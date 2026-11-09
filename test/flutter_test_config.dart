// desktop_drop 0.9 talks to its native plugin through FFI, which is not
// available in widget tests. Use the package's testing seam for the lifetime
// of the test process.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:desktop_drop/src/native_transport.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final transport = NativeTransport.testing();
  transport.invokeHandler = (call) async {
    if (call.method == 'initialize') {
      final arguments = call.arguments as Map;
      return {'view': arguments['view'], 'generation': 1};
    }
    return null;
  };
  NativeTransport.debugOverride = transport;
  await testMain();
}
