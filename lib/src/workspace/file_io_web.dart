/// Web stub of the file-system facade (see file_io.dart). Browsers expose no
/// path-based file system; `WorkspaceController` falls back to `XFile`
/// streams from file_selector where possible and disables the rest.
library;

import 'file_io.dart';

/// No path-based file system in the browser.
bool get supportsFileSystem => false;

Future<String> readTextFile(String path) async {
  throw UnsupportedError('readTextFile is not available on the web');
}

Future<void> writeTextFile(String path, String text) async {
  throw UnsupportedError('writeTextFile is not available on the web');
}

/// Folder trees are unavailable in the browser.
Future<List<FileTreeNode>> listMarkdownTree(String dir) async =>
    const <FileTreeNode>[];

/// No-op watch: never fires, cancel does nothing.
WatchCancel watchFolder(String dir, void Function() onChange) => () async {};
