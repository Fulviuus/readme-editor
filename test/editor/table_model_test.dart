import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/editor/blocks/table_model.dart';

void main() {
  group('TableShape', () {
    test('parses rows, columns and alignments', () {
      final s = TableShape('| a | bb |\n|:--|--:|\n| c | d |');
      expect(s.columnCount, 2);
      expect(s.lineCount, 3);
      expect(s.alignments, [TextAlign.left, TextAlign.right]);
      expect(s.textOf(0, 1), 'bb');
      expect(s.textOf(2, 0), 'c');
    });

    test('rangeOf points at trimmed cell content', () {
      const src = '| a | bb |\n|---|---|\n| c | d |';
      final s = TableShape(src);
      final (a, b) = s.rangeOf(2, 1);
      expect(src.substring(a, b), 'd');
    });

    test('cellForOffset resolves padding positions to the right cell', () {
      const src = '| Ff   | f    |\n| ---- | ---- |';
      final s = TableShape(src);
      // Offset inside the padding after 'Ff'.
      expect(s.cellForOffset(src.indexOf('Ff') + 3), (0, 0));
      expect(s.cellForOffset(src.indexOf('f    |', 7)), (0, 1));
    });
  });

  group('prettifyTable', () {
    test('aligns pipes and pads cells to the widest content', () {
      final pretty = prettifyTable('|Ff|f|\n|---|----|---|\n||f||');
      expect(pretty.split('\n'), [
        '| Ff   | f    |      |',
        '| ---- | ---- | ---- |',
        '|      | f    |      |',
      ]);
    });

    test('preserves center and right alignment colons', () {
      final pretty = prettifyTable('| a | b | c |\n|---|:-:|--:|\n|x|y|z|');
      expect(pretty.split('\n')[1], '| ---- | :--: | ---: |');
    });

    test('pads short rows with empty trailing cells', () {
      final pretty = prettifyTable('| a | b |\n|---|---|\n| only |');
      expect(pretty.split('\n')[2], '| only | ${''.padRight(4)} |');
    });

    test('long content widens the whole column', () {
      final pretty = prettifyTable(
          '| head | x |\n|---|---|\n| longer-content | y |');
      final lines = pretty.split('\n');
      expect(lines[0], '| head           | x    |');
      expect(lines[2], '| longer-content | y    |');
    });

    test('is idempotent', () {
      const src = '|Ff|f|\n|---|---|\n||f|';
      final once = prettifyTable(src);
      expect(prettifyTable(once), once);
    });
  });
}
