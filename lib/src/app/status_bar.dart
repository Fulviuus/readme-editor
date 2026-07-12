/// 28px status bar: word/character count, outline breadcrumb of the focused
/// block, theme name, source-mode indicator and dirty dot.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../document/block.dart';
import '../document/document.dart';
import '../document/document_controller.dart';
import '../editor/editor_controller.dart';
import '../theme/theme_manager.dart';
import '../util/word_count.dart';
import 'settings_controller.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  /// Titles of the headings enclosing [focusedId], outermost first.
  static List<String> _breadcrumb(Document doc, String? focusedId) {
    if (focusedId == null) return const [];
    final i = doc.indexOfBlock(focusedId);
    if (i < 0) return const [];
    final crumbs = <String>[];
    var level = 7;
    for (var k = i; k >= 0; k--) {
      final block = doc.blocks[k];
      if (block.kind == BlockKind.heading && block.headingLevel < level) {
        crumbs.insert(0, block.headingText);
        level = block.headingLevel;
        if (level == 1) break;
      }
    }
    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    final docCtrl = context.read<DocumentController>();
    final editor = context.read<EditorController>();
    final theme = context.watch<ThemeManager>().current;
    return AnimatedBuilder(
      animation: Listenable.merge([docCtrl, editor]),
      builder: (context, _) {
        final count = WordCountResult.fromDocument(docCtrl.doc);
        final crumbs = _breadcrumb(docCtrl.doc, editor.focusedBlockId);
        final fg = theme.sidebarForeground;
        final style = TextStyle(fontSize: 12, color: fg);
        return Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.sidebarBackground,
            border: Border(top: BorderSide(color: theme.hr)),
          ),
          child: Row(
            children: [
              // Click for the word-count popover (reading time & friends).
              MenuAnchor(
                alignmentOffset: const Offset(0, -8),
                menuChildren: [
                  for (final line in [
                    '${count.words} words',
                    '${count.characters} characters',
                    '${docCtrl.doc.blocks.length} blocks',
                    '~${count.readingMinutes} min read',
                  ])
                    MenuItemButton(
                      onPressed: null,
                      child: Text(line, style: TextStyle(color: fg)),
                    ),
                ],
                builder: (context, controller, _) => InkWell(
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Text(
                    context.watch<SettingsController>().showWordCount
                        ? '${count.words} words · '
                            '${count.characters} characters'
                        : '⋯',
                    style: style,
                  ),
                ),
              ),
              if (crumbs.isNotEmpty) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: MenuAnchor(
                    alignmentOffset: const Offset(0, -8),
                    menuChildren: [
                      for (final entry in docCtrl.doc.outline)
                        MenuItemButton(
                          onPressed: () =>
                              editor.focusBlock(entry.blockId, offset: 0),
                          child: Padding(
                            padding: EdgeInsets.only(
                                left: (entry.level - 1) * 12.0),
                            child: Text(
                              entry.text.isEmpty ? '(untitled)' : entry.text,
                              style: TextStyle(
                                  fontSize: 13, color: theme.foreground),
                            ),
                          ),
                        ),
                      if (docCtrl.doc.outline.isEmpty)
                        MenuItemButton(
                          onPressed: null,
                          child: Text('No headings',
                              style: TextStyle(color: fg)),
                        ),
                    ],
                    builder: (context, controller, _) => InkWell(
                      onTap: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                      child: Text(
                        crumbs.join(' › '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: editor.sourceModeEnabled,
                builder: (context, sourceMode, _) => sourceMode
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          'SOURCE',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                            color: theme.accent,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Text(theme.name, style: style),
              if (docCtrl.dirty) ...[
                const SizedBox(width: 8),
                Text('●', style: TextStyle(fontSize: 9, color: theme.accent)),
              ],
            ],
          ),
        );
      },
    );
  }
}
