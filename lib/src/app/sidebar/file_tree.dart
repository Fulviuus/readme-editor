/// Recursive folder tree for the sidebar (workspace.tree). Directories
/// expand/collapse with chevrons; markdown files open through the shell's
/// confirm-if-dirty flow ([FileTree.onOpenFile]).
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../theme/readme_theme.dart';
import '../../theme/theme_manager.dart';
import '../../workspace/file_io.dart' show FileTreeNode;
import '../../workspace/workspace_controller.dart';

class FileTree extends StatefulWidget {
  const FileTree({super.key, required this.onOpenFile});

  /// Invoked with the file's path; the shell runs confirm-if-dirty and then
  /// workspace.openPath.
  final void Function(String path) onOpenFile;

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  final Set<String> _expanded = {};

  static bool _isMarkdown(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final theme = context.watch<ThemeManager>().current;
    final folder = workspace.folder;
    if (folder == null) return _emptyState(workspace, theme);

    final rows = <Widget>[];
    _addNodes(rows, workspace.tree, 0, workspace.activeFilePath, theme);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
          child: Text(
            p.basename(folder).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: theme.sidebarForeground.withValues(alpha: 0.8),
            ),
          ),
        ),
        ...rows,
      ],
    );
  }

  Widget _emptyState(WorkspaceController workspace, ReadmeTheme theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No folder open',
            style: TextStyle(fontSize: 13, color: theme.sidebarForeground),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: workspace.openFolderDialog,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.accent,
              side: BorderSide(color: theme.accent.withValues(alpha: 0.6)),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: const Text('Open a folder'),
          ),
        ],
      ),
    );
  }

  void _addNodes(List<Widget> rows, List<FileTreeNode> nodes, int depth,
      String? activePath, ReadmeTheme theme) {
    for (final node in nodes) {
      if (node.isDirectory) {
        final expanded = _expanded.contains(node.path);
        rows.add(_row(
          node: node,
          depth: depth,
          theme: theme,
          active: false,
          enabled: true,
          icon: expanded ? Icons.expand_more : Icons.chevron_right,
          onTap: () => setState(() {
            if (!_expanded.add(node.path)) _expanded.remove(node.path);
          }),
        ));
        if (expanded) {
          _addNodes(rows, node.children, depth + 1, activePath, theme);
        }
      } else {
        final markdown = _isMarkdown(node.path);
        rows.add(_row(
          node: node,
          depth: depth,
          theme: theme,
          active: node.path == activePath,
          enabled: markdown,
          icon: Icons.description_outlined,
          onTap: markdown ? () => widget.onOpenFile(node.path) : null,
        ));
      }
    }
  }

  Widget _row({
    required FileTreeNode node,
    required int depth,
    required ReadmeTheme theme,
    required bool active,
    required bool enabled,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final fg = active
        ? (theme.sidebarActiveForeground ?? theme.sidebarForeground)
        : theme.sidebarForeground;
    final color = enabled ? fg : fg.withValues(alpha: 0.45);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 26,
        color: active ? theme.sidebarActiveBackground : null,
        padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 8),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
