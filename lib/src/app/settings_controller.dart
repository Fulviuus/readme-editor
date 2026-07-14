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

  /// Drop behaviors ('open'/'none', 'open'/'insertLink', 'import'/'none').
  String dropFolderAction = 'open';
  String dropMarkdownAction = 'open';
  String dropImportableAction = 'import';

  /// Quit with the window (false: stay alive, Dock reopen restores it).
  bool quitWhenClosed = true;

  // ---- Editor ----
  bool spellCheck = true;
  bool smartQuotes = false;
  bool smartDashes = false;

  /// Typing `(`, `[`, `{`, `"` or `'` inserts the closing pair.
  bool autoPairBrackets = false;

  /// Typing `*`, `_`, `~` or a backtick inserts the closing marker too.
  bool autoPairMarkdown = false;

  /// Spaces per list indent level ('2' | '4').
  String indentSize = '2';

  /// Indent nested list lines to the parent marker's width.
  bool prettyIndent = false;

  /// `:shortcode:` converts to its emoji on the closing colon.
  bool emojiAutocomplete = true;

  /// Show block markers (heading #, quote >) while editing; off keeps
  /// simple blocks looking rendered.
  bool displaySourceOnFocus = true;

  /// Cmd+C copies markdown source (false: rendered plain text).
  bool copyMarkdownSource = true;

  /// Copy/cut the caret's line when nothing is selected.
  bool copyWholeLine = false;

  /// Typewriter mode recenters on every caret move (false: only on drift).
  bool typewriterCenterAlways = true;

  /// Markdown syntax coloring in source mode.
  bool sourceHighlight = true;

  /// Modal (Vim-style) key bindings in the editor.
  bool vimMode = false;

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

  /// Wrap long code lines (false: horizontal scroll).
  bool autoWrapCode = true;

  /// Language pre-filled on code fences created from the menu.
  String codeDefaultLanguage = '';

  /// Heading style produced by conversions ('atx' | 'setext').
  String headingStyle = 'atx';

  /// Ordered-list delimiter ('.' | ')').
  String orderedDelimiter = '.';

  /// `~x~` / `^x^` / `==x==` syntax support.
  bool subscriptSyntax = false;
  bool superscriptSyntax = false;
  bool highlightSyntax = false;

  bool preserveSingleLineBreak = true;
  bool visibleBr = false;

  // ---- Export ----
  /// Explicit pandoc executable path; empty means auto-discover.
  String pandocPath = '';

  /// Reveal exported files in the file manager after a successful export.
  bool revealAfterExport = false;

  // ---- Appearance ----
  /// Cmd+scroll-wheel zooms the document.
  bool wheelZoom = false;

  /// Word count in the status bar (off collapses it to a click target).
  bool showWordCount = true;

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
      dropFolderAction = await _prefs.getString('dropFolderAction') ?? 'open';
      dropMarkdownAction =
          await _prefs.getString('dropMarkdownAction') ?? 'open';
      dropImportableAction =
          await _prefs.getString('dropImportableAction') ?? 'import';
      quitWhenClosed = await _prefs.getBool('quitWhenClosed') ?? true;
      indentSize = await _prefs.getString('indentSize') ?? '2';
      prettyIndent = await _prefs.getBool('prettyIndent') ?? false;
      emojiAutocomplete = await _prefs.getBool('emojiAutocomplete') ?? true;
      displaySourceOnFocus =
          await _prefs.getBool('displaySourceOnFocus') ?? true;
      copyMarkdownSource =
          await _prefs.getBool('copyMarkdownSource') ?? true;
      copyWholeLine = await _prefs.getBool('copyWholeLine') ?? false;
      typewriterCenterAlways =
          await _prefs.getBool('typewriterCenterAlways') ?? true;
      sourceHighlight = await _prefs.getBool('sourceHighlight') ?? true;
      vimMode = await _prefs.getBool('vimMode') ?? false;
      autoWrapCode = await _prefs.getBool('autoWrapCode') ?? true;
      codeDefaultLanguage =
          await _prefs.getString('codeDefaultLanguage') ?? '';
      headingStyle = await _prefs.getString('headingStyle') ?? 'atx';
      orderedDelimiter = await _prefs.getString('orderedDelimiter') ?? '.';
      subscriptSyntax = await _prefs.getBool('subscriptSyntax') ?? false;
      superscriptSyntax =
          await _prefs.getBool('superscriptSyntax') ?? false;
      highlightSyntax = await _prefs.getBool('highlightSyntax') ?? false;
      wheelZoom = await _prefs.getBool('wheelZoom') ?? false;
      showWordCount = await _prefs.getBool('showWordCount') ?? true;
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
