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

    // Size the marker column off the widest marker in the block so numbers
    // right-align ("9." and "10." end at the same x) and every item's text
    // starts at the same column, a fixed small gap after its marker.
    final markerStyle = theme.bodyStyle;
    var markerWidth = theme.fontSize * 0.6; // bullet minimum
    for (final line in lines) {
      final m = _itemRe.firstMatch(line);
      final marker = m?.group(2);
      if (m == null) continue;
      if (m.group(4) != null) {
        markerWidth =
            markerWidth < theme.fontSize * 0.9 ? theme.fontSize * 0.9 : markerWidth;
      } else if (RegExp(r'^\d').hasMatch(marker!)) {
        final painter = TextPainter(
          text: TextSpan(text: marker, style: markerStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        if (painter.width > markerWidth) markerWidth = painter.width;
      }
    }
    final gap = theme.fontSize * 0.45;
    final slot = markerWidth + gap;

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
            slot: slot,
            gap: gap,
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
                // The box rides inside a real text line: the paragraph
                // supplies the baseline the row aligns on (a bare box has
                // none) and `middle` centers it on that line.
                ? Text.rich(
                    TextSpan(children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: _TaskCheckbox(
                          checked: checkbox.toLowerCase() == '[x]',
                          editor: editor,
                          blockId: block.id,
                          lineIndex: li,
                        ),
                      ),
                    ]),
                    style: theme.bodyStyle,
                  )
                : ordered
                ? Text(marker,
                    style: markerStyle.copyWith(color: theme.foreground))
                : Text('•',
                    style: markerStyle.copyWith(color: theme.accent)),
            slot: slot,
            gap: gap,
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
    required double slot,
    required double gap,
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
        // Markers sit on the first text line's baseline — top alignment
        // leaves them floating high because of the text's leading.
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // Marker column: right-aligned against a fixed gap so the marker
          // hugs its text and all items share one text column.
          SizedBox(
            width: slot,
            child: glyph == null
                ? null
                : Padding(
                    padding: EdgeInsets.only(right: gap),
                    child: Align(
                      alignment: Alignment.topRight,
                      heightFactor: 1,
                      child: glyph,
                    ),
                  ),
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: checked ? theme.checkboxAccent : null,
          border: Border.all(
            color: theme.checkboxBorder ??
                theme.checkboxAccent.withValues(alpha: 0.7),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: checked
            ? Icon(Icons.check, size: size * 0.8, color: theme.background)
            : null,
      ),
    );
  }
}
