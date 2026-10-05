import 'dart:ui' show Size;
import 'dart:io';
import 'package:window_manager/window_manager.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

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

Future<void> initDesktopWindow() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(420, 560));
  await windowManager.setTitle('Vaulton');
}

void setCloseGuard(bool Function() hasActiveWork, Future<bool> Function() askMinimize) {
  if (!isDesktop) return;
  windowManager.setPreventClose(true);
  windowManager.addListener(_Guard(hasActiveWork, askMinimize));
}
