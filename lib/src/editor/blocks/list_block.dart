/// Rendered list block: one row per source line — bullet/number/checkbox
/// glyph plus inline content — with per-line offset runs for caret transfer.
library;

import 'package:flutter/material.dart';

import '../../document/block.dart';
import '../editor_controller.dart';
import '../offset_runs.dart';
import '../rendered_block.dart';

final _itemRe = RegExp(
  r'^(\s*)([-*+]|\d{1,9}[.)])([ \t]+)(?:(\[[ xX]\])([ \t]+))?',
);

class ListBlockView extends StatelessWidget {
  const ListBlockView({super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final theme = editor.theme;
    final rows = <Widget>[];
    var lineStart = 0;
    final lines = block.source.split('\n');
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      final m = _itemRe.firstMatch(line);
      final base = lineStart;
      if (m == null) {
        // Continuation line: indent + inline content.
        final indentLen = RegExp(r'^\s*').firstMatch(line)!.end;
        rows.add(
          _row(
            indentPx: _indentPx(line.substring(0, indentLen), theme.fontSize),
            glyph: null,
            content: line.substring(indentLen),
            contentBase: base + indentLen,
            hiddenPrefix: (base, base + indentLen),
            lineIndex: -1,
          ),
        );
      } else {
        final indent = m.group(1)!;
        final marker = m.group(2)!;
        final checkbox = m.group(4);
        final ordered = RegExp(r'^\d').hasMatch(marker);
        rows.add(
          _row(
            indentPx: _indentPx(indent, theme.fontSize),
            glyph: checkbox != null
                ? _TaskCheckbox(
                    checked: checkbox.toLowerCase() == '[x]',
                    editor: editor,
                    blockId: block.id,
                    lineIndex: li,
                  )
                : ordered
                ? Text(
                    '$marker ',
                    style: theme.bodyStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.foreground,
                    ),
                  )
                : Text(
                    '•  ',
                    style: theme.bodyStyle.copyWith(
                      color: theme.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            content: line.substring(m.end),
            contentBase: base + m.end,
            hiddenPrefix: (base, base + m.end),
            lineIndex: 0,
          ),
        );
      }
      lineStart += line.length + 1;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  /// One nesting level per two spaces; a tab counts as one level.
  double _indentPx(String indent, double fontSize) {
    final expanded = indent.replaceAll('\t', '  ').length;
    return (expanded / 2).floorToDouble() * fontSize * 1.4;
  }

  Widget _row({
    required double indentPx,
    required Widget? glyph,
    required String content,
    required int contentBase,
    required (int, int) hiddenPrefix,
    required int lineIndex,
  }) {
    final theme = editor.theme;
    final r = editor.renderer.renderInline(content, baseStyle: theme.bodyStyle);
    final runs = <OffsetRun>[
      OffsetRun(RunKind.hidden, 0, 0, hiddenPrefix.$1, hiddenPrefix.$2),
      for (final run in r.runs)
        OffsetRun(
          run.kind,
          run.rStart,
          run.rEnd,
          run.sStart + contentBase,
          run.sEnd + contentBase,
        ),
    ];
    return Padding(
      padding: EdgeInsets.only(left: indentPx, top: 1, bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: theme.fontSize * 1.5,
            child: glyph ?? const SizedBox.shrink(),
          ),
          Expanded(
            child: TappableInlineText(
              span: r.span,
              runs: runs,
              links: r.links,
              onOpenLink: editor.openLink,
              onCaret: (offset) => editor.focusBlock(block.id, offset: offset),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCheckbox extends StatelessWidget {
  const _TaskCheckbox({
    required this.checked,
    required this.editor,
    required this.blockId,
    required this.lineIndex,
  });

  final bool checked;
  final EditorController editor;
  final String blockId;
  final int lineIndex;

  @override
  Widget build(BuildContext context) {
    final theme = editor.theme;
    final size = theme.fontSize * 0.85;
    return GestureDetector(
      onTap: () => editor.toggleTask(blockId, lineIndex),
      // Keep the box at its own size — the glyph slot's tight constraints
      // would otherwise stretch it to the full slot width.
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(top: theme.fontSize * 0.25),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: checked ? theme.checkboxAccent : null,
              border: Border.all(
                color:
                    theme.checkboxBorder ??
                    theme.checkboxAccent.withValues(alpha: 0.7),
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: checked
                ? Icon(Icons.check, size: size * 0.8, color: theme.background)
                : null,
          ),
        ),
      ),
    );
  }
}
