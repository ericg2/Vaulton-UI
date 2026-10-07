import 'dart:async';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'session.dart';
import 'vaulton.dart';

class WakeService {
  static Future<void> refreshConfig(Vaulton vaulton, SessionStore session) async {
    try {
      final d = await vaulton.wakeConfig();
      if (_bool(d['enabled']) && _str(d['brokerUrl']).isNotEmpty && _str(d['wakeToken']).isNotEmpty) {
        await session.setWakeConfig(
          brokerUrl: _str(d['brokerUrl']),
          token: _str(d['wakeToken']),
          wakeBeforeMinutes: _int(d['wakeBeforeMinutes']),
        );
      } else {
        await session.clearWakeConfig();
      }
    } on ApiException catch (e) {
      if (!e.isForbidden && e.status != null) rethrow;
    }
  }

  static Future<void> wake(SessionStore session) async {
    final url = session.wakeBrokerUrl;
    final token = session.wakeToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw ApiException('Server wake is not configured.');
    }

    try {
      await Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
      )).post(
        '/wake',
        options: Options(headers: {'X-Wake-Token': token}),
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  static Future<bool> ensureReady(ApiClient api) async {
    final ready = Dio(BaseOptions(
      baseUrl: api.session.baseUrl,
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ));

    try {
      final response = await ready.get('/health/ready');
      if ((response.statusCode ?? 500) >= 200 && (response.statusCode ?? 500) < 300) {
        return true;
      }
    } catch (_) {}

    try {
      await wake(api.session);
    } catch (_) {
      return false;
    }

    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final response = await ready.get('/health/ready');
        if ((response.statusCode ?? 500) >= 200 && (response.statusCode ?? 500) < 300) {
          return true;
        }
      } catch (_) {}
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
