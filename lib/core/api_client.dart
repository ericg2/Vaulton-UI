import 'dart:async';
import 'package:dio/dio.dart';
import 'session.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.title});
  final String message;
  final int? status;
  final String? title;

  bool get isForbidden => status == 403;
  bool get isConflict => status == 409;
  bool get isNotFound => status == 404;
  bool get isCancelled => message == 'Cancelled';

  @override
  String toString() => message;

  static ApiException from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final r = e.response;
      if (r != null) {
        final d = r.data;
        String? detail;
        String? title;
        if (d is Map) {
          detail = d['detail']?.toString();
          title = d['title']?.toString();
          final errs = d['errors'];
          if (errs is Map && errs.isNotEmpty) {
            final lines = <String>[];
            for (final v in errs.values) {
              if (v is List) {
                lines.addAll(v.map((x) => '$x'));
              } else {
                lines.add('$v');
              }
            }
            detail = [?detail, ...lines].join('\n');
          }
        } else if (d is String && d.isNotEmpty && d.length < 400) {
          detail = d;
        }
        final fallback = r.statusCode == 403
            ? 'You do not have permission to do this.'
            : r.statusCode == 401
                ? 'Not signed in.'
                : 'Request failed (${r.statusCode})';
        return ApiException(detail ?? title ?? fallback, status: r.statusCode, title: title);
      }
      if (e.type == DioExceptionType.cancel) return ApiException('Cancelled');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        return ApiException('Cannot reach the server. Check the address and your connection.');
      }
      return ApiException('Network error: ${e.message ?? e.error}');
    }
    return ApiException(e.toString());
  }
}

class ApiClient {
  ApiClient(this.session) {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      headers: {'Accept': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final SessionStore session;
  late final Dio dio;
  void Function()? onSignedOut;
  Future<bool>? _refreshing;

  Future<void> _onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    o.baseUrl = session.baseUrl;
    if (o.extra['noAuth'] != true) {
      final exp = session.expiresAt;
      if (session.refreshToken != null &&
          exp != null &&
          exp.isBefore(DateTime.now().add(const Duration(seconds: 45)))) {
        await refresh();
      }
      final t = session.accessToken;
      if (t != null) o.headers['Authorization'] = 'Bearer $t';
    }
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    if (e.response?.statusCode == 401 &&
        o.extra['noAuth'] != true &&
        o.extra['retried'] != true &&
        o.data is! Stream) {
      if (await refresh()) {
        o.extra['retried'] = true;
        o.headers['Authorization'] = 'Bearer ${session.accessToken}';
        try {
          return h.resolve(await dio.fetch(o));
        } on DioException catch (e2) {
          return h.next(e2);
        }
      }
    }
    h.next(e);
  }

  /// Refresh tokens are single-use, so concurrent callers share one request and
  /// we first re-read storage in case another isolate already rotated them.
  Future<bool> refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final before = session.refreshToken;
    await session.load();
    if (session.refreshToken != before &&
        session.expiresAt != null &&
        session.expiresAt!.isAfter(DateTime.now().add(const Duration(seconds: 45)))) {
      return true; // another isolate already refreshed
    }
    final rt = session.refreshToken;
    if (rt == null) return false;
    try {
      final r = await Dio(BaseOptions(baseUrl: session.baseUrl, connectTimeout: const Duration(seconds: 8)))
          .post('/auth/refresh', data: {'refreshToken': rt});
      await session.setTokens(AuthTokens.fromJson(Map<String, dynamic>.from(r.data)));
      return true;
    } on DioException catch (e) {
      final s = e.response?.statusCode;
      if (s == 400 || s == 401 || s == 403) {
        await session.load();
        if (session.refreshToken != rt) return true;
        await session.clear();
        onSignedOut?.call();
      }
      return false;
    }
  }
}
