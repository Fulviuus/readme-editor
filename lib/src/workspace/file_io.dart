/// Platform-neutral file-system facade for the workspace layer.
///
/// The conditional export picks the `dart:io` + `package:watcher`
/// implementation on desktop and a stub on the web, so nothing the web build
/// reaches imports `dart:io` (web-compile rule, docs/ARCHITECTURE.md).
/// Callers check [supportsFileSystem] before offering path-based features.
library;

export 'file_io_web.dart'
    if (dart.library.io) 'file_io_io.dart'
    show
        copyIntoFolder,
        duplicateFile,
        listMarkdownTree,
        readBinaryFileSync,
        readTextFile,
        renameFile,
        revealInFileManager,
        supportsFileSystem,
        trashFile,
        watchFolder,
        writeBinaryFile,
        writeTextFile;

/// Cancels a [watchFolder] subscription.
typedef WatchCancel = Future<void> Function();

/// One node of the sidebar folder tree: a directory (with [children]) or a
/// markdown/text file. Within one directory, subdirectories come first, each
/// group sorted alphabetically (case-insensitive).
class FileTreeNode {
  const FileTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const [],
  });

  /// File or directory name (no path separators).
  final String name;

  /// Absolute path of this entry.
  final String path;

  final bool isDirectory;

  /// Child nodes for directories; always empty for files.
  final List<FileTreeNode> children;

  @override
  String toString() =>
      'FileTreeNode(${isDirectory ? 'dir' : 'file'} $path'
      '${isDirectory ? ', ${children.length} children' : ''})';
}
