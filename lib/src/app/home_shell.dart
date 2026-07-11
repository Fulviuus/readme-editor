/// The main window layout: menu bar (platform or Material), collapsible
/// sidebar (Files | Outline), editor surface (live or source mode) with the
/// find-bar overlay, and the status bar. Also owns the confirm-if-dirty
/// flows, window-title sync and window-close interception.
library;

import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart'
    show XFile, XTypeGroup, getSaveLocation, openFile, openFiles;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getTemporaryDirectory;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../document/document_controller.dart';
import '../editor/editor_controller.dart';
import '../editor/editor_view.dart';
import '../editor/find_bar.dart';
import '../editor/rendered_block.dart';
import '../editor/source_view.dart';
import '../theme/readme_theme.dart';
import '../theme/theme_manager.dart';
import '../workspace/file_history.dart';
import '../workspace/file_io.dart' show copyIntoFolder, writeBinaryFile;
import '../workspace/html_export.dart';
import '../workspace/pandoc.dart';
import '../workspace/pdf_export.dart';
import '../workspace/update_check.dart';
import '../workspace/workspace_controller.dart';
import 'app_menu.dart';
import 'doc_tabs.dart';
import 'platform/clipboard_image.dart';
import 'settings_controller.dart';
import 'open_quickly.dart';
import 'platform/window_support.dart';
import 'preferences_dialog.dart';
import 'sidebar/articles_pane.dart';
import 'sidebar/file_tree.dart';
import 'sidebar/outline_pane.dart';
import 'sidebar/search_pane.dart';
import 'sidebar/sidebar_pane.dart';
import 'status_bar.dart';

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
  late final DocTabs _tabs;

  bool _sidebarVisible = true;
  bool _alwaysOnTop = false;
  SidebarPane _sidebarPane = SidebarPane.fileTree;
  String? _windowTitle;

  @override
  void initState() {
    super.initState();
    _doc = context.read<DocumentController>();
    _editor = context.read<EditorController>();
    _workspace = context.read<WorkspaceController>();
    _themeManager = context.read<ThemeManager>();
    _tabs = DocTabs(_doc);
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
    _tabs.dispose();
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
    if (await _confirmCloseAllTabs()) {
      await destroyWindow();
    }
  }

  // ---- Document tabs ----

  /// Parks the live editor before any tab state swap.
  void _prepareForTabSwitch() {
    _editor.commitSourceMode?.call();
    _editor.sourceModeEnabled.value = false;
    _editor.blur();
  }

  void _newTab() {
    _prepareForTabSwitch();
    _tabs.newTab();
  }

  void _selectTab(int i) {
    if (i == _tabs.activeIndex) return;
    _prepareForTabSwitch();
    _tabs.select(i);
  }

  /// Close tab [i] (confirm-if-dirty); with one tab, closes the window.
  Future<void> _closeTab(int i) async {
    if (_tabs.length <= 1) {
      await _handleWindowClose();
      return;
    }
    _selectTab(i); // the confirm flow always runs on the live document
    if (!await _confirmLoseChanges()) return;
    _prepareForTabSwitch();
    _tabs.closeTab(_tabs.activeIndex);
  }

  /// Runs the save/discard/cancel flow for every dirty tab (window close
  /// and quit). Each dirty tab is brought forward so the user sees what
  /// the dialog is about.
  Future<bool> _confirmCloseAllTabs() async {
    for (var i = 0; i < _tabs.length; i++) {
      if (!_tabs.dirtyOf(i)) continue;
      _selectTab(i);
      if (!await _confirmLoseChanges()) return false;
    }
    return true;
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

  /// File > Revert To…: pick one of the recorded save snapshots and restore
  /// it as a single undoable edit.
  Future<void> _revertTo() async {
    final path = _doc.filePath;
    if (path == null) return;
    final entries = await listSnapshots(path);
    if (!mounted) return;
    if (entries.isEmpty) {
      _showErrorDialog('No saved versions',
          'No save history has been recorded for this document yet.');
      return;
    }
    String stamp(DateTime d) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}-${two(d.month)}-${two(d.day)} '
          '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }

    final picked = await showDialog<HistoryEntry>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Revert To'),
        children: [
          for (final e in entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(e),
              child: Text('${stamp(e.savedAt)}   ·   ${e.sizeBytes} bytes'),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final text = await readSnapshot(picked.path);
      _editor.commitSourceMode?.call();
      _doc.replaceAll(text);
    } catch (e) {
      _showErrorDialog('Revert failed', '$e');
    }
  }

  /// readme > Check for Updates…
  Future<void> _checkForUpdates() async {
    final result = await checkForUpdates();
    if (!mounted) return;
    final (title, message, url) = switch (result) {
      UpToDate() => (
          'Up to date',
          'readme $appVersion is the newest version.',
          null
        ),
      UpdateAvailable(:final version, :final url) => (
          'Update available',
          'readme $version is available (you have $appVersion).',
          url
        ),
      UpdateCheckFailed(:final reason) => ('Could not check', reason, null),
    };
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (url != null)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(url)),
              child: const Text('View Release'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// File > Import…: any format pandoc reads, converted to markdown and
  /// opened as a new untitled document.
  Future<void> _importFile() async {
    _editor.commitSourceMode?.call();
    final pandoc = await findPandoc();
    if (pandoc == null) {
      _showPandocMissing();
      return;
    }
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Importable documents', extensions: <String>[
        'docx', 'odt', 'epub', 'html', 'htm', 'rtf', 'tex', 'rst', 'textile',
      ]),
    ]);
    if (file == null || !await _confirmLoseChanges()) return;
    _prepareForDocumentSwitch();
    try {
      final markdown = await pandocImport(pandoc, file.path);
      await _workspace.newFile();
      _doc.loadText(markdown);
    } on PandocException catch (e) {
      _showErrorDialog('Import failed', e.message);
    }
  }

  /// File > Export > Word/OpenDocument/Epub/LaTeX/RTF via pandoc.
  Future<void> _exportPandoc(String ext) async {
    _editor.commitSourceMode?.call();
    final pandoc = await findPandoc();
    if (pandoc == null) {
      _showPandocMissing();
      return;
    }
    final location = await getSaveLocation(
      acceptedTypeGroups: [
        XTypeGroup(label: ext.toUpperCase(), extensions: <String>[ext]),
      ],
      suggestedName: '${p.basenameWithoutExtension(_fileName)}.$ext',
    );
    if (location == null) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
    try {
      await pandocExport(pandoc, _doc.serialize(), path,
          title: p.basenameWithoutExtension(_fileName));
    } on PandocException catch (e) {
      _showErrorDialog('Export failed', e.message);
    }
  }

  void _showPandocMissing() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pandoc required'),
        content: const Text(
            'Importing and exporting these formats uses Pandoc, which was '
            'not found on this system. Install it and try again.'),
        actions: [
          TextButton(
            onPressed: () =>
                launchUrl(Uri.parse('https://pandoc.org/installing.html')),
            child: const Text('Get Pandoc'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message.isEmpty ? 'Unknown error.' : message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

  Future<void> _exportPdf() async {
    _editor.commitSourceMode?.call();
    await exportPdfDialog(
      _doc.doc,
      _editor.theme,
      title: p.basenameWithoutExtension(_fileName),
      suggestedName: '${p.basenameWithoutExtension(_fileName)}.pdf',
    );
  }

  /// File > Export > Image…: renders every block offscreen at the theme's
  /// column width and captures one tall PNG — exactly what the app shows.
  Future<void> _exportImage() async {
    _editor.commitSourceMode?.call();
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG image', extensions: <String>['png']),
      ],
      suggestedName: '${p.basenameWithoutExtension(_fileName)}.png',
    );
    if (location == null || !mounted) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.png')) path = '$path.png';

    final theme = _editor.theme;
    final boundaryKey = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -100000,
        top: 0,
        child: Material(
          child: RepaintBoundary(
            key: boundaryKey,
            child: Container(
              width: theme.contentMaxWidth + 96,
              color: theme.background,
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final block in _doc.doc.blocks)
                    RenderedBlock(block: block, editor: _editor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    try {
      // Two frames: one to lay out, one for images to (maybe) resolve.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await WidgetsBinding.instance.endOfFrame;
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      await XFile.fromData(bytes.buffer.asUint8List(),
              mimeType: 'image/png')
          .saveTo(path);
    } finally {
      entry.remove();
    }
  }

  Future<void> _print() async {
    _editor.commitSourceMode?.call();
    await printDocument(
      _doc.doc,
      _editor.theme,
      title: p.basenameWithoutExtension(_fileName),
    );
  }

  Future<void> _openQuickly() async {
    final path = await showOpenQuickly(
      context,
      workspace: _workspace,
      themeManager: _themeManager,
    );
    if (path != null) await _openPath(path);
  }

  Future<void> _revealFile() async {
    await _workspace.revealActiveFile();
    _surfaceWorkspaceError();
  }

  Future<void> _duplicateFile() async {
    if (!await _workspace.duplicateActiveFile()) _surfaceWorkspaceError();
  }

  Future<void> _renameFile() async {
    if (_doc.filePath == null) return;
    final ctrl = TextEditingController(text: p.basename(_doc.filePath!));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.trim().isNotEmpty) {
      if (!await _workspace.renameActiveFile(name)) _surfaceWorkspaceError();
    }
  }

  Future<void> _deleteFile() async {
    if (_doc.filePath == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move "$_fileName" to Trash?'),
        content: const Text('This moves the file to the system Trash.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (!await _workspace.trashActiveFile()) _surfaceWorkspaceError();
    }
  }

  /// File > Share…: native share sheet — the saved file when clean, the
  /// current markdown text otherwise.
  Future<void> _share() async {
    _editor.commitSourceMode?.call();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(64, 32, 64, 32)
        : box.localToGlobal(Offset.zero) & const Size(64, 32);
    if (_doc.filePath != null && !_doc.dirty) {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(_doc.filePath!)],
        sharePositionOrigin: origin,
      ));
    } else {
      await SharePlus.instance.share(ShareParams(
        text: _doc.serialize(),
        subject: _fileName,
        sharePositionOrigin: origin,
      ));
    }
  }

  /// Format > Image > Insert Image…: URL + alt-text dialog.
  Future<void> _insertImageDialog() async {
    final urlCtrl = TextEditingController();
    final altCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insert Image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Image URL or path',
                  hintText: 'https://… or images/pic.png'),
            ),
            TextField(
              controller: altCtrl,
              decoration:
                  const InputDecoration(labelText: 'Alt text (optional)'),
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
    );
    if (confirmed == true && urlCtrl.text.trim().isNotEmpty) {
      _editor.insertImage(urlCtrl.text.trim(), alt: altCtrl.text.trim());
    }
    urlCtrl.dispose();
    altCtrl.dispose();
  }

  /// Resolves where an inserted/dropped image should live and how to link
  /// it: optionally copied into `<doc folder>/assets`, then made relative
  /// to the document when possible.
  Future<String> _storeImagePath(String srcPath) async {
    final docDir = _doc.filePath == null ? null : p.dirname(_doc.filePath!);
    var path = srcPath;
    if (docDir != null && context.read<SettingsController>().copyImagesToAssets) {
      try {
        path = await copyIntoFolder(srcPath, p.join(docDir, 'assets'));
      } catch (_) {
        path = srcPath; // unreadable source/folder: link the original
      }
    }
    if (docDir != null && p.isWithin(docDir, path)) {
      path = p.relative(path, from: docDir);
    }
    return path;
  }

  /// Format > Image > Insert Local Images…: file picker; paths are stored
  /// relative to the document's folder when possible.
  Future<void> _insertLocalImages() async {
    const group = XTypeGroup(label: 'Images', extensions: <String>[
      'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg',
    ]);
    final files = await openFiles(acceptedTypeGroups: const [group]);
    if (files.isEmpty) return;
    for (final file in files) {
      _editor.insertImage(await _storeImagePath(file.path),
          alt: p.basenameWithoutExtension(file.name));
    }
  }

  /// Edit > Paste (also Cmd+V through the menu bar): when the clipboard has
  /// no text but does hold an image, the image is written to disk (assets
  /// folder or temp) and inserted as markdown; otherwise the normal text
  /// paste runs.
  Future<void> _paste() async {
    const intent = PasteTextIntent(SelectionChangedCause.keyboard);
    if (_editor.focusedBlockId == null) {
      dispatchTextIntent(intent);
      return;
    }
    final text = await Clipboard.getData('text/plain');
    if ((text?.text ?? '').isNotEmpty) {
      dispatchTextIntent(intent);
      return;
    }
    final png = await readClipboardImagePng();
    if (png == null) {
      dispatchTextIntent(intent);
      return;
    }
    try {
      final docDir =
          _doc.filePath == null ? null : p.dirname(_doc.filePath!);
      final copyToAssets =
          mounted && context.read<SettingsController>().copyImagesToAssets;
      final name =
          'pasted-image-${DateTime.now().millisecondsSinceEpoch}.png';
      final String target;
      if (docDir != null) {
        target = p.join(docDir, copyToAssets ? 'assets' : '.', name);
      } else {
        target = p.join((await getTemporaryDirectory()).path, name);
      }
      await writeBinaryFile(target, png);
      final link = docDir != null && p.isWithin(docDir, target)
          ? p.relative(target, from: docDir)
          : target;
      _editor.insertImage(link, alt: '');
    } catch (_) {
      // No writable destination: nothing sensible to paste.
    }
  }

  /// Quit via the same confirm-if-dirty flow as the window close button —
  /// the platform-provided quit item would terminate without asking.
  Future<void> _quit() async {
    _editor.commitSourceMode?.call();
    if (await _confirmCloseAllTabs()) {
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

  /// Help menu: loads a bundled markdown doc into the editor as an
  /// untitled, non-dirty buffer (with confirm-if-dirty first).
  Future<void> _openBundledDoc(String asset) async {
    _editor.commitSourceMode?.call();
    if (!await _confirmLoseChanges()) return;
    _prepareForDocumentSwitch();
    try {
      final text = await rootBundle.loadString(asset);
      _doc
        ..loadText(text)
        ..markSaved();
    } catch (_) {}
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
        newTab: _newTab,
        closeTab: () => _closeTab(_tabs.activeIndex),
        nextTab: () =>
            _selectTab((_tabs.activeIndex + 1) % _tabs.length),
        previousTab: () => _selectTab(
            (_tabs.activeIndex - 1 + _tabs.length) % _tabs.length),
        revertTo: _revertTo,
        checkForUpdates: _checkForUpdates,
        paste: _paste,
        importFile: _importFile,
        exportPandoc: _exportPandoc,
        exportHtml: _exportHtml,
        exportPdf: _exportPdf,
        exportImage: _exportImage,
        print: _print,
        share: _share,
        toggleSidebar: _toggleSidebar,
        quit: _quit,
        alwaysOnTop: _alwaysOnTop,
        toggleAlwaysOnTop: _toggleAlwaysOnTop,
        insertTable: _insertTableDialog,
        insertImage: _insertImageDialog,
        insertLocalImages: _insertLocalImages,
        activeSidebarPane: _sidebarPane,
        selectSidebarPane: _selectSidebarPane,
        hasFilePath: _doc.filePath != null,
        openQuickly: _openQuickly,
        revealFile: _revealFile,
        duplicateFile: _duplicateFile,
        renameFile: _renameFile,
        deleteFile: _deleteFile,
        autosave: _workspace.autosaveEnabled,
        toggleAutosave: () =>
            _workspace.setAutosave(!_workspace.autosaveEnabled),
        openMarkdownReference: () =>
            _openBundledDoc('assets/markdown-reference.md'),
        openQuickStart: () => _openBundledDoc('assets/welcome.md'),
        preferences: () => showPreferences(context),
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
      cmd(LogicalKeyboardKey.keyO, shift: true): _openQuickly,
      cmd(LogicalKeyboardKey.keyS): _saveDocument,
      cmd(LogicalKeyboardKey.keyS, shift: true): _saveDocumentAs,
      cmd(LogicalKeyboardKey.keyF): () => _editor.findVisible.value = true,
      cmd(LogicalKeyboardKey.slash): _editor.toggleSourceMode,
      cmd(LogicalKeyboardKey.keyL, shift: true): _toggleSidebar,
      const SingleActivator(LogicalKeyboardKey.f8): _editor.toggleFocusMode,
    };
  }

  // ---- Drag & drop ----

  static const _imageExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg',
  };

  Future<void> _onDropDone(DropDoneDetails details) async {
    for (final file in details.files) {
      final lower = file.path.toLowerCase();
      if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
        await _openPath(file.path);
        return;
      }
    }
    // No markdown in the drop: insert any images at the caret.
    for (final file in details.files) {
      if (_imageExtensions.contains(p.extension(file.path).toLowerCase())) {
        _editor.insertImage(await _storeImagePath(file.path),
            alt: p.basenameWithoutExtension(file.name));
      }
    }
  }

  // ---- Layout ----

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeManager>().current;
    // Rebuild menus when the workspace (recent files, tree) or editor modes
    // (focus/typewriter checkmarks) change.
    context.watch<WorkspaceController>();
    context.watch<EditorController>();
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
                  for (final pane in SidebarPane.values)
                    Expanded(
                      child: _SidebarTabButton(
                        label: pane.label,
                        selected: _sidebarPane == pane,
                        theme: theme,
                        onTap: () => setState(() => _sidebarPane = pane),
                      ),
                    ),
                ],
              ),
              Expanded(child: _buildSidebarPane()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarPane() {
    return switch (_sidebarPane) {
      SidebarPane.fileTree => FileTree(onOpenFile: _openPath),
      SidebarPane.outline => const OutlinePane(),
      SidebarPane.articles => ArticlesPane(onOpenFile: _openPath),
      SidebarPane.search => SearchPane(onOpenMatch: _openSearchMatch),
    };
  }

  /// View-menu pane selection: switches the pane and reveals the sidebar.
  void _selectSidebarPane(SidebarPane pane) {
    setState(() {
      _sidebarPane = pane;
      _sidebarVisible = true;
    });
  }

  /// Opens [path] and focuses the first block containing [lineText].
  Future<void> _openSearchMatch(String path, String lineText) async {
    if (_doc.filePath != path) {
      await _openPath(path);
      if (_doc.filePath != path) return; // cancelled or failed
    }
    final needle = lineText.trim();
    if (needle.isEmpty) return;
    for (final block in _doc.doc.blocks) {
      final at = block.source.indexOf(needle);
      if (at >= 0) {
        _editor.focusBlock(block.id, offset: at);
        return;
      }
    }
  }

  /// Tab strip above the editor; hidden while there is only one tab.
  Widget _buildTabBar(ReadmeTheme theme) {
    return ListenableBuilder(
      listenable: _tabs,
      builder: (context, _) {
        if (_tabs.length < 2) return const SizedBox.shrink();
        return Container(
          height: 32,
          color: theme.sidebarBackground,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _DocTabButton(
                    title:
                        '${_tabs.titleOf(i)}${_tabs.dirtyOf(i) ? ' •' : ''}',
                    selected: i == _tabs.activeIndex,
                    theme: theme,
                    onTap: () => _selectTab(i),
                    onClose: () => _closeTab(i),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditorArea() {
    return DropTarget(
      onDragDone: _onDropDone,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                _buildTabBar(_editor.theme),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _editor.sourceModeEnabled,
                    builder: (context, sourceMode, _) => sourceMode
                        ? SourceView(editor: _editor)
                        : EditorView(editor: _editor),
                  ),
                ),
              ],
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

class _DocTabButton extends StatelessWidget {
  const _DocTabButton({
    required this.title,
    required this.selected,
    required this.theme,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool selected;
  final ReadmeTheme theme;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? (theme.sidebarActiveForeground ?? theme.foreground)
        : theme.sidebarForeground;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? theme.background : Colors.transparent,
          border: Border(
            right: BorderSide(
                color: theme.sidebarForeground.withValues(alpha: 0.15)),
            top: BorderSide(
              width: 2,
              color: selected ? theme.accent : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ),
            InkWell(
              onTap: onClose,
              child: Icon(Icons.close, size: 13, color: fg),
            ),
          ],
        ),
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
