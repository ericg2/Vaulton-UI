import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  AuthTokens({required this.access, required this.refresh, required this.expiresAt});
  final String access;
  final String refresh;
  final DateTime expiresAt;

  factory AuthTokens.fromJson(Map<String, dynamic> j) {
    final raw = j['expiresIn'];
    final secs = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 3600;
    return AuthTokens(
      access: '${j['accessToken']}',
      refresh: '${j['refreshToken']}',
      expiresAt: DateTime.now().add(Duration(seconds: secs)),
    );
  }
}

/// Persists server URL + tokens in the platform secure store. Safe to use from
/// background isolates (WorkManager) because it re-reads storage on demand.
class SessionStore {
  // Android uses the plugin's default Keystore-backed ciphers
  // (encryptedSharedPreferences was removed in flutter_secure_storage 11).
  static const _st = FlutterSecureStorage();

  String baseUrl = 'http://localhost:5141';
  String? accessToken;
  String? refreshToken;
  String? userName;
  DateTime? expiresAt;

  bool get isSignedIn => refreshToken != null && refreshToken!.isNotEmpty;

  static String normalizeUrl(String u) {
    var s = u.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> load() async {
    final m = await _st.readAll();
    baseUrl = m['baseUrl'] ?? baseUrl;
    accessToken = m['access'];
    refreshToken = m['refresh'];
    userName = m['user'];
    final e = int.tryParse(m['exp'] ?? '');
    expiresAt = e == null ? null : DateTime.fromMillisecondsSinceEpoch(e);
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = normalizeUrl(url);
    await _st.write(key: 'baseUrl', value: baseUrl);
  }

  Future<void> setUser(String name) async {
    userName = name;
    await _st.write(key: 'user', value: name);
  }

  Future<void> setTokens(AuthTokens t) async {
    accessToken = t.access;
    refreshToken = t.refresh;
    expiresAt = t.expiresAt;
    await _st.write(key: 'access', value: t.access);
    await _st.write(key: 'refresh', value: t.refresh);
    await _st.write(key: 'exp', value: '${t.expiresAt.millisecondsSinceEpoch}');
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
    for (final k in ['access', 'refresh', 'exp', 'user']) {
      await _st.delete(key: k);
    }
  }
}
