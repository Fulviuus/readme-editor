/// Workspace state around the document: open/save dialogs, the sidebar
/// folder tree (with a debounced file watcher), and the persisted
/// recent-files list.
///
/// Owns no UI: dirty checks and "save your changes?" prompts are the app
/// layer's job — [newFile] and the open methods replace the buffer
/// unconditionally.
library;

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../document/document_controller.dart';
import 'file_io.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this.docCtrl) {
    _restoreFuture = _restoreRecentFiles();
  }

  final DocumentController docCtrl;

  static const _recentFilesKey = 'recentFiles';
  static const _maxRecentFiles = 10;
  static const _watchDebounce = Duration(milliseconds: 300);
  static const _markdownTypeGroup = XTypeGroup(
    label: 'Markdown',
    extensions: <String>['md', 'markdown', 'txt'],
  );

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  String? _folder;
  List<FileTreeNode> _tree = const [];
  List<String> _recentFiles = const [];
  WatchCancel? _cancelWatch;
  Timer? _watchTimer;
  bool _disposed = false;
  Future<void>? _restoreFuture;

  /// Guards against interleaved [openFolder] calls: only the latest call may
  /// install its tree and watcher.
  int _folderEpoch = 0;

  /// Human-readable description of the last failed save/open, or null.
  /// Set when [save]/[saveAs]/[openPath] return false/throw; the app layer
  /// surfaces it.
  String? lastError;

  /// Root folder shown in the sidebar, or null when no folder is open.
  String? get folder => _folder;

  /// Folder tree (directories first, alphabetical); empty without a folder.
  List<FileTreeNode> get tree => _tree;

  /// Path of the document in the editor (null for unsaved/new documents).
  String? get activeFilePath => docCtrl.filePath;

  /// Most recently opened/saved files, newest first, max 10. Persisted
  /// across sessions under the `recentFiles` preference key.
  List<String> get recentFiles => List.unmodifiable(_recentFiles);

  /// Replaces the buffer with an empty untitled document (no file path).
  /// Callers confirm with the user first when [DocumentController.dirty].
  Future<void> newFile() async {
    docCtrl.loadText('');
    notifyListeners();
  }

  /// Shows an open dialog and loads the chosen file. Returns false when the
  /// user cancels. On the web the picked file is read as a stream (it has no
  /// usable path, so the document stays "untitled").
  Future<bool> openFileDialog() async {
    final file = await openFile(acceptedTypeGroups: const [_markdownTypeGroup]);
    if (file == null) return false;
    if (!supportsFileSystem) {
      docCtrl.loadText(await file.readAsString());
      notifyListeners();
      return true;
    }
    await openPath(file.path);
    return true;
  }

  /// Loads the file at [path] into the editor and records it as recent.
  Future<void> openPath(String path) async {
    final String text;
    try {
      text = await readTextFile(path);
    } catch (e) {
      lastError = 'Could not open ${p.basename(path)}: $e';
      notifyListeners();
      return;
    }
    lastError = null;
    docCtrl.loadText(text, path: path);
    await _addRecentFile(path);
    notifyListeners();
  }

  /// Saves in place. Returns false when there is no file path yet (the
  /// caller should fall through to [saveAs]) or when the write failed
  /// ([lastError] is set in that case).
  Future<bool> save() async {
    final path = docCtrl.filePath;
    if (path == null) return false;
    // Snapshot before the async write: keystrokes typed while the write is
    // in flight must stay dirty.
    final revision = docCtrl.revision;
    final text = docCtrl.serialize();
    try {
      await writeTextFile(path, text);
    } catch (e) {
      lastError = 'Could not save ${p.basename(path)}: $e';
      notifyListeners();
      return false;
    }
    lastError = null;
    docCtrl.markSavedAt(revision);
    await _addRecentFile(path);
    return true;
  }

  /// Shows a save dialog and writes the document there. Returns false when
  /// cancelled, on platforms without a save dialog (web), or when the write
  /// failed ([lastError] set).
  Future<bool> saveAs() async {
    if (!supportsFileSystem) return false;
    final current = docCtrl.filePath;
    final location = await getSaveLocation(
      acceptedTypeGroups: const [_markdownTypeGroup],
      suggestedName: current == null ? 'Untitled.md' : p.basename(current),
    );
    if (location == null) return false;
    var path = location.path;
    if (p.extension(path).isEmpty) path = '$path.md';
    final revision = docCtrl.revision;
    final text = docCtrl.serialize();
    try {
      await writeTextFile(path, text);
    } catch (e) {
      lastError = 'Could not save ${p.basename(path)}: $e';
      notifyListeners();
      return false;
    }
    lastError = null;
    docCtrl.filePath = path;
    docCtrl.markSavedAt(revision);
    await _addRecentFile(path);
    notifyListeners();
    return true;
  }

  /// Shows a directory picker and opens the chosen folder in the sidebar.
  /// No-op on the web and when the user cancels.
  Future<void> openFolderDialog() async {
    if (!supportsFileSystem) return;
    final dir = await getDirectoryPath();
    if (dir == null) return;
    await openFolder(dir);
  }

  /// Opens [dir] as the workspace folder: builds the tree and watches it,
  /// rebuilding (debounced) whenever something under it changes.
  Future<void> openFolder(String dir) async {
    final epoch = ++_folderEpoch;
    await _stopWatching();
    if (epoch != _folderEpoch || _disposed) return;
    _folder = dir;
    final tree = await listMarkdownTree(dir);
    if (epoch != _folderEpoch || _disposed) return;
    _tree = tree;
    if (supportsFileSystem) {
      _cancelWatch = watchFolder(dir, _onFolderEvent);
    }
    notifyListeners();
  }

  void _onFolderEvent() {
    _watchTimer?.cancel();
    _watchTimer = Timer(_watchDebounce, () => unawaited(_rebuildTree()));
  }

  Future<void> _rebuildTree() async {
    final dir = _folder;
    if (dir == null || _disposed) return;
    final tree = await listMarkdownTree(dir);
    // The folder may have changed (or the controller been disposed) while
    // the listing was in flight.
    if (_disposed || _folder != dir) return;
    _tree = tree;
    notifyListeners();
  }

  Future<void> _stopWatching() async {
    _watchTimer?.cancel();
    _watchTimer = null;
    final cancel = _cancelWatch;
    _cancelWatch = null;
    if (cancel != null) await cancel();
  }

  Future<void> _restoreRecentFiles() async {
    List<String>? stored;
    try {
      stored = await _prefs.getStringList(_recentFilesKey);
    } catch (_) {
      return; // Unreadable prefs: start with an empty list.
    }
    if (stored == null || stored.isEmpty || _disposed) return;
    // Files opened before the prefs read completed stay at the front.
    final merged = [
      ..._recentFiles,
      ...stored.where((path) => !_recentFiles.contains(path)),
    ];
    _recentFiles = merged.take(_maxRecentFiles).toList();
    notifyListeners();
  }

  Future<void> _addRecentFile(String path) async {
    // Never write before the persisted history has been merged in, or an
    // early open would clobber it with a one-entry list.
    try {
      await _restoreFuture;
    } catch (_) {}
    _recentFiles = [
      path,
      ..._recentFiles.where((existing) => existing != path),
    ].take(_maxRecentFiles).toList();
    notifyListeners();
    try {
      await _prefs.setStringList(_recentFilesKey, _recentFiles);
    } catch (_) {
      // Persistence is best-effort; the in-memory list is already updated.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopWatching());
    super.dispose();
  }
}
