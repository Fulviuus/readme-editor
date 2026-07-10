/// `dart:io` implementation of the file-system facade (see file_io.dart).
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'file_io.dart';

/// A real, path-based file system is available on desktop.
bool get supportsFileSystem => true;

Future<String> readTextFile(String path) => File(path).readAsString();

Future<void> writeTextFile(String path, String text) async {
  await File(path).writeAsString(text, flush: true);
}

const _markdownExtensions = {'.md', '.markdown', '.txt'};

/// Recursively lists [dir]: non-hidden directories plus markdown/text files.
/// Unreadable directories are treated as empty rather than failing the whole
/// tree.
Future<List<FileTreeNode>> listMarkdownTree(String dir) =>
    _listDirectory(Directory(dir));

Future<List<FileTreeNode>> _listDirectory(Directory dir) async {
  final List<FileSystemEntity> entries;
  try {
    entries = await dir.list(followLinks: false).toList();
  } on FileSystemException {
    return const [];
  }
  final dirs = <FileTreeNode>[];
  final files = <FileTreeNode>[];
  for (final entry in entries) {
    final name = p.basename(entry.path);
    if (name.startsWith('.')) continue;
    if (entry is Directory) {
      dirs.add(FileTreeNode(
        name: name,
        path: entry.path,
        isDirectory: true,
        children: await _listDirectory(entry),
      ));
    } else if (entry is File &&
        _markdownExtensions.contains(p.extension(name).toLowerCase())) {
      files.add(FileTreeNode(name: name, path: entry.path, isDirectory: false));
    }
  }
  int byName(FileTreeNode a, FileTreeNode b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  dirs.sort(byName);
  files.sort(byName);
  return [...dirs, ...files];
}

/// Watches [dir] recursively; [onChange] fires on every file-system event
/// under it (the caller debounces). Watcher errors (e.g. the folder being
/// deleted mid-watch) silently end the subscription.
WatchCancel watchFolder(String dir, void Function() onChange) {
  final subscription = DirectoryWatcher(dir).events.listen(
        (_) => onChange(),
        onError: (Object _) {},
        cancelOnError: true,
      );
  return subscription.cancel;
}
