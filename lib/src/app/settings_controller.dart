/// User preferences beyond theme/zoom (which live on ThemeManager) and
/// autosave (WorkspaceController). Persisted via SharedPreferences.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends ChangeNotifier {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  // ---- General / files ----
  /// 'new' opens an empty document on launch; 'reopenLast' restores the
  /// most recent file.
  String launchAction = 'new';

  /// Extension for new documents and Save As ('md' | 'markdown' | 'txt').
  String defaultExtension = 'md';

  /// Save (instead of prompting) when switching files from the sidebar
  /// while the current document is dirty and has a path.
  bool saveOnFileSwitch = false;

  /// Track recently opened files for File > Open Recent.
  bool recordRecentFiles = true;

  /// Silently check the release feed at startup; only speaks up when an
  /// update exists.
  bool checkUpdatesAutomatically = false;

  // ---- Editor ----
  bool spellCheck = true;
  bool smartQuotes = false;
  bool smartDashes = false;

  /// Typing `(`, `[`, `{`, `"` or `'` inserts the closing pair.
  bool autoPairBrackets = false;

  /// Typing `*`, `_`, `~` or a backtick inserts the closing marker too.
  bool autoPairMarkdown = false;

  // ---- Image ----
  bool copyImagesToAssets = false;

  /// Link inserted images relative to the document when possible.
  bool relativeImagePaths = true;

  /// Prefix relative image links with `./`.
  bool dotSlashImagePaths = false;

  // ---- Markdown ----
  /// Marker used when converting to an unordered list ('-' | '*' | '+').
  String bulletMarker = '-';

  /// Render `$…$` as inline math (off leaves it literal text).
  bool inlineMath = true;

  /// Render diagram code fences as diagrams.
  bool diagrams = true;

  /// Line-number gutter on code blocks.
  bool codeLineNumbers = false;

  bool preserveSingleLineBreak = true;
  bool visibleBr = false;

  // ---- Export ----
  /// Explicit pandoc executable path; empty means auto-discover.
  String pandocPath = '';

  /// Reveal exported files in the file manager after a successful export.
  bool revealAfterExport = false;

  // ---- Window/sidebar state (restored on launch) ----
  bool sidebarVisible = true;
  String sidebarPane = 'fileTree';

  /// True once [load] has completed (with stored values or defaults) —
  /// consumers restoring UI state wait for this.
  bool get loaded => _loaded;
  bool _loaded = false;

  Future<void> load() async {
    try {
      launchAction = await _prefs.getString('launchAction') ?? 'new';
      defaultExtension = await _prefs.getString('defaultExtension') ?? 'md';
      saveOnFileSwitch = await _prefs.getBool('saveOnFileSwitch') ?? false;
      recordRecentFiles = await _prefs.getBool('recordRecentFiles') ?? true;
      checkUpdatesAutomatically =
          await _prefs.getBool('checkUpdatesAutomatically') ?? false;
      spellCheck = await _prefs.getBool('spellCheck') ?? true;
      smartQuotes = await _prefs.getBool('smartQuotes') ?? false;
      smartDashes = await _prefs.getBool('smartDashes') ?? false;
      autoPairBrackets = await _prefs.getBool('autoPairBrackets') ?? false;
      autoPairMarkdown = await _prefs.getBool('autoPairMarkdown') ?? false;
      copyImagesToAssets =
          await _prefs.getBool('copyImagesToAssets') ?? false;
      relativeImagePaths =
          await _prefs.getBool('relativeImagePaths') ?? true;
      dotSlashImagePaths =
          await _prefs.getBool('dotSlashImagePaths') ?? false;
      bulletMarker = await _prefs.getString('bulletMarker') ?? '-';
      inlineMath = await _prefs.getBool('inlineMath') ?? true;
      diagrams = await _prefs.getBool('diagrams') ?? true;
      codeLineNumbers = await _prefs.getBool('codeLineNumbers') ?? false;
      preserveSingleLineBreak =
          await _prefs.getBool('preserveSingleLineBreak') ?? true;
      visibleBr = await _prefs.getBool('visibleBr') ?? false;
      pandocPath = await _prefs.getString('pandocPath') ?? '';
      revealAfterExport = await _prefs.getBool('revealAfterExport') ?? false;
      sidebarVisible = await _prefs.getBool('sidebarVisible') ?? true;
      sidebarPane = await _prefs.getString('sidebarPane') ?? 'fileTree';
    } catch (_) {
      // Unreadable prefs: keep the defaults.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Applies and persists one setting (best-effort write).
  Future<void> update(String key, Object value, void Function() apply) async {
    apply();
    notifyListeners();
    try {
      if (value is bool) {
        await _prefs.setBool(key, value);
      } else if (value is String) {
        await _prefs.setString(key, value);
      }
    } catch (_) {}
  }

  // Convenience setters kept for existing call sites.
  Future<void> setSpellCheck(bool v) =>
      update('spellCheck', v, () => spellCheck = v);
  Future<void> setSidebarVisible(bool v) =>
      update('sidebarVisible', v, () => sidebarVisible = v);
  Future<void> setSidebarPane(String v) =>
      update('sidebarPane', v, () => sidebarPane = v);
}
