/// Web build of the window helpers: everything is a no-op.
library;

/// Initializes the native window (no-op on web).
Future<void> initWindow() async {}

/// Sets the native window title (no-op on web).
Future<void> setWindowTitle(String title) async {}

/// Enables or disables close interception (no-op on web).
Future<void> setPreventCloseEnabled(bool enabled) async {}

/// Registers [handler] to run when the user tries to close the window;
/// pass null to unregister (no-op on web).
void setWindowCloseHandler(Future<void> Function()? handler) {}

/// Destroys the window, bypassing the close handler (no-op on web).
Future<void> destroyWindow() async {}
