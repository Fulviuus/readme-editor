/// Desktop implementation of the window helpers, backed by window_manager.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Initializes the native window: minimum size and initial title.
Future<void> initWindow() async {
  if (!_isDesktop) return;
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(640, 480));
  await windowManager.setTitle('readme');
}

/// Sets the native window title.
Future<void> setWindowTitle(String title) async {
  if (!_isDesktop) return;
  await windowManager.setTitle(title);
}

/// Enables or disables close interception ([setWindowCloseHandler]).
Future<void> setPreventCloseEnabled(bool enabled) async {
  if (!_isDesktop) return;
  await windowManager.setPreventClose(enabled);
}

_CloseListener? _closeListener;

/// Registers [handler] to run when the user tries to close the window;
/// pass null to unregister. Only fires while prevent-close is enabled.
void setWindowCloseHandler(Future<void> Function()? handler) {
  if (!_isDesktop) return;
  final previous = _closeListener;
  if (previous != null) {
    windowManager.removeListener(previous);
    _closeListener = null;
  }
  if (handler != null) {
    final listener = _CloseListener(handler);
    _closeListener = listener;
    windowManager.addListener(listener);
  }
}

/// Destroys the window for real, bypassing the close handler.
Future<void> destroyWindow() async {
  if (!_isDesktop) return;
  await windowManager.destroy();
}

/// Hides the window without quitting (Preferences > General keeps the app
/// alive when the window closes; Dock reopen brings it back).
Future<void> hideWindow() async {
  if (!_isDesktop) return;
  await windowManager.hide();
}

class _CloseListener with WindowListener {
  _CloseListener(this.handler);

  final Future<void> Function() handler;

  @override
  void onWindowClose() {
    handler();
  }
}

/// Pins the window above all others (View > Always on Top).
Future<void> setWindowAlwaysOnTop(bool enabled) async {
  if (!_isDesktop) return;
  await windowManager.setAlwaysOnTop(enabled);
}

/// Minimizes the window (Window > Minimize on non-macOS menus).
Future<void> minimizeWindow() async {
  if (!_isDesktop) return;
  await windowManager.minimize();
}

/// Zooms/maximizes the window (Window > Zoom on non-macOS menus).
Future<void> zoomWindow() async {
  if (!_isDesktop) return;
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Toggles full screen (View > Full Screen on non-macOS menus).
Future<void> toggleFullScreenWindow() async {
  if (!_isDesktop) return;
  await windowManager.setFullScreen(!await windowManager.isFullScreen());
}
