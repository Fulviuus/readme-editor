/// Articles pane: a flat, alphabetical list of every markdown file in the
/// open folder (the sidebar's counterpart to the hierarchical file tree).
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../theme/theme_manager.dart';
import '../../workspace/file_io.dart';
import '../../workspace/workspace_controller.dart';

class ArticlesPane extends StatelessWidget {
  const ArticlesPane({super.key, required this.onOpenFile});

  final void Function(String path) onOpenFile;

  static void _collect(List<FileTreeNode> nodes, List<FileTreeNode> out) {
    for (final node in nodes) {
      if (node.isDirectory) {
        _collect(node.children, out);
      } else {
        out.add(node);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final theme = context.watch<ThemeManager>().current;
    final fg = theme.sidebarForeground;

    if (workspace.folder == null) {
      return Center(
        child: Text('Open a folder to list articles',
            style: TextStyle(fontSize: 12, color: fg)),
      );
    }
    final files = <FileTreeNode>[];
    _collect(workspace.tree, files);
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (files.isEmpty) {
      return Center(
        child: Text('No markdown files',
            style: TextStyle(fontSize: 12, color: fg)),
      );
    }
    final root = workspace.folder!;
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, i) {
        final file = files[i];
        final active = file.path == workspace.activeFilePath;
        final dir = p.dirname(p.relative(file.path, from: root));
        return InkWell(
          onTap: () => onOpenFile(file.path),
          child: Container(
            color: active ? theme.sidebarActiveBackground : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basenameWithoutExtension(file.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: active
                        ? (theme.sidebarActiveForeground ?? fg)
                        : theme.foreground.withValues(alpha: 0.85),
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (dir != '.')
                  Text(
                    dir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: fg),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
