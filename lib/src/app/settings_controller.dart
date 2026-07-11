/// User preferences beyond theme/zoom (which live on ThemeManager) and
/// autosave (WorkspaceController): editor text-substitution and line-break
/// behavior. Persisted via SharedPreferences.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends ChangeNotifier {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static const _kSmartQuotes = 'smartQuotes';
  static const _kSmartDashes = 'smartDashes';
  static const _kPreserveLineBreak = 'preserveSingleLineBreak';
  static const _kVisibleBr = 'visibleBr';
  static const _kSpellCheck = 'spellCheck';

  bool _smartQuotes = false;
  bool _smartDashes = false;
  bool _preserveSingleLineBreak = true;
  bool _visibleBr = false;
  bool _spellCheck = true;

  /// Convert straight quotes to curly while typing.
  bool get smartQuotes => _smartQuotes;

  /// Convert `--` to an em dash while typing.
  bool get smartDashes => _smartDashes;

  /// Render a single `\n` inside a paragraph as a line break (true, the
  /// default) or as a space (CommonMark strictness).
  bool get preserveSingleLineBreak => _preserveSingleLineBreak;

  /// Show `<br>` tags as a dimmed `↵` glyph instead of hiding them.
  bool get visibleBr => _visibleBr;

  /// Squiggle misspellings in the block being edited (system spell checker;
  /// native platforms only).
  bool get spellCheck => _spellCheck;

  Future<void> load() async {
    try {
      _smartQuotes = await _prefs.getBool(_kSmartQuotes) ?? false;
      _smartDashes = await _prefs.getBool(_kSmartDashes) ?? false;
      _preserveSingleLineBreak =
          await _prefs.getBool(_kPreserveLineBreak) ?? true;
      _visibleBr = await _prefs.getBool(_kVisibleBr) ?? false;
      _spellCheck = await _prefs.getBool(_kSpellCheck) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _set(String key, bool value, void Function() apply) async {
    apply();
    notifyListeners();
    try {
      await _prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> setSmartQuotes(bool v) =>
      _set(_kSmartQuotes, v, () => _smartQuotes = v);
  Future<void> setSmartDashes(bool v) =>
      _set(_kSmartDashes, v, () => _smartDashes = v);
  Future<void> setPreserveSingleLineBreak(bool v) =>
      _set(_kPreserveLineBreak, v, () => _preserveSingleLineBreak = v);
  Future<void> setVisibleBr(bool v) =>
      _set(_kVisibleBr, v, () => _visibleBr = v);
  Future<void> setSpellCheck(bool v) =>
      _set(_kSpellCheck, v, () => _spellCheck = v);
}
