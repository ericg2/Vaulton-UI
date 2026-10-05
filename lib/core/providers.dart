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
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState(AuthStatus.loading);
  }

  SessionStore get _s => ref.read(sessionProvider);
  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _restore() async {
    if (!_s.isSignedIn) {
      state = const AuthState(AuthStatus.signedOut);
      return;
    }
    try {
      final u = await _v.me();
      state = AuthState(AuthStatus.signedIn, user: u);
    } on ApiException catch (e) {
      // Network error: stay signed in locally so offline-capable screens work.
      if (e.status == null) {
        state = const AuthState(AuthStatus.signedOut, message: 'Server unreachable. Check the address and sign in again.');
      } else {
        state = const AuthState(AuthStatus.signedOut);
      }
    }
  }

  Future<void> signIn(String url, String user, String pass, {String? newPassword}) async {
    await _s.setBaseUrl(url);
    final t = await _v.signIn(user, pass, newPassword: newPassword);
    await _s.setTokens(t);
    await _s.setUser(user);
    ref.read(accountsProvider.notifier).remember(url, user);
    final u = await _v.me();
    state = AuthState(AuthStatus.signedIn, user: u);
  }

  Future<void> refreshUser() async {
    final u = await _v.me();
    state = AuthState(AuthStatus.signedIn, user: u);
  }

  Future<void> signOut() async {
    await _v.signOut();
    await _s.clear();
    state = const AuthState(AuthStatus.signedOut);
  }

  void sessionExpired() {
    state = const AuthState(AuthStatus.signedOut, message: 'Your session expired. Please sign in again.');
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
final userProvider = Provider<UserAccount?>((ref) => ref.watch(authProvider).user);

final unreadProvider = StreamProvider<int>((ref) async* {
  final v = ref.watch(vaultonProvider);
  while (true) {
    try {
      yield await v.unreadCount();
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 60));
  }
});


// ------------------------------------------------- shared lookups / refresh
/// id -> display name for every data point and repository (used to label jobs).
final pointNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final v = ref.watch(vaultonProvider);
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
  final host = Uri.tryParse(session.baseUrl)?.authority ?? session.baseUrl;
  while (true) {
    try {
      final s = await v.status();
      yield ServerInfo(
        host: host,
        version: toStr(s['version']),
        environment: toStr(s['environment']),
        reachable: toBool(s['backendReachable']),
        uptime: Duration(seconds: toInt(s['uptimeSeconds'])),
      );
    } catch (e) {
      final ex = ApiException.from(e);
      yield ServerInfo(host: host, reachable: ex.status != null);
    }
    await Future.delayed(const Duration(seconds: 30));
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
