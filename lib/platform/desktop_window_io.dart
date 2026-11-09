import 'dart:async';
import 'dart:ui' show Size;
import 'dart:io';

import 'package:window_manager/window_manager.dart';

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Window? get _currentWindow => WindowManager.instance.getCurrent();

ListenerId? _closeListener;

Future<void> clearCloseGuard() async {
  if (!isDesktop) return;
  final listener = _closeListener;
  _closeListener = null;
  if (listener != null) _currentWindow?.removeListener(listener);
}

Future<void> initDesktopWindow() async {
  if (!isDesktop) return;
  final window = _currentWindow;
  if (window == null) return;
  window.minimumSize = const Size(420, 560).toNative();
  window.title = 'Vaulton';
}

void setCloseGuard(
  bool Function() hasActiveWork,
  Future<bool> Function() askMinimize,
) {
  if (!isDesktop) return;
  final window = _currentWindow;
  if (window == null) return;
  final previous = _closeListener;
  if (previous != null) window.removeListener(previous);
  _closeListener = window.addListener((event) async {
    if (event is! WindowCloseRequestedEvent || !hasActiveWork()) return;
    // true => minimise and keep transferring, false => really quit.
    if (await askMinimize()) {
      event.request.cancel();
      window.minimize();
    }
  });
}
