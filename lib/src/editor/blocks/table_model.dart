/// Table source parsing and formatting, shared by the rendered table widget
/// and the in-place cell editor.
///
/// Rows are addressed by SOURCE LINE index: 0 = header, 1 = delimiter,
/// 2+ = data rows. Navigation helpers skip the delimiter row.
library;

import 'package:flutter/widgets.dart' show TextAlign;

class TableShape {
  TableShape(this.source) {
    _lines = source.split('\n');
    for (var li = 0; li < _lines.length; li++) {
      _cells.add(_splitCells(_lines[li]));
    }
    alignments = _parseAlignments(_lines.length > 1 ? _lines[1] : '');
    columnCount = _cells
        .asMap()
        .entries
        .where((e) => e.key != 1)
        .fold<int>(1, (m, e) => e.value.length > m ? e.value.length : m);
  }

  final String source;
  late final List<String> _lines;
  final List<List<(int start, int end)>> _cells = [];
  late final List<TextAlign> alignments;
  late final int columnCount;

  int get lineCount => _lines.length;
  List<String> get lines => _lines;

  /// Line-local content ranges (trimmed) of the cells on [line].
  List<(int, int)> cellsOnLine(int line) =>
      line < _cells.length ? _cells[line] : const [];

  /// Source-global (start, end) of the trimmed content of [row]/[col].
  /// A column beyond the row's cells clamps to the row's last cell.
  (int, int) rangeOf(int row, int col) {
    var base = 0;
    for (var i = 0; i < row && i < _lines.length; i++) {
      base += _lines[i].length + 1;
    }
    final cells = cellsOnLine(row);
    if (cells.isEmpty) return (base, base + _lineAt(row).length);
    final c = col.clamp(0, cells.length - 1);
    return (base + cells[c].$1, base + cells[c].$2);
  }

  String _lineAt(int row) => row < _lines.length ? _lines[row] : '';

  String textOf(int row, int col) {
    final (a, b) = rangeOf(row, col);
    return source.substring(a, b);
  }

  /// (row, col) for a source offset — col from unescaped-pipe counting so
  /// carets sitting in cell padding resolve correctly.
  (int, int) cellForOffset(int offset) {
    var lineStart = 0;
    var row = 0;
    for (; row < _lines.length; row++) {
      final end = lineStart + _lines[row].length;
      if (offset <= end) break;
      lineStart = end + 1;
    }
    row = row.clamp(0, _lines.length - 1);
    final line = _lineAt(row);
    final local = (offset - lineStart).clamp(0, line.length);
    var pipes = 0;
    for (var i = 0; i < local; i++) {
      if (line[i] == '|' && (i == 0 || line[i - 1] != r'\')) pipes++;
    }
    final leading = line.trimLeft().startsWith('|') ? 1 : 0;
    final col = (pipes - leading).clamp(0, columnCount - 1);
    return (row, col);
  }

  /// Line-local trimmed cell ranges between unescaped pipes.
  static List<(int, int)> _splitCells(String line) {
    final bounds = <int>[];
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '|' && (i == 0 || line[i - 1] != r'\')) bounds.add(i);
    }
    final startsWithPipe = line.trimLeft().startsWith('|');
    final endsWithPipe = RegExp(r'(^|[^\\])\|[ \t]*$').hasMatch(line);
    final cuts = <(int, int)>[];
    var prev = startsWithPipe && bounds.isNotEmpty ? bounds.first + 1 : 0;
    for (final b in bounds) {
      if (startsWithPipe && b == bounds.first) continue;
      cuts.add((prev, b));
      prev = b + 1;
    }
    if (!endsWithPipe) cuts.add((prev, line.length));
    final out = <(int, int)>[];
    for (final (a0, b0) in cuts) {
      var a = a0;
      var b = b0;
      while (a < b && line[a] == ' ') {
        a++;
      }
      while (b > a && line[b - 1] == ' ') {
        b--;
      }
      out.add((a, b));
    }
    return out;
  }

  static List<TextAlign> _parseAlignments(String delimiterLine) {
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
}

/// Builds prettified table source from cell texts (header first, no
/// delimiter row — it is generated) and per-column alignments: aligned
/// pipes, cells padded to the widest content, min-4-dash delimiters.
String buildTableSource(List<List<String>> rows, List<TextAlign> alignments) {
  final cols =
      rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  String cellAt(List<String> row, int c) => c < row.length ? row[c] : '';

  const minWidth = 4;
  final widths = List<int>.generate(cols, (c) {
    var w = minWidth;
    for (final row in rows) {
      if (cellAt(row, c).length > w) w = cellAt(row, c).length;
    }
    return w;
  });

  String delimiterCell(int c) {
    final align = c < alignments.length ? alignments[c] : TextAlign.left;
    final w = widths[c];
    return switch (align) {
      TextAlign.center => ':${'-' * (w - 2)}:',
      TextAlign.right => '${'-' * (w - 1)}:',
      _ => '-' * w,
    };
  }

  String formatRow(List<String> cells) =>
      '| ${[for (var c = 0; c < cols; c++) cellAt(cells, c).padRight(widths[c])].join(' | ')} |';

  return [
    formatRow(rows.isEmpty ? const [''] : rows.first),
    '| ${[for (var c = 0; c < cols; c++) delimiterCell(c)].join(' | ')} |',
    for (final row in rows.skip(1)) formatRow(row),
  ].join('\n');
}

/// Reformats table source with aligned pipes and padded cells:
///
/// ```
/// | Ff   | f    |      |
/// | ---- | ---- | ---- |
/// |      | f    |      |
/// ```
///
/// Cell CONTENT is preserved exactly (trimmed); only padding and structure
/// normalize. Rows shorter than the widest row gain empty trailing cells.
String prettifyTable(String source) {
  final shape = TableShape(source);
  if (shape.lineCount < 2) return source;
  final cols = shape.columnCount;
  final rows = <List<String>>[];
  for (var li = 0; li < shape.lineCount; li++) {
    if (li == 1) continue;
    rows.add([
      for (var c = 0; c < cols; c++)
        c < shape.cellsOnLine(li).length ? shape.textOf(li, c) : '',
    ]);
  }
  return buildTableSource(rows, shape.alignments);
}
