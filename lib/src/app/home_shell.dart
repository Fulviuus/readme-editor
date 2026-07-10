/// The main window layout: menu bar (platform or Material), collapsible
/// sidebar (Files | Outline), editor surface (live or source mode) with the
/// find-bar overlay, and the status bar. Also owns the confirm-if-dirty
/// flows, window-title sync and window-close interception.
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../document/document_controller.dart';
import '../editor/editor_controller.dart';
import '../editor/editor_view.dart';
import '../editor/find_bar.dart';
import '../editor/source_view.dart';
import '../theme/readme_theme.dart';
import '../theme/theme_manager.dart';
import '../workspace/html_export.dart';
import '../workspace/workspace_controller.dart';
import 'app_menu.dart';
import 'platform/window_support.dart';
import 'sidebar/file_tree.dart';
import 'sidebar/outline_pane.dart';
import 'status_bar.dart';

enum _SidebarTab { files, outline }

enum _DirtyChoice { save, discard, cancel }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final DocumentController _doc;
  late final EditorController _editor;
  late final WorkspaceController _workspace;
  late final ThemeManager _themeManager;

  bool _sidebarVisible = true;
  bool _alwaysOnTop = false;
  _SidebarTab _sidebarTab = _SidebarTab.files;
  String? _windowTitle;

  @override
  void initState() {
    super.initState();
    _doc = context.read<DocumentController>();
    _editor = context.read<EditorController>();
    _workspace = context.read<WorkspaceController>();
    _themeManager = context.read<ThemeManager>();
    _doc.addListener(_syncWindowTitle);
    _syncWindowTitle();
    _editor.linkOpener = (url) => _openLink(url);
    if (!kIsWeb) {
      setPreventCloseEnabled(true);
      setWindowCloseHandler(_handleWindowClose);
    }
  }

  @override
  void dispose() {
    _editor.linkOpener = null;
    _doc.removeListener(_syncWindowTitle);
    if (!kIsWeb) {
      setWindowCloseHandler(null);
    }
    super.dispose();
  }

  // ---- Window integration ----

  String get _fileName =>
      _doc.filePath == null ? 'Untitled' : p.basename(_doc.filePath!);

  String? _menuLineEnding;
  bool? _menuFinalNewline;

  void _syncWindowTitle() {
    // Menu checkmarks (Line Endings) read document state at build time;
    // rebuild the shell when those specific facts change.
    if (_menuLineEnding != _doc.doc.lineEnding ||
        _menuFinalNewline != _doc.doc.hadFinalNewline) {
      _menuLineEnding = _doc.doc.lineEnding;
      _menuFinalNewline = _doc.doc.hadFinalNewline;
      if (mounted) setState(() {});
    }
    if (kIsWeb) return;
    final title = '$_fileName${_doc.dirty ? ' •' : ''} — readme';
    if (title == _windowTitle) return;
    _windowTitle = title;
    setWindowTitle(title);
  }

  Future<void> _handleWindowClose() async {
    _editor.commitSourceMode?.call();
    if (await _confirmLoseChanges()) {
      await destroyWindow();
    }
  }

  // ---- Confirm-if-dirty flow ----

  /// True when it is safe to replace or close the current document (clean,
  /// saved, or explicitly discarded); false when the user cancelled.
  Future<bool> _confirmLoseChanges() async {
    if (!_doc.dirty) return true;
    final choice = await showDialog<_DirtyChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save changes to $_fileName?'),
        content:
            const Text("Your changes will be lost if you don't save them."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DirtyChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DirtyChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_DirtyChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    switch (choice) {
      case _DirtyChoice.save:
        return _saveDocument();
      case _DirtyChoice.discard:
        return true;
      case _DirtyChoice.cancel:
      case null:
        return false;
    }
  }

  // ---- Menu actions ----

  /// Save; a document without a path falls through to Save As. Returns
  /// whether the document actually reached disk. Uncommitted source-mode
  /// edits are flushed into the document first so they cannot be lost.
  Future<bool> _saveDocument() async {
    _editor.commitSourceMode?.call();
    if (await _workspace.save()) return true;
    if (await _workspace.saveAs()) return true;
    _surfaceWorkspaceError();
    return false;
  }

  Future<bool> _saveDocumentAs() async {
    _editor.commitSourceMode?.call();
    if (await _workspace.saveAs()) return true;
    _surfaceWorkspaceError();
    return false;
  }

  /// Failed writes/opens must not vanish silently (they also abort
  /// menu/close flows) — tell the user what happened.
  void _surfaceWorkspaceError() {
    final message = _workspace.lastError;
    if (message == null || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Leaving source mode (its buffer belongs to the outgoing document) and
  /// flushing pending source edits keeps dirty-checks truthful before any
  /// document replacement.
  void _prepareForDocumentSwitch() {
    _editor.commitSourceMode?.call();
    _editor.sourceModeEnabled.value = false;
  }

  /// Opens a link from the document: web/mailto URLs in the browser,
  /// relative markdown paths in the editor (confirm-if-dirty first), other
  /// local paths with the system default app.
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme ?? '';
    if (scheme == 'http' || scheme == 'https' || scheme == 'mailto') {
      await launchUrl(uri!);
      return;
    }
    // Relative or file path: resolve against the open document's folder.
    var path = url;
    if (scheme == 'file') path = uri!.toFilePath();
    if (!p.isAbsolute(path) && _doc.filePath != null) {
      path = p.normalize(p.join(p.dirname(_doc.filePath!), path));
    }
    final lower = path.toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown') ||
        lower.endsWith('.txt')) {
      await _openPath(path);
      return;
    }
    await launchUrl(Uri.file(path));
  }

  Future<void> _newFile() async {
    _editor.commitSourceMode?.call();
    if (await _confirmLoseChanges()) {
      _prepareForDocumentSwitch();
      await _workspace.newFile();
    }
  }

  Future<void> _openFile() async {
    _editor.commitSourceMode?.call();
    if (await _confirmLoseChanges()) {
      _prepareForDocumentSwitch();
      await _workspace.openFileDialog();
      _surfaceWorkspaceError();
    }
  }

  Future<void> _openPath(String path) async {
    _editor.commitSourceMode?.call();
    if (await _confirmLoseChanges()) {
      _prepareForDocumentSwitch();
      await _workspace.openPath(path);
      _surfaceWorkspaceError();
    }
  }

  Future<void> _exportHtml() async {
    _editor.commitSourceMode?.call();
    await exportHtmlDialog(
      _doc.serialize(),
      _editor.theme,
      title: p.basenameWithoutExtension(_fileName),
      suggestedName: '${p.basenameWithoutExtension(_fileName)}.html',
    );
  }

  /// Quit via the same confirm-if-dirty flow as the window close button —
  /// the platform-provided quit item would terminate without asking.
  Future<void> _quit() async {
    _editor.commitSourceMode?.call();
    if (await _confirmLoseChanges()) {
      await destroyWindow();
    }
  }

  void _toggleSidebar() => setState(() => _sidebarVisible = !_sidebarVisible);

  void _toggleAlwaysOnTop() {
    setState(() => _alwaysOnTop = !_alwaysOnTop);
    if (!kIsWeb) setWindowAlwaysOnTop(_alwaysOnTop);
  }

  /// Paragraph > Insert Table…: rows × columns picker.
  Future<void> _insertTableDialog() async {
    var rows = 2;
    var cols = 2;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Insert Table'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value, set) in [
                ('Rows', rows, (int v) => rows = v),
                ('Columns', cols, (int v) => cols = v),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => setDialogState(
                                () => set((value - 1).clamp(1, 99))),
                          ),
                          Text('$value',
                              style: const TextStyle(fontSize: 18)),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => setDialogState(
                                () => set((value + 1).clamp(1, 99))),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Insert'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) _editor.insertTable(rows, cols);
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'readme',
      applicationVersion: '1.0.0',
      children: [
        const Text('A live markdown editor — the document is the editor.'),
      ],
    );
  }

  AppMenuCallbacks get _menuCallbacks => AppMenuCallbacks(
        about: _showAbout,
        newFile: _newFile,
        openFile: _openFile,
        openFolder: _workspace.openFolderDialog,
        openRecent: _openPath,
        save: _saveDocument,
        saveAs: _saveDocumentAs,
        exportHtml: _exportHtml,
        toggleSidebar: _toggleSidebar,
        quit: _quit,
        alwaysOnTop: _alwaysOnTop,
        toggleAlwaysOnTop: _toggleAlwaysOnTop,
        insertTable: _insertTableDialog,
      );

  /// Shell-level shortcuts for platforms without a native menu bar. The
  /// editor already binds formatting/undo (Ctrl+B/I/E/K/Z/0-6) itself.
  Map<ShortcutActivator, VoidCallback> get _shellBindings {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return const {};
    }
    final meta = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: meta, control: !meta, shift: shift);
    return {
      cmd(LogicalKeyboardKey.keyN): _newFile,
      cmd(LogicalKeyboardKey.keyO): _openFile,
      cmd(LogicalKeyboardKey.keyS): _saveDocument,
      cmd(LogicalKeyboardKey.keyS, shift: true): _saveDocumentAs,
      cmd(LogicalKeyboardKey.keyF): () => _editor.findVisible.value = true,
      cmd(LogicalKeyboardKey.slash): _editor.toggleSourceMode,
      cmd(LogicalKeyboardKey.keyL, shift: true): _toggleSidebar,
      const SingleActivator(LogicalKeyboardKey.f8): _editor.toggleFocusMode,
    };
  }

  // ---- Drag & drop ----

  Future<void> _onDropDone(DropDoneDetails details) async {
    for (final file in details.files) {
      final lower = file.path.toLowerCase();
      if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
        await _openPath(file.path);
        return;
      }
    }
  }

  // ---- Layout ----

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeManager>().current;
    // Rebuild menus when the workspace (recent files, tree) changes.
    context.watch<WorkspaceController>();
    final isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

    Widget shell = Column(
      children: [
        if (!isMacOS)
          AppMenuBar(
            actions: _menuCallbacks,
            workspace: _workspace,
            editor: _editor,
            themeManager: _themeManager,
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidebar(theme),
              if (_sidebarVisible)
                VerticalDivider(width: 1, thickness: 1, color: theme.hr),
              Expanded(child: _buildEditorArea()),
            ],
          ),
        ),
        const StatusBar(),
      ],
    );

    shell = Scaffold(
      backgroundColor: theme.background,
      body: CallbackShortcuts(bindings: _shellBindings, child: shell),
    );

    if (isMacOS) {
      return PlatformMenuBar(
        menus: buildPlatformMenus(
          actions: _menuCallbacks,
          workspace: _workspace,
          editor: _editor,
          themeManager: _themeManager,
        ),
        child: shell,
      );
    }
    return shell;
  }

  Widget _buildSidebar(ReadmeTheme theme) {
    return ClipRect(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOutCubic,
        width: _sidebarVisible ? 240 : 0,
        color: theme.sidebarBackground,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 240,
          maxWidth: 240,
          child: Column(
            children: [
              Row(
                children: [
                  for (final tab in _SidebarTab.values)
                    Expanded(
                      child: _SidebarTabButton(
                        label: tab == _SidebarTab.files ? 'Files' : 'Outline',
                        selected: _sidebarTab == tab,
                        theme: theme,
                        onTap: () => setState(() => _sidebarTab = tab),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: _sidebarTab == _SidebarTab.files
                    ? FileTree(onOpenFile: _openPath)
                    : const OutlinePane(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorArea() {
    return DropTarget(
      onDragDone: _onDropDone,
      child: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable: _editor.sourceModeEnabled,
              builder: (context, sourceMode, _) => sourceMode
                  ? SourceView(editor: _editor)
                  : EditorView(editor: _editor),
            ),
          ),
          Positioned(
            top: 0,
            right: 24,
            child: ValueListenableBuilder<bool>(
              valueListenable: _editor.findVisible,
              builder: (context, visible, _) => visible
                  ? FindBar(editor: _editor)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTabButton extends StatelessWidget {
  const _SidebarTabButton({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ReadmeTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? (theme.sidebarActiveForeground ?? theme.foreground)
        : theme.sidebarForeground;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? theme.accent : Colors.transparent,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
      ),
    );
  }
}
