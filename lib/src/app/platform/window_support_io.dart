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

class _CloseListener with WindowListener {
  _CloseListener(this.handler);

  final Future<void> Function() handler;

  @override
  void onWindowClose() {
    handler();
  }
}
