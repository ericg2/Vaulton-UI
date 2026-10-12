import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../platform/desktop_window.dart';
import 'api_client.dart';
import 'models.dart';
import 'session.dart';
import 'vaulton.dart';
import 'wake.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final sessionProvider = Provider<SessionStore>((ref) => throw UnimplementedError());

final apiClientProvider = Provider<ApiClient>((ref) {
  final c = ApiClient(ref.watch(sessionProvider));
  c.onSignedOut = () => ref.read(authProvider.notifier).sessionExpired();
  return c;
});
final vaultonProvider = Provider<Vaulton>((ref) => Vaulton(ref.watch(apiClientProvider)));

// ------------------------------------------------------------- settings
class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system, this.concurrency = 3, this.downloadDir, this.lastPointId});
  final ThemeMode themeMode;
  final int concurrency;
  final String? downloadDir, lastPointId;
  AppSettings copyWith({ThemeMode? themeMode, int? concurrency, String? downloadDir, String? lastPointId, bool clearDir = false}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        concurrency: concurrency ?? this.concurrency,
        downloadDir: clearDir ? null : (downloadDir ?? this.downloadDir),
        lastPointId: lastPointId ?? this.lastPointId,
      );
}

class SettingsController extends Notifier<AppSettings> {
  SharedPreferences get _p => ref.read(prefsProvider);
  @override
  AppSettings build() => AppSettings(
        themeMode: ThemeMode.values.firstWhere((m) => m.name == _p.getString('themeMode'), orElse: () => ThemeMode.system),
        concurrency: _p.getInt('concurrency') ?? 3,
        // A custom download folder only works on desktop (scoped storage blocks it on Android).
        downloadDir: isDesktop ? _p.getString('downloadDir') : null,
        lastPointId: _p.getString('lastPointId'),
      );

  void setTheme(ThemeMode m) {
    _p.setString('themeMode', m.name);
    state = state.copyWith(themeMode: m);
  }

  void setConcurrency(int n) {
    _p.setInt('concurrency', n);
    state = state.copyWith(concurrency: n);
  }

  void setDownloadDir(String? d) {
    if (d == null) {
      _p.remove('downloadDir');
      state = state.copyWith(clearDir: true);
    } else {
      _p.setString('downloadDir', d);
      state = state.copyWith(downloadDir: d);
    }
  }

  void setLastPoint(String id) {
    _p.setString('lastPointId', id);
    state = state.copyWith(lastPointId: id);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

// ----------------------------------------------------------------- auth
enum AuthStatus { loading, signedOut, signedIn }

class AuthState {
  const AuthState(this.status, {this.user, this.message});
  final AuthStatus status;
  final UserAccount? user;
  final String? message;
}

class AuthController extends Notifier<AuthState> {
  int _restoreGeneration = 0;
  @override
  AuthState build() {
    // No saved session -> go straight to the login form (no splash flash).
    if (!ref.read(sessionProvider).isSignedIn) return const AuthState(AuthStatus.signedOut);
    Future.microtask(_restore);
    return const AuthState(AuthStatus.loading);
  }

  SessionStore get _s => ref.read(sessionProvider);
  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _restore() async {
    final generation = ++_restoreGeneration;
    if (!_s.isSignedIn) {
      state = const AuthState(AuthStatus.signedOut);
      return;
    }
    final started = DateTime.now();
    // Keep the splash up for a moment even on a fast connection so the
    // transition into the app is smooth instead of a hard flash.
    Future<void> settle() async {
      final left = const Duration(milliseconds: 900) - DateTime.now().difference(started);
      if (left > Duration.zero) await Future.delayed(left);
    }

    try {
      final u = await _v.me().timeout(const Duration(seconds: 8));
      try {
        await WakeService.refreshConfig(_v, _s);
      } catch (_) {
        // Keep the cached wake token if the server is temporarily unavailable.
      }
      await settle();
      if (generation != _restoreGeneration) return;
      state = AuthState(AuthStatus.signedIn, user: u);
    } catch (e) {
      // Network/timeout errors should return control to the login screen quickly.
      if (generation != _restoreGeneration) return;
      await settle();
      if (generation != _restoreGeneration) return;
      final ex = ApiException.from(e);
      if (ex.status == null) {
        state = const AuthState(AuthStatus.signedOut, message: 'Server unreachable. Check the address and sign in again.');
      } else {
        state = const AuthState(AuthStatus.signedOut);
      }
    }
  }

  void cancelRestore() {
    _restoreGeneration++;
    if (state.status == AuthStatus.loading) {
      state = const AuthState(AuthStatus.signedOut);
    }
  }

  Future<void> signIn(String url, String user, String pass, {String? newPassword, CancelToken? cancelToken}) async {
    await _s.setBaseUrl(url);
    cancelToken?.throwIfCancelled();
    final t = await _v.signIn(user, pass, newPassword: newPassword, cancelToken: cancelToken);
    try {
      cancelToken?.throwIfCancelled();
      await _s.setTokens(t);
      cancelToken?.throwIfCancelled();
      await _s.setUser(user);
      cancelToken?.throwIfCancelled();
      final u = await _v.me(cancelToken: cancelToken);
      cancelToken?.throwIfCancelled();
      await WakeService.refreshConfig(_v, _s, cancelToken: cancelToken);
      cancelToken?.throwIfCancelled();
      ref.read(accountsProvider.notifier).remember(url, user);
      state = AuthState(AuthStatus.signedIn, user: u);
    } catch (_) {
      if (cancelToken?.isCancelled == true) await _s.clearTokensIf(t.refresh);
      rethrow;
    }
  }

  Future<void> refreshUser() async {
    final u = await _v.me();
    state = AuthState(AuthStatus.signedIn, user: u);
  }

  Future<void> signOut() async {
    // Signing out is a local action and must work even when the server is offline.
    // Clear credentials before any optional network cleanup can delay navigation.
    await _s.clear();
    state = const AuthState(AuthStatus.signedOut);
  }

  void sessionExpired() {
    state = const AuthState(AuthStatus.signedOut, message: 'Your session expired. Please sign in again.');
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
final userProvider = Provider<UserAccount?>((ref) => ref.watch(authProvider).user);

/// True while a user is signed in. Pollers below watch it so they stop on sign-out
/// and restart (with fresh data) when another account signs in.
final _signedInUserProvider = Provider<String?>((ref) {
  final a = ref.watch(authProvider);
  return a.status == AuthStatus.signedIn ? a.user?.userName : null;
});

final unreadProvider = StreamProvider<int>((ref) async* {
  final v = ref.watch(vaultonProvider);
  if (ref.watch(_signedInUserProvider) == null) return;
  var alive = true;
  ref.onDispose(() => alive = false);
  while (alive) {
    try {
      final n = await v.unreadCount();
      if (!alive) return;
      yield n;
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 60));
  }
});


// ------------------------------------------------- shared lookups / refresh
/// id -> display name for every data folder and backup vault (used to label jobs).
final pointNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final v = ref.watch(vaultonProvider);
  ref.watch(_signedInUserProvider);
  final out = <String, String>{};
  for (final fetch in [(String? c) => v.datas(cursor: c, limit: 200), (String? c) => v.repos(cursor: c, limit: 200)]) {
    String? cur;
    do {
      final p = await fetch(cur);
      for (final x in p.items) {
        out[x.id] = x.name;
      }
      cur = p.hasMore ? p.nextCursor : null;
    } while (cur != null);
  }
  return out;
});

/// Bumped whenever something changes server-side (upload finished, job queued...)
/// so dashboards and lists can reload without a manual refresh.
class EpochNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final epochProvider = NotifierProvider<EpochNotifier, int>(EpochNotifier.new);

/// Basic server facts for the sidebar. `/admin/status` is used when permitted.
class ServerInfo {
  const ServerInfo({required this.host, this.version, this.environment, this.reachable = true, this.uptime});
  final String host;
  final String? version, environment;
  final bool reachable;
  final Duration? uptime;
}

final serverInfoProvider = StreamProvider<ServerInfo>((ref) async* {
  final v = ref.watch(vaultonProvider);
  final session = ref.watch(sessionProvider);
  if (ref.watch(_signedInUserProvider) == null) return;
  final host = Uri.tryParse(session.baseUrl)?.authority ?? session.baseUrl;
  var alive = true;
  ref.onDispose(() => alive = false);
  while (alive) {
    try {
      final s = await v.status();
      if (!alive) return;
      yield ServerInfo(
        host: host,
        version: toStr(s['version']),
        environment: toStr(s['environment']),
        reachable: toBool(s['backendReachable']),
        uptime: Duration(seconds: toInt(s['uptimeSeconds'])),
      );
    } catch (e) {
      if (!alive) return;
      final ex = ApiException.from(e);
      yield ServerInfo(host: host, reachable: ex.status != null);
    }
    await Future.delayed(const Duration(seconds: 15));
  }
});

// ------------------------------------------------------- saved accounts
/// A server + user the person has signed in with before (no secrets stored).
class SavedAccount {
  const SavedAccount(this.url, this.user, this.lastUsed);
  final String url, user;
  final int lastUsed;
  String get host => Uri.tryParse(url)?.authority.isNotEmpty == true ? Uri.parse(url).authority : url;
  Map<String, dynamic> toJson() => {'url': url, 'user': user, 'last': lastUsed};
  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount('${j['url']}', '${j['user']}', (j['last'] as num?)?.toInt() ?? 0);
}

class AccountsController extends Notifier<List<SavedAccount>> {
  static const _k = 'accounts_v1';
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  List<SavedAccount> build() {
    try {
      final l = (jsonDecode(_p.getString(_k) ?? '[]') as List).map((e) => SavedAccount.fromJson(Map<String, dynamic>.from(e))).toList();
      l.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return l;
    } catch (_) {
      return [];
    }
  }

  void _save(List<SavedAccount> l) {
    state = l;
    _p.setString(_k, jsonEncode([for (final a in l) a.toJson()]));
  }

  void remember(String url, String user) {
    final u = SessionStore.normalizeUrl(url);
    final l = state.where((a) => !(a.url == u && a.user.toLowerCase() == user.toLowerCase())).toList();
    _save([SavedAccount(u, user, DateTime.now().millisecondsSinceEpoch), ...l]);
  }

  void forget(SavedAccount a) => _save(state.where((x) => !(x.url == a.url && x.user == a.user)).toList());
}

final accountsProvider = NotifierProvider<AccountsController, List<SavedAccount>>(AccountsController.new);
