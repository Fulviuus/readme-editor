/// Root widget: owns the controllers, wires theme-manager changes into the
/// editor, resolves image URLs for the inline renderer, and provides
/// everything below via provider.
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../document/document_controller.dart';
import '../editor/editor_controller.dart';
import '../editor/inline_tokenizer.dart'
    show
        highlightSyntaxEnabled,
        inlineMathEnabled,
        subscriptSyntaxEnabled,
        superscriptSyntaxEnabled;
import '../theme/material_theme.dart';
import '../theme/theme_manager.dart';
import '../workspace/workspace_controller.dart';
import 'home_shell.dart';
import 'platform/local_image.dart';
import 'settings_controller.dart';

class ReadmeApp extends StatefulWidget {
  const ReadmeApp({super.key, required this.themeManager});

  final ThemeManager themeManager;

  @override
  State<ReadmeApp> createState() => _ReadmeAppState();
}

class _ReadmeAppState extends State<ReadmeApp> with WidgetsBindingObserver {
  late final DocumentController _docCtrl;
  late final EditorController _editor;
  late final WorkspaceController _workspace;
  late final SettingsController _settings;

  @override
  void initState() {
    super.initState();
    _docCtrl = DocumentController()..loadText('');
    _editor = EditorController(_docCtrl, widget.themeManager.current)
      ..imageBuilder = _buildImage;
    _workspace = WorkspaceController(_docCtrl)..restoreSettings();
    _settings = SettingsController();
    _settings.addListener(_onSettingsChanged);
    _settings.load();
    widget.themeManager.addListener(_onThemeChanged);
    WidgetsBinding.instance.addObserver(this);
    widget.themeManager.platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  void didChangePlatformBrightness() {
    widget.themeManager.onPlatformBrightnessChanged(
        WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  void _onSettingsChanged() {
    inlineMathEnabled = _settings.inlineMath;
    subscriptSyntaxEnabled = _settings.subscriptSyntax;
    superscriptSyntaxEnabled = _settings.superscriptSyntax;
    highlightSyntaxEnabled = _settings.highlightSyntax;
    _editor
      ..smartQuotes = _settings.smartQuotes
      ..smartDashes = _settings.smartDashes
      ..spellCheckEnabled = _settings.spellCheck
      ..autoPairBrackets = _settings.autoPairBrackets
      ..autoPairMarkdown = _settings.autoPairMarkdown
      ..bulletMarker = _settings.bulletMarker
      ..orderedDelimiter = _settings.orderedDelimiter
      ..headingStyle = _settings.headingStyle
      ..indentUnit = ' ' * (int.tryParse(_settings.indentSize) ?? 2)
      ..prettyIndent = _settings.prettyIndent
      ..emojiAutocomplete = _settings.emojiAutocomplete
      ..codeDefaultLanguage = _settings.codeDefaultLanguage
      ..typewriterCenterAlways = _settings.typewriterCenterAlways
      ..sourceHighlightEnabled = _settings.sourceHighlight
      ..diagramsEnabled = _settings.diagrams
      ..codeLineNumbers = _settings.codeLineNumbers
      ..autoWrapCode = _settings.autoWrapCode
      ..wheelZoom = _settings.wheelZoom
      ..onWheelZoom = ((zoomIn) => zoomIn
          ? widget.themeManager.zoomIn()
          : widget.themeManager.zoomOut())
      ..displaySourceOnFocus = _settings.displaySourceOnFocus
      ..applyRenderSettings(
        preserveSingleLineBreak: _settings.preserveSingleLineBreak,
        visibleBr: _settings.visibleBr,
      );
    _workspace
      ..recordRecentFiles = _settings.recordRecentFiles
      ..defaultExtension = _settings.defaultExtension;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettingsChanged);
    _settings.dispose();
    widget.themeManager.removeListener(_onThemeChanged);
    _workspace.dispose();
    _editor.dispose();
    _docCtrl.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    _editor.theme = widget.themeManager.current;
    // Material chrome (dialogs, buttons, menus) follows the editor theme.
    if (mounted) setState(() {});
  }

  // ---- Image resolution for the inline renderer ----

  Widget _buildImage(String url, String alt) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        errorBuilder: (context, error, stackTrace) => _brokenImage(alt),
      );
    }
    final path = _resolveLocalPath(url);
    if (path == null) return _brokenImage(alt);
    return buildLocalImage(path, alt, () => _brokenImage(alt));
  }

  /// Resolves a relative or file:// URL against the open document's folder.
  String? _resolveLocalPath(String url) {
    var path = url;
    if (path.startsWith('file://')) {
      try {
        path = Uri.parse(path).toFilePath();
      } catch (_) {
        return null;
      }
    }
    if (p.isAbsolute(path)) return path;
    final docPath = _docCtrl.filePath;
    if (docPath == null) return null;
    return p.normalize(p.join(p.dirname(docPath), path));
  }

  /// Placeholder for unloadable images: bordered box with icon + alt text.
  Widget _brokenImage(String alt) {
    final theme = _editor.theme;
    final color = theme.hintColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              alt.isEmpty ? 'image' : alt,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: theme.fontSize * 0.85),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeManager>.value(value: widget.themeManager),
        ChangeNotifierProvider<DocumentController>.value(value: _docCtrl),
        ChangeNotifierProvider<EditorController>.value(value: _editor),
        ChangeNotifierProvider<WorkspaceController>.value(value: _workspace),
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
      ],
      child: MaterialApp(
        title: 'readme',
        debugShowCheckedModeBanner: false,
        theme: buildMaterialTheme(widget.themeManager.current),
        home: const HomeShell(),
      ),
    );
  }
}
