/// Rendered table: a real [Table] widget; each cell keeps its source range so
/// a click focuses the block with the caret inside that cell.
library;

import 'package:flutter/material.dart';

import '../../document/block.dart';
import '../editor_controller.dart';
import '../offset_runs.dart';
import '../rendered_block.dart';

class _Cell {
  _Cell(this.text, this.start, this.end);
  final String text; // trimmed content
  final int start; // source offset of trimmed content
  final int end;
}

class TableBlockView extends StatelessWidget {
  const TableBlockView({super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final theme = editor.theme;
    final lines = block.source.split('\n');
    if (lines.length < 2) {
      return Text(block.source, style: theme.bodyStyle);
    }

    final alignments = _alignments(lines[1]);
    final rows = <List<_Cell>>[];
    var base = 0;
    for (var li = 0; li < lines.length; li++) {
      if (li != 1) rows.add(_splitCells(lines[li], base));
      base += lines[li].length + 1;
    }
    final columnCount =
        rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);

    final tableRows = <TableRow>[];
    for (var ri = 0; ri < rows.length; ri++) {
      final isHeader = ri == 0;
      final stripe = !isHeader && ri.isEven; // data rows 2,4,… (1-based even)
      tableRows.add(TableRow(
        decoration: BoxDecoration(
          color: isHeader
              ? theme.tableHeaderBackground
              : stripe
                  ? theme.tableStripeBackground
                  : null,
        ),
        children: [
          for (var ci = 0; ci < columnCount; ci++)
            _cellWidget(
              ci < rows[ri].length ? rows[ri][ci] : null,
              isHeader: isHeader,
              align: ci < alignments.length ? alignments[ci] : TextAlign.left,
            ),
        ],
      ));
    }

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: theme.tableBorder != null
          ? TableBorder.all(color: theme.tableBorder!, width: 1)
          : null,
      children: tableRows,
    );
  }

  Widget _cellWidget(_Cell? cell, {required bool isHeader, required TextAlign align}) {
    final theme = editor.theme;
    final style = isHeader
        ? theme.bodyStyle.copyWith(fontWeight: FontWeight.w700)
        : theme.bodyStyle;
    if (cell == null) {
      return const Padding(padding: EdgeInsets.all(8), child: SizedBox());
    }
    final r = editor.renderer.renderInline(cell.text, baseStyle: style);
    final runs = [
      for (final run in r.runs)
        OffsetRun(run.kind, run.rStart, run.rEnd, run.sStart + cell.start,
            run.sEnd + cell.start),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => editor.focusBlock(block.id, offset: cell.start),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: 10, vertical: theme.fontSize * 0.35),
        child: TappableInlineText(
          span: r.span,
          runs: runs,
          textAlign: align,
          onCaret: (offset) => editor.focusBlock(block.id, offset: offset),
        ),
      ),
    );
  }

  List<TextAlign> _alignments(String delimiterLine) {
    final cells = delimiterLine.split('|').where((c) => c.trim().isNotEmpty);
    return [
      for (final c in cells)
        switch ((c.trim().startsWith(':'), c.trim().endsWith(':'))) {
          (true, true) => TextAlign.center,
          (false, true) => TextAlign.right,
          _ => TextAlign.left,
        },
    ];
  }

  List<_Cell> _splitCells(String line, int base) {
    final bounds = <int>[];
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '|' && (i == 0 || line[i - 1] != r'\')) bounds.add(i);
    }
    final startsWithPipe = line.trimLeft().startsWith('|');
    // A trailing `\|` is cell content, not a closing pipe.
    final endsWithPipe =
        RegExp(r'(^|[^\\])\|[ \t]*$').hasMatch(line);
    final cuts = <(int, int)>[];
    var prev = startsWithPipe ? bounds.first + 1 : 0;
    for (final b in bounds) {
      if (startsWithPipe && b == bounds.first) continue;
      cuts.add((prev, b));
      prev = b + 1;
    }
    if (!endsWithPipe) cuts.add((prev, line.length));
    final cells = <_Cell>[];
    for (final (a, b) in cuts) {
      var s = a;
      var e = b;
      while (s < e && line[s] == ' ') {
        s++;
      }
      while (e > s && line[e - 1] == ' ') {
        e--;
      }
      cells.add(_Cell(line.substring(s, e), base + s, base + e));
    }
    return cells;
  }
}
