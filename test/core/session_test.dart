import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/session.dart';

void main() {
  group('SessionStore.isSameServer', () {
    test('treats the default port and explicit port as the same server', () {
      expect(
        SessionStore.isSameServer('https://vaulton.example', 'https://vaulton.example:5141/'),
        isTrue,
      );
    });

    test('treats different hosts as different servers', () {
      expect(
        SessionStore.isSameServer('https://vaulton.example', 'https://other.example'),
        isFalse,
      );
    });

    test('treats different schemes as different servers', () {
      expect(
        SessionStore.isSameServer('http://vaulton.example', 'https://vaulton.example'),
        isFalse,
      );
    });

    test('treats different non-default ports as different servers', () {
      expect(
        SessionStore.isSameServer('https://vaulton.example:5141', 'https://vaulton.example:8443'),
        isFalse,
      );
    });
  });
}
