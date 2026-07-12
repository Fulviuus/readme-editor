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
import 'file_history.dart';
import 'file_io.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this.docCtrl) {
    _restoreFuture = _restoreRecentFiles();
    docCtrl.addListener(_onDocChanged);
  }

  final DocumentController docCtrl;

  static const _recentFilesKey = 'recentFiles';
  static const _autosaveKey = 'autosave';
  static const _folderKey = 'openFolder';
  static const _maxRecentFiles = 10;
  static const _watchDebounce = Duration(milliseconds: 300);
  static const _autosaveDebounce = Duration(seconds: 2);
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

  bool _autosave = false;
  Timer? _autosaveTimer;

  /// Whether edits are written back to the file automatically (debounced).
  bool get autosaveEnabled => _autosave;

  Future<void> setAutosave(bool enabled) async {
    if (_autosave == enabled) return;
    _autosave = enabled;
    notifyListeners();
    try {
      await _prefs.setBool(_autosaveKey, enabled);
    } catch (_) {}
    if (enabled) _scheduleAutosave();
  }

  void _onDocChanged() {
    if (_autosave) _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (!_autosave || docCtrl.filePath == null || !docCtrl.dirty) return;
    _autosaveTimer = Timer(_autosaveDebounce, () => unawaited(save()));
  }

  /// Root folder shown in the sidebar, or null when no folder is open.
  String? get folder => _folder;

  /// Folder tree (directories first, alphabetical); empty without a folder.
  List<FileTreeNode> get tree => _tree;

  /// Path of the document in the editor (null for unsaved/new documents).
  String? get activeFilePath => docCtrl.filePath;

  /// Most recently opened/saved files, newest first, max 10. Persisted
  /// across sessions under the `recentFiles` preference key.
  List<String> get recentFiles => List.unmodifiable(_recentFiles);

  String? _lastClosedFile;

  /// The file most recently replaced in the editor (File > Open Recent >
  /// Reopen Closed File), or null.
  String? get lastClosedFile => _lastClosedFile;

  void _rememberClosed(String? replacedPath, {String? incoming}) {
    if (replacedPath != null && replacedPath != incoming) {
      _lastClosedFile = replacedPath;
    }
  }

  /// Reopens the file that was last replaced in the editor.
  Future<void> reopenClosedFile() async {
    final path = _lastClosedFile;
    if (path != null) await openPath(path);
  }

  /// Empties the recent-files list (persisted).
  Future<void> clearRecentFiles() async {
    _recentFiles = const [];
    notifyListeners();
    try {
      await _restoreFuture;
      await _prefs.setStringList(_recentFilesKey, const []);
    } catch (_) {}
  }

  /// Replaces the buffer with an empty untitled document (no file path).
  /// Callers confirm with the user first when [DocumentController.dirty].
  Future<void> newFile() async {
    _rememberClosed(docCtrl.filePath);
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
      _rememberClosed(docCtrl.filePath);
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
    _rememberClosed(docCtrl.filePath, incoming: path);
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
    unawaited(recordSnapshot(path, text));
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
      suggestedName: current == null
          ? 'Untitled.$defaultExtension'
          : p.basename(current),
    );
    if (location == null) return false;
    var path = location.path;
    if (p.extension(path).isEmpty) path = '$path.$defaultExtension';
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
    unawaited(recordSnapshot(path, text));
    notifyListeners();
    return true;
  }

  /// Reveals the active file in the system file manager (no-op if unsaved).
  Future<void> revealActiveFile() async {
    final path = docCtrl.filePath;
    if (path == null || !supportsFileSystem) return;
    await revealInFileManager(path);
  }

  /// Duplicates the active file on disk and opens the copy. Returns false if
  /// there is no saved file.
  Future<bool> duplicateActiveFile() async {
    final path = docCtrl.filePath;
    if (path == null || !supportsFileSystem) return false;
    try {
      final copy = await duplicateFile(path);
      await openPath(copy);
      return true;
    } catch (e) {
      lastError = 'Could not duplicate ${p.basename(path)}: $e';
      notifyListeners();
      return false;
    }
  }

  /// Renames the active file to [newName] (basename, extension optional) in
  /// its current folder, keeping it open.
  Future<bool> renameActiveFile(String newName) async {
    final path = docCtrl.filePath;
    if (path == null || !supportsFileSystem || newName.trim().isEmpty) {
      return false;
    }
    var name = newName.trim();
    if (p.extension(name).isEmpty) name = '$name${p.extension(path)}';
    final newPath = p.join(p.dirname(path), name);
    try {
      await renameFile(path, newPath);
      docCtrl.filePath = newPath;
      await _addRecentFile(newPath);
      await _rebuildTree();
      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Could not rename ${p.basename(path)}: $e';
      notifyListeners();
      return false;
    }
  }

  /// Moves the active file to the trash and clears the editor to a new
  /// untitled document. Returns false if there is no saved file.
  Future<bool> trashActiveFile() async {
    final path = docCtrl.filePath;
    if (path == null || !supportsFileSystem) return false;
    try {
      await trashFile(path);
      _recentFiles = _recentFiles.where((r) => r != path).toList();
      await _persistRecent();
      docCtrl.loadText('');
      await _rebuildTree();
      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Could not delete ${p.basename(path)}: $e';
      notifyListeners();
      return false;
    }
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
  /// rebuilding (debounced) whenever something under it changes. The
  /// folder persists and is reopened on the next launch.
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
    try {
      await _prefs.setString(_folderKey, dir);
    } catch (_) {}
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

  /// Preferences > Files: whether Open Recent records anything.
  bool recordRecentFiles = true;

  /// Preferences > Files: extension for new documents and Save As.
  String defaultExtension = 'md';

  Future<void> _addRecentFile(String path) async {
    if (!recordRecentFiles) return;
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
    await _persistRecent();
  }

  Future<void> _persistRecent() async {
    try {
      await _prefs.setStringList(_recentFilesKey, _recentFiles);
    } catch (_) {
      // Persistence is best-effort; the in-memory list is already updated.
    }
  }

  /// Restores the persisted autosave preference and reopens the last
  /// workspace folder. Call once at startup.
  Future<void> restoreSettings() async {
    try {
      _autosave = await _prefs.getBool(_autosaveKey) ?? false;
      notifyListeners();
    } catch (_) {}
    if (!supportsFileSystem) return;
    try {
      final dir = await _prefs.getString(_folderKey);
      // Only restore when nothing was opened in the meantime; a vanished
      // folder just yields an empty tree, which openFolder handles.
      if (dir != null && _folder == null && !_disposed) {
        await openFolder(dir);
      }
    } catch (_) {}
    // Preferences > Files > On Launch: reopen the last file. Skipped when
    // a document is already loaded (dirty, or opened via the OS).
    try {
      final action = await _prefs.getString('launchAction');
      if (action == 'reopenLast' &&
          !_disposed &&
          docCtrl.filePath == null &&
          !docCtrl.dirty &&
          _recentFiles.isNotEmpty) {
        await openPath(_recentFiles.first);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _autosaveTimer?.cancel();
    docCtrl.removeListener(_onDocChanged);
    unawaited(_stopWatching());
    super.dispose();
  }
}
