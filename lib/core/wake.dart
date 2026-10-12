import 'dart:async';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'session.dart';
import 'vaulton.dart';

class WakeService {
  static Future<void> refreshConfig(
    Vaulton vaulton,
    SessionStore session,
  ) async {
    try {
      final data = await vaulton.wakeConfig();
      if (_bool(data['enabled']) &&
          _str(data['brokerUrl']).isNotEmpty &&
          _str(data['wakeToken']).isNotEmpty) {
        await session.setWakeConfig(
          brokerUrl: _str(data['brokerUrl']),
          token: _str(data['wakeToken']),
          wakeBeforeMinutes: _int(data['wakeBeforeMinutes']),
        );
      } else {
        await session.clearWakeConfig();
      }
    } on ApiException catch (e) {
      if (e.isForbidden) {
        await session.clearWakeConfig();
      } else if (e.status != null) {
        rethrow;
      }
    }
  }

  static Future<void> wake(SessionStore session, {CancelToken? cancelToken}) async {
    final rawUrl = session.wakeBrokerUrl;
    final token = session.wakeToken;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        token == null ||
        token.length < 32) {
      throw ApiException('Server wake is not configured.');
    }

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: uri.toString().replaceFirst(RegExp(r'/+$'), ''),
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      await dio.post(
        '/wake',
        cancelToken: cancelToken,
        options: Options(
          headers: {'X-Wake-Token': token},
        ),
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  static Future<bool> ensureReady(ApiClient api, {CancelToken? cancelToken}) async {
    final ready = Dio(
      BaseOptions(
        baseUrl: api.session.baseUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      ),
    );

    try {
      final response = await ready.get('/health/ready', cancelToken: cancelToken);
      final status = response.statusCode ?? 500;
      if (status >= 200 && status < 300) {
        return true;
      }
    } catch (_) {
      if (cancelToken?.isCancelled == true) throw ApiException('Cancelled');
    }

    if (cancelToken?.isCancelled == true) throw ApiException('Cancelled');
    if (!api.session.hasWakeConfigFor(api.session.baseUrl)) return false;

    try {
      await wake(api.session, cancelToken: cancelToken);
    } catch (_) {
      if (cancelToken?.isCancelled == true) throw ApiException('Cancelled');
      return false;
    }

    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (cancelToken?.isCancelled == true) throw ApiException('Cancelled');
      await Future<void>.delayed(const Duration(seconds: 2));
      if (cancelToken?.isCancelled == true) throw ApiException('Cancelled');

      try {
        final response = await ready.get('/health/ready', cancelToken: cancelToken);
        final status = response.statusCode ?? 500;
        if (status >= 200 && status < 300) {
          return true;
        }
      } catch (_) {
        if (cancelToken?.isCancelled == true) throw ApiException('Cancelled');
      }
    }

    return false;
  }

  static String _str(dynamic value) => value?.toString() ?? '';

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
