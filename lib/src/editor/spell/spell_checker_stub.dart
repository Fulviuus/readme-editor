/// Web build: no system spell checker.
library;

import 'package:flutter/widgets.dart' show TextRange;

class SpellChecker {
  static bool get supported => false;

  static Future<List<TextRange>> check(String text) async => const [];

  static Future<List<String>> suggest(String word) async => const [];

  static Future<void> learn(String word) async {}

  static Future<void> ignore(String word) async {}
}
