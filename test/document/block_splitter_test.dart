/// Unit tests for the block scanner (`splitMarkdown`), the derived facts on
/// [Block], and the byte-exact round-trip contract of [Document].
///
/// Expected behavior follows docs/DESIGN-editor-interaction.md §1.1/§1.2.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/block.dart';
import 'package:readme/src/document/block_splitter.dart';
import 'package:readme/src/document/document.dart';

List<Block> blocksOf(String text, {bool isFragment = false}) =>
    splitMarkdown(text, isFragment: isFragment).blocks;

List<BlockKind> kindsOf(String text, {bool isFragment = false}) =>
    [for (final b in blocksOf(text, isFragment: isFragment)) b.kind];

Block singleBlockOf(String text, {bool isFragment = false}) =>
    blocksOf(text, isFragment: isFragment).single;

/// The round-trip contract (§1.2): `serialize(parse(text)) == text`
/// byte-for-byte for any input the scanner accepts.
void expectRoundTrip(String text) {
  expect(Document.parse(text).serialize(), text);
}

void main() {
  group('ATX headings', () {
    test('levels 1-6 are detected with level and text', () {
      for (var level = 1; level <= 6; level++) {
        final block = singleBlockOf('${'#' * level} Title');
        expect(block.kind, BlockKind.heading, reason: 'level $level');
        expect(block.headingLevel, level);
        expect(block.headingText, 'Title');
        expect(block.isSetextHeading, isFalse);
      }
    });

    test('seven hashes is a paragraph', () {
      expect(singleBlockOf('####### nope').kind, BlockKind.paragraph);
    });

    test('hash without following space is a paragraph', () {
      expect(singleBlockOf('#nospace').kind, BlockKind.paragraph);
    });

    test('a bare # (end of line) is a heading', () {
      final block = singleBlockOf('#');
      expect(block.kind, BlockKind.heading);
      expect(block.headingLevel, 1);
    });

    test('an ATX heading is exactly one line', () {
      final blocks = blocksOf('# T\ntext');
      expect(blocks.map((b) => b.kind),
          [BlockKind.heading, BlockKind.paragraph]);
      expect(blocks[1].source, 'text');
      expect(blocks[1].blankLinesBefore, 0);
    });
  });

  group('setext headings', () {
    test('= underline gives level 1', () {
      final block = singleBlockOf('Title\n===');
      expect(block.kind, BlockKind.heading);
      expect(block.headingLevel, 1);
      expect(block.isSetextHeading, isTrue);
      expect(block.headingText, 'Title');
    });

    test('- underline gives level 2', () {
      final block = singleBlockOf('Title\n----');
      expect(block.kind, BlockKind.heading);
      expect(block.headingLevel, 2);
      expect(block.isSetextHeading, isTrue);
    });

    test('underline consumes a multiline paragraph above it', () {
      final block = singleBlockOf('line one\nline two\n====');
      expect(block.kind, BlockKind.heading);
      expect(block.headingLevel, 1);
      expect(block.source, 'line one\nline two\n====');
      expect(block.headingText, 'line one line two');
    });

    test('an underline with no paragraph above is not a setext heading', () {
      // A lone --- is a thematic break; a lone === is a paragraph.
      expect(singleBlockOf('---').kind, BlockKind.thematicBreak);
      expect(singleBlockOf('===').kind, BlockKind.paragraph);
    });
  });

  group('fenced code', () {
    test('backtick fence with info string', () {
      final block = singleBlockOf('```dart\nvoid main() {}\n```');
      expect(block.kind, BlockKind.fencedCode);
      expect(block.fenceLanguage, 'dart');
      expect(block.fenceIsClosed, isTrue);
      expect(block.codeBody, 'void main() {}');
    });

    test('tilde fence', () {
      final block = singleBlockOf('~~~\ncode\n~~~');
      expect(block.kind, BlockKind.fencedCode);
      expect(block.fenceLanguage, isNull);
      expect(block.fenceIsClosed, isTrue);
    });

    test('longer fence is only closed by a fence at least as long', () {
      final block = singleBlockOf('````\n```\nstill code\n````');
      expect(block.kind, BlockKind.fencedCode);
      expect(block.fenceIsClosed, isTrue);
      expect(block.codeBody, '```\nstill code');
    });

    test('closing fence must use the same character', () {
      final block = singleBlockOf('```\ncode\n~~~\n```');
      expect(block.kind, BlockKind.fencedCode);
      expect(block.codeBody, 'code\n~~~');
    });

    test('blank lines inside a fence are swallowed verbatim', () {
      final block = singleBlockOf('```\na\n\nb\n```');
      expect(block.kind, BlockKind.fencedCode);
      expect(block.codeBody, 'a\n\nb');
    });

    test('an unclosed fence swallows everything to the end of input', () {
      final block =
          singleBlockOf('```\ncode\n\n# not a heading\n- not a list');
      expect(block.kind, BlockKind.fencedCode);
      expect(block.fenceIsClosed, isFalse);
      expect(block.source, '```\ncode\n\n# not a heading\n- not a list');
    });

    test('a backtick in a backtick fence info string is not a fence', () {
      final block = singleBlockOf('``` `x` ```\ntext');
      expect(block.kind, BlockKind.paragraph);
      expect(block.source, '``` `x` ```\ntext');
    });

    test('a backtick in a tilde fence info string is fine', () {
      expect(kindsOf('~~~ `x`\ncode\n~~~'), [BlockKind.fencedCode]);
    });
  });

  group('indented code', () {
    test('4-space and tab indents start indented code', () {
      final block = singleBlockOf('    line1\n    line2');
      expect(block.kind, BlockKind.indentedCode);
      expect(block.codeBody, 'line1\nline2');
      expect(singleBlockOf('\tcode').kind, BlockKind.indentedCode);
    });

    test('a single interior blank line stays inside the block', () {
      final block = singleBlockOf('    a\n\n    b');
      expect(block.kind, BlockKind.indentedCode);
      expect(block.source, '    a\n\n    b');
    });

    test('does not interrupt a paragraph', () {
      final block = singleBlockOf('text\n    still the paragraph');
      expect(block.kind, BlockKind.paragraph);
    });

    test('ends before a non-indented line', () {
      expect(kindsOf('    code\nplain'),
          [BlockKind.indentedCode, BlockKind.paragraph]);
    });
  });

  group('blockquote', () {
    test('consecutive > lines form one block', () {
      expect(singleBlockOf('> a\n> b').kind, BlockKind.blockquote);
    });

    test('lazy continuation lines are absorbed', () {
      final block = singleBlockOf('> quote\nlazy continuation');
      expect(block.kind, BlockKind.blockquote);
      expect(block.source, '> quote\nlazy continuation');
    });

    test('a blank line ends the quote', () {
      final blocks = blocksOf('> a\n\n> b');
      expect(blocks.map((b) => b.kind),
          [BlockKind.blockquote, BlockKind.blockquote]);
      expect(blocks[1].blankLinesBefore, 1);
    });

    test('a >-only line continues the quote', () {
      expect(kindsOf('> a\n>\n> b'), [BlockKind.blockquote]);
    });

    test('an interrupting construct ends the lazy continuation', () {
      expect(kindsOf('> a\n# h'), [BlockKind.blockquote, BlockKind.heading]);
      expect(kindsOf('> a\n- item'), [BlockKind.blockquote, BlockKind.list]);
    });
  });

  group('lists', () {
    test('simple unordered list is one block', () {
      final block = singleBlockOf('- a\n- b');
      expect(block.kind, BlockKind.list);
      expect(block.isOrderedList, isFalse);
      expect(block.hasTaskItems, isFalse);
    });

    test('nested items and indented continuations stay in the block', () {
      final block = singleBlockOf('- a\n  - b\n    deep continuation');
      expect(block.kind, BlockKind.list);
      expect(block.source, '- a\n  - b\n    deep continuation');
    });

    test('lazy continuation text stays in the list', () {
      expect(singleBlockOf('- item\nwrapped text').kind, BlockKind.list);
    });

    test('a single interior blank line stays in the list (loose list)', () {
      final block = singleBlockOf('- a\n\n- b');
      expect(block.kind, BlockKind.list);
      expect(block.source, '- a\n\n- b');
    });

    test('interior blank before an indented continuation stays', () {
      final block = singleBlockOf('- a\n\n  still item a');
      expect(block.kind, BlockKind.list);
      expect(block.source, '- a\n\n  still item a');
    });

    test('two consecutive blank lines split the list', () {
      final blocks = blocksOf('- a\n\n\n- b');
      expect(blocks.map((b) => b.kind), [BlockKind.list, BlockKind.list]);
      expect(blocks[0].source, '- a');
      expect(blocks[1].source, '- b');
      expect(blocks[1].blankLinesBefore, 2);
    });

    test('ordered list with . delimiter', () {
      final block = singleBlockOf('1. a\n2. b');
      expect(block.kind, BlockKind.list);
      expect(block.isOrderedList, isTrue);
    });

    test('ordered list with ) delimiter', () {
      final block = singleBlockOf('1) a\n2) b');
      expect(block.kind, BlockKind.list);
      expect(block.isOrderedList, isTrue);
    });

    test('task list items set hasTaskItems', () {
      final block = singleBlockOf('- [ ] one\n- [x] two');
      expect(block.kind, BlockKind.list);
      expect(block.hasTaskItems, isTrue);
    });
  });

  group('tables', () {
    test('table with leading pipes', () {
      final block = singleBlockOf('| a | b |\n| --- | --- |\n| 1 | 2 |');
      expect(block.kind, BlockKind.table);
      expect(block.lines, hasLength(3));
    });

    test('table without leading pipes', () {
      expect(singleBlockOf('a | b\n--- | ---\n1 | 2').kind, BlockKind.table);
    });

    test('alignment colons in the delimiter row', () {
      expect(singleBlockOf('| a | b |\n|:---|---:|\n| 1 | 2 |').kind,
          BlockKind.table);
    });

    test('a pipe line without a delimiter row is a paragraph', () {
      expect(singleBlockOf('a | b\njust text').kind, BlockKind.paragraph);
    });

    test('the table ends at the first line without a pipe', () {
      final blocks = blocksOf('| a |\n| --- |\n| 1 |\nplain');
      expect(blocks.map((b) => b.kind),
          [BlockKind.table, BlockKind.paragraph]);
      expect(blocks[0].lines, hasLength(3));
    });

    test('a table start interrupts a paragraph', () {
      expect(kindsOf('text\n| a | b |\n| --- | --- |'),
          [BlockKind.paragraph, BlockKind.table]);
    });

    test(
        'delimiter row with fewer cells than the header is not a table '
        '(design §1.1 rule 6)', () {
      // `x | y` followed by a lone `---` must scan as a setext heading, not
      // as a one-column table.
      final block = singleBlockOf('x | y\n---');
      expect(block.kind, BlockKind.heading);
      expect(block.headingLevel, 2);
    });
  });

  group('thematic breaks', () {
    test('---, ***, ___ are thematic breaks', () {
      expect(singleBlockOf('---').kind, BlockKind.thematicBreak);
      expect(singleBlockOf('***').kind, BlockKind.thematicBreak);
      expect(singleBlockOf('___').kind, BlockKind.thematicBreak);
    });

    test('spaced markers beat list detection', () {
      expect(singleBlockOf('- - -').kind, BlockKind.thematicBreak);
      expect(singleBlockOf('* * *').kind, BlockKind.thematicBreak);
    });

    test('a break between paragraphs stays its own block', () {
      expect(kindsOf('a\n\n---\n\nb'),
          [BlockKind.paragraph, BlockKind.thematicBreak, BlockKind.paragraph]);
    });
  });

  group('HTML blocks', () {
    test('an HTML block runs until a blank line', () {
      final block = singleBlockOf('<div>\n<span>x</span>\n</div>');
      expect(block.kind, BlockKind.html);
      expect(block.lines, hasLength(3));
    });

    test('a blank line ends the HTML block', () {
      expect(kindsOf('<div>\n\ntext'),
          [BlockKind.html, BlockKind.paragraph]);
    });

    test('comments and closing tags start HTML blocks', () {
      expect(singleBlockOf('<!-- note -->').kind, BlockKind.html);
      expect(singleBlockOf('</div>').kind, BlockKind.html);
    });
  });

  group('math blocks', () {
    test('multiline \$\$ ... \$\$', () {
      final block = singleBlockOf('\$\$\nE = mc^2\n\$\$');
      expect(block.kind, BlockKind.mathBlock);
      expect(block.lines, hasLength(3));
    });

    test('single-line \$\$x\$\$', () {
      final block = singleBlockOf(r'$$x^2$$');
      expect(block.kind, BlockKind.mathBlock);
      expect(block.lines, hasLength(1));
    });

    test('an unclosed math block swallows to the end of input', () {
      final block = singleBlockOf('\$\$\nx = 1');
      expect(block.kind, BlockKind.mathBlock);
      expect(block.source, '\$\$\nx = 1');
    });
  });

  group('front matter', () {
    test('--- fence at document start is front matter', () {
      final blocks = blocksOf('---\ntitle: x\n---\n\n# H');
      expect(blocks.map((b) => b.kind),
          [BlockKind.frontMatter, BlockKind.heading]);
      expect(blocks[0].source, '---\ntitle: x\n---');
    });

    test('front matter may be closed by ...', () {
      expect(singleBlockOf('---\na: 1\n...').kind, BlockKind.frontMatter);
    });

    test('--- later in the document is never front matter', () {
      final kinds = kindsOf('text\n\n---\ntitle: x\n---');
      expect(kinds, isNot(contains(BlockKind.frontMatter)));
      expect(kinds[1], BlockKind.thematicBreak);
    });

    test('unclosed front matter falls back to a thematic break', () {
      expect(kindsOf('---\ntitle: x'),
          [BlockKind.thematicBreak, BlockKind.paragraph]);
    });

    test('isFragment: true disables front matter detection', () {
      final blocks = blocksOf('---\ntitle: x\n---', isFragment: true);
      expect(blocks.first.kind, BlockKind.thematicBreak);
      expect(blocks.map((b) => b.kind),
          isNot(contains(BlockKind.frontMatter)));
    });
  });

  group('round-trip: serialize(parse(text)) == text', () {
    const fixtures = <String, String>{
      'empty document': '',
      'plain paragraphs': 'one\n\ntwo\n',
      'heading directly followed by paragraph, no final newline': '# T\ntext',
      'no final newline': 'alpha\n\nbeta',
      'two blank lines between blocks': 'one\n\n\ntwo\n',
      'three blank lines between blocks': 'one\n\n\n\ntwo\n',
      'trailing blank lines': 'para\n\n\n',
      'leading blank lines': '\n\nfirst\n',
      'CRLF line endings': '# Title\r\n\r\nBody text\r\n\r\n- a\r\n- b\r\n',
      'CRLF without final newline': 'a\r\n\r\nb',
      'BOM': '\uFEFF# Title\n\nBody\n',
      'BOM only': '\uFEFF',
      'BOM with CRLF': '\uFEFFa\r\nb\r\n',
      'unclosed fence': '```dart\ncode\n',
      'fence with interior blank lines': '```\na\n\nb\n```\n',
      'loose list': '- a\n\n- b\n',
      'double blank splits lists': '- a\n\n\n- b\n',
      'setext heading': 'Title\n=====\n\nBody\n',
      'front matter': '---\ntitle: x\n---\n\nbody\n',
      'quote with lazy continuation': '> q\nlazy\n\nafter\n',
      'table then paragraph': '| a |\n| --- |\n| 1 |\nplain\n',
      'trailing whitespace on content lines': 'line one  \nline two\t\n',
      'paragraph interrupted by heading': 'text\n# H\ntext\n',
    };

    fixtures.forEach((name, text) {
      test(name, () => expectRoundTrip(text));
    });
  });

  group('kitchen sink', () {
    final sink = [
      '---',
      'title: Kitchen Sink',
      'author: tester',
      '---',
      '',
      '# Heading One',
      '',
      'Intro paragraph',
      'spanning two lines with **bold** and `code`.',
      '',
      'Setext Title',
      '============',
      '',
      'Setext Sub',
      '----------',
      '',
      '## Sub heading',
      '',
      '> quote line one',
      '> quote line two',
      'lazy continuation of the quote',
      '',
      '- item one',
      '- item two',
      '  wrapped item text',
      '  - nested item',
      '',
      '  loose continuation',
      '',
      '',
      '1) first',
      '2) second',
      '',
      '',
      '- [ ] todo item',
      '- [x] done item',
      '',
      '```dart',
      'void main() {',
      "  print('fenced');",
      '}',
      '```',
      '',
      '~~~',
      'tilde fenced',
      '~~~',
      '',
      '    indented code',
      '    more indented',
      '',
      '| Col A | Col B |',
      '| ----- | ----- |',
      '| 1     | 2     |',
      '',
      'Left | Right',
      '---- | -----',
      'a    | b',
      '',
      '---',
      '',
      '* * *',
      '',
      r'$$',
      'E = mc^2',
      r'$$',
      '',
      r'$$x^2$$',
      '',
      '<div class="wrap">',
      '  <span>html content</span>',
      '</div>',
      '',
      'Final paragraph.',
      '',
    ].join('\n');

    test('scans into the expected block kinds', () {
      expect(kindsOf(sink), [
        BlockKind.frontMatter,
        BlockKind.heading, // # Heading One
        BlockKind.paragraph, // intro (two lines)
        BlockKind.heading, // Setext Title (=)
        BlockKind.heading, // Setext Sub (-)
        BlockKind.heading, // ## Sub heading
        BlockKind.blockquote, // quote + lazy continuation
        BlockKind.list, // bullets + nested + loose continuation
        BlockKind.list, // ordered with )
        BlockKind.list, // tasks
        BlockKind.fencedCode, // ```dart
        BlockKind.fencedCode, // ~~~
        BlockKind.indentedCode,
        BlockKind.table, // with pipes
        BlockKind.table, // without leading pipes
        BlockKind.thematicBreak, // ---
        BlockKind.thematicBreak, // * * *
        BlockKind.mathBlock, // multiline
        BlockKind.mathBlock, // single-line
        BlockKind.html,
        BlockKind.paragraph, // final
      ]);
    });

    test('round-trips exactly (LF)', () => expectRoundTrip(sink));

    test('round-trips exactly (CRLF + BOM)', () {
      expectRoundTrip('\uFEFF${sink.replaceAll('\n', '\r\n')}');
    });

    test('round-trips exactly without final newline', () {
      expectRoundTrip(sink.substring(0, sink.length - 1));
    });
  });

  group('deriveSingleKind', () {
    test('single-block sources re-derive their kind', () {
      expect(deriveSingleKind('# x'), BlockKind.heading);
      expect(deriveSingleKind('x'), BlockKind.paragraph);
      expect(deriveSingleKind('- a'), BlockKind.list);
      expect(deriveSingleKind('> q'), BlockKind.blockquote);
      expect(deriveSingleKind('```\ncode\n```'), BlockKind.fencedCode);
    });

    test('a blank line inside the source returns null', () {
      expect(deriveSingleKind('a\n\nb'), isNull);
    });

    test('trailing blank lines return null', () {
      expect(deriveSingleKind('a\n'), isNull);
    });

    test('leading blank lines return null', () {
      expect(deriveSingleKind('\na'), isNull);
    });

    test('a source scanning as two blocks returns null', () {
      expect(deriveSingleKind('```\ncode\n```\ntail'), isNull);
    });

    test('--- is a thematic break, never front matter (fragment mode)', () {
      expect(deriveSingleKind('---'), BlockKind.thematicBreak);
    });
  });
}
