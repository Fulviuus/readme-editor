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

/// Reveals [path] in the system file manager.
Future<void> revealInFileManager(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', path]);
  } else {
    await Process.run('xdg-open', [p.dirname(path)]);
  }
}

/// Copies [path] to a sibling `<name> copy.<ext>`, returning the new path.
Future<String> duplicateFile(String path) async {
  final dir = p.dirname(path);
  final stem = p.basenameWithoutExtension(path);
  final ext = p.extension(path);
  var candidate = p.join(dir, '$stem copy$ext');
  var n = 2;
  while (await File(candidate).exists()) {
    candidate = p.join(dir, '$stem copy $n$ext');
    n++;
  }
  await File(path).copy(candidate);
  return candidate;
}

/// Copies [srcPath] into [folder] (created if missing), deduplicating the
/// name with ` 2`, ` 3`, … suffixes. Returns the destination path; if the
/// source already lives in [folder], it is returned untouched.
Future<String> copyIntoFolder(String srcPath, String folder) async {
  if (p.equals(p.dirname(srcPath), folder)) return srcPath;
  await Directory(folder).create(recursive: true);
  final stem = p.basenameWithoutExtension(srcPath);
  final ext = p.extension(srcPath);
  var candidate = p.join(folder, '$stem$ext');
  var n = 2;
  while (await File(candidate).exists()) {
    candidate = p.join(folder, '$stem $n$ext');
    n++;
  }
  await File(srcPath).copy(candidate);
  return candidate;
}

/// Writes [bytes] to [path], creating parent directories as needed.
Future<void> writeBinaryFile(String path, List<int> bytes) async {
  await Directory(p.dirname(path)).create(recursive: true);
  await File(path).writeAsBytes(bytes, flush: true);
}

/// Renames/moves [path] to [newPath]; returns the destination.
Future<String> renameFile(String path, String newPath) async {
  await File(path).rename(newPath);
  return newPath;
}

/// Moves [path] to the trash where supported, else deletes it.
Future<void> trashFile(String path) async {
  if (Platform.isMacOS) {
    final r = await Process.run('osascript', [
      '-e',
      'tell application "Finder" to delete POSIX file "$path"',
    ]);
    if (r.exitCode == 0) return;
  }
  await File(path).delete();
}
