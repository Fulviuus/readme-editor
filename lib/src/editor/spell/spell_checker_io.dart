/// Native platforms: the system spell checker over the `readme/spell`
/// platform channel (registered by the macOS runner). Range offsets are
/// UTF-16 code units on both sides, so they map 1:1 onto Dart strings.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class SpellChecker {
  static const _channel = MethodChannel('readme/spell');

  /// Flips false on the first channel failure (non-macOS desktop) so the
  /// editor stops asking.
  static bool _available = Platform.isMacOS;
  static bool get supported => _available;

  static Future<List<TextRange>> check(String text) async {
    if (!_available || text.isEmpty) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
          'check', {'text': text});
      return [
        for (final e in raw ?? const [])
          if (e is List && e.length == 2)
            TextRange(start: e[0] as int, end: (e[0] as int) + (e[1] as int)),
      ];
    } on MissingPluginException {
      _available = false;
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<List<String>> suggest(String word) async {
    if (!_available) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
          'suggest', {'word': word});
      return [...?raw?.cast<String>()];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      _available = false;
      return const [];
    }
  }

  static Future<void> learn(String word) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('learn', {'word': word});
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      _available = false;
    }
  }

  static Future<void> ignore(String word) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('ignore', {'word': word});
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      _available = false;
    }
  }
}
