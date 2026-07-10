/// App entry: theme loading, native window setup, then [ReadmeApp].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app/app.dart';
import 'src/app/platform/window_support.dart';
import 'src/theme/theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeManager = ThemeManager();
  await themeManager.init();
  if (!kIsWeb) {
    await initWindow();
  }
  runApp(ReadmeApp(themeManager: themeManager));
}
