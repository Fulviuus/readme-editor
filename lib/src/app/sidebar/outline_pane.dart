/// Heading outline of the open document. Rows indent by heading level and
/// clicking one focuses that block; the heading nearest above the focused
/// block is highlighted.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../document/block.dart';
import '../../document/document.dart';
import '../../document/document_controller.dart';
import '../../editor/editor_controller.dart';
import '../../theme/readme_theme.dart';
import '../../theme/theme_manager.dart';

class OutlinePane extends StatelessWidget {
  const OutlinePane({super.key});

  /// Id of the heading at or nearest above the focused block.
  static String? _currentHeadingId(Document doc, String? focusedId) {
    if (focusedId == null) return null;
    final i = doc.indexOfBlock(focusedId);
    if (i < 0) return null;
    for (var k = i; k >= 0; k--) {
      if (doc.blocks[k].kind == BlockKind.heading) return doc.blocks[k].id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final docCtrl = context.watch<DocumentController>();
    final editor = context.watch<EditorController>();
    final theme = context.watch<ThemeManager>().current;
    final outline = docCtrl.doc.outline;
    if (outline.isEmpty) {
      return Center(
        child: Text(
          'No headings',
          style: TextStyle(fontSize: 13, color: theme.sidebarForeground),
        ),
      );
    }
    final currentId =
        _currentHeadingId(docCtrl.doc, editor.focusedBlockId);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final entry in outline)
          _OutlineRow(
            entry: entry,
            active: entry.blockId == currentId,
            theme: theme,
            onTap: () => editor.focusBlock(entry.blockId),
          ),
      ],
    );
  }
}

class _OutlineRow extends StatelessWidget {
  const _OutlineRow({
    required this.entry,
    required this.active,
    required this.theme,
    required this.onTap,
  });

  final OutlineEntry entry;
  final bool active;
  final ReadmeTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? (theme.sidebarActiveForeground ?? theme.sidebarForeground)
        : theme.sidebarForeground;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active ? theme.sidebarActiveBackground : null,
        padding: EdgeInsets.only(
          left: 12.0 + (entry.level - 1) * 12,
          right: 8,
          top: 4,
          bottom: 4,
        ),
        child: Text(
          entry.text.isEmpty ? '(untitled)' : entry.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: entry.level <= 1 ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
