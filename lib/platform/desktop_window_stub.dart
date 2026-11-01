bool get isDesktop => false;
Future<void> initDesktopWindow() async {}
void setCloseGuard(bool Function() hasActiveWork, Future<bool> Function() askMinimize) {}
void clearCloseGuard() {}
