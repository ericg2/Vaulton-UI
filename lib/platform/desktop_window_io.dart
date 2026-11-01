import 'dart:ui' show Size;
import 'dart:io';
import 'package:window_manager/window_manager.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

_Guard? _closeGuard;

class _Guard with WindowListener {
  _Guard(this.hasWork, this.ask);
  final bool Function() hasWork;
  final Future<bool> Function() ask;
  @override
  void onWindowClose() async {
    if (!hasWork()) {
      await windowManager.setPreventClose(false);
      await windowManager.close();
      return;
    }
    // true => minimise and keep transferring, false => really quit.
    if (await ask()) {
      await windowManager.minimize();
    } else {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }
}

Future<void> clearCloseGuard() async {
  if (!isDesktop) return;
  if (_closeGuard != null) {
    windowManager.removeListener(_closeGuard!);
    _closeGuard = null;
  }
  await windowManager.setPreventClose(false);
}

Future<void> initDesktopWindow() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(420, 560));
  await windowManager.setTitle('Vaulton');
  await windowManager.setPreventClose(false);
}

void setCloseGuard(bool Function() hasActiveWork, Future<bool> Function() askMinimize) {
  if (!isDesktop) return;
  if (_closeGuard != null) windowManager.removeListener(_closeGuard!);
  _closeGuard = _Guard(hasActiveWork, askMinimize);
  windowManager.addListener(_closeGuard!);
  windowManager.setPreventClose(true);

}
