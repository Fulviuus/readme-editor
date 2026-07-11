import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/editor/inline_tokenizer.dart';

void main() {
  group('tokenizeInline', () {
    test('plain text is one TextNode', () {
      final nodes = tokenizeInline('hello world');
      expect(nodes, hasLength(1));
      expect(nodes.first, isA<TextNode>());
      expect((nodes.first.start, nodes.first.end), (0, 11));
    });

    test('strong', () {
      final nodes = tokenizeInline('a **bold** b');
      expect(nodes, hasLength(3));
      final em = nodes[1] as EmphasisNode;
      expect(em.delimiterLength, 2);
      expect(em.isStrong, isTrue);
      expect(em.isEmphasis, isFalse);
      expect((em.start, em.end), (2, 10));
      final inner = em.children.single as TextNode;
      expect((inner.start, inner.end), (4, 8));
    });

    test('emphasis with underscore respects intraword rule', () {
      expect(tokenizeInline('snake_case_name').whereType<EmphasisNode>(),
          isEmpty);
      final nodes = tokenizeInline('a _em_ b');
      expect(nodes[1], isA<EmphasisNode>());
    });

    test('triple asterisk is strong+em', () {
      final em = tokenizeInline('***x***').single as EmphasisNode;
      expect(em.delimiterLength, 3);
      expect(em.isStrong, isTrue);
      expect(em.isEmphasis, isTrue);
    });

    test('nested strong inside em-ish content', () {
      final nodes = tokenizeInline('**a *b* c**');
      final outer = nodes.single as EmphasisNode;
      expect(outer.isStrong, isTrue);
      expect(outer.children.whereType<EmphasisNode>(), hasLength(1));
    });

    test('strikethrough', () {
      final s = tokenizeInline('~~gone~~').single as EmphasisNode;
      expect(s.isStrikethrough, isTrue);
    });

    test('single tilde is not strikethrough', () {
      expect(
          tokenizeInline('~x~').whereType<EmphasisNode>(), isEmpty);
    });

    test('unmatched delimiters stay literal', () {
      expect(tokenizeInline('2 * 3 = 6').whereType<EmphasisNode>(), isEmpty);
      expect(tokenizeInline('a ** b').whereType<EmphasisNode>(), isEmpty);
    });

    test('code span protects content', () {
      final nodes = tokenizeInline('x `a *b*` y');
      final code = nodes[1] as CodeNode;
      expect((code.contentStart, code.contentEnd), (3, 8));
      expect(nodes.whereType<EmphasisNode>(), isEmpty);
    });

    test('double-backtick code span', () {
      final code = tokenizeInline('``a ` b``').single as CodeNode;
      expect((code.start, code.end), (0, 9));
      expect((code.contentStart, code.contentEnd), (2, 7));
    });

    test('emphasis closer is not found inside a code span', () {
      // The * inside the backticks must not close the emphasis.
      final nodes = tokenizeInline('*a `b*` c*');
      final em = nodes.first as EmphasisNode;
      expect(em.end, 10);
    });

    test('link with title', () {
      final link =
          tokenizeInline('[text](https://x.dev "T")').single as LinkNode;
      expect(link.url, 'https://x.dev');
      expect((link.labelStart, link.labelEnd), (1, 5));
      expect(link.children.single, isA<TextNode>());
    });

    test('image', () {
      final img = tokenizeInline('![alt](pic.png)').single as ImageNode;
      expect(img.alt, 'alt');
      expect(img.url, 'pic.png');
    });

    test('bracketed autolink and bare url', () {
      final a = tokenizeInline('<https://a.b>').single as AutolinkNode;
      expect(a.bracketed, isTrue);
      expect(a.url, 'https://a.b');

      final nodes = tokenizeInline('see https://x.dev/p, ok');
      final bare = nodes.whereType<AutolinkNode>().single;
      expect(bare.url, 'https://x.dev/p'); // trailing comma trimmed
    });

    test('escape', () {
      final nodes = tokenizeInline(r'\*not em\*');
      expect(nodes.whereType<EmphasisNode>(), isEmpty);
      expect(nodes.whereType<EscapeNode>(), hasLength(2));
    });

    test('inline html tag', () {
      final nodes = tokenizeInline('a <br> b');
      expect(nodes[1], isA<HtmlTagNode>());
    });

    test('malformed link falls back to text', () {
      final nodes = tokenizeInline('[no url] here');
      expect(nodes.whereType<LinkNode>(), isEmpty);
    });

    test('HTML comment is one CommentNode', () {
      final nodes = tokenizeInline('a <!-- hi --> b');
      expect(nodes[1], isA<CommentNode>());
      expect((nodes[1].start, nodes[1].end), (2, 13));
    });

    test('unterminated comment stays literal', () {
      expect(
          tokenizeInline('a <!-- no end').whereType<CommentNode>(), isEmpty);
    });

    test('reference link (full and shortcut)', () {
      final full = tokenizeInline('see [text][ref] here')
          .whereType<RefLinkNode>()
          .single;
      expect(full.reference, 'ref');
      expect((full.labelStart, full.labelEnd), (5, 9));

      final shortcut =
          tokenizeInline('see [ref] here').whereType<RefLinkNode>().single;
      expect(shortcut.reference, 'ref');

      final collapsed =
          tokenizeInline('[text][] x').whereType<RefLinkNode>().single;
      expect(collapsed.reference, 'text');
    });

    test('inline link is not treated as a reference link', () {
      final nodes = tokenizeInline('[a](http://x)');
      expect(nodes.whereType<RefLinkNode>(), isEmpty);
      expect(nodes.whereType<LinkNode>(), hasLength(1));
    });

    test('footnote reference', () {
      final fn =
          tokenizeInline('text[^1] more').whereType<FootnoteRefNode>().single;
      expect(fn.id, '1');
      expect((fn.start, fn.end), (4, 8));
    });

    test('inline math', () {
      final m = tokenizeInline(r'so $x^2 + y$ holds')
          .whereType<MathNode>()
          .single;
      expect((m.start, m.end), (3, 12));
      expect((m.contentStart, m.contentEnd), (4, 11));
    });

    test(r'prices are not math: closer followed by a digit', () {
      expect(tokenizeInline(r'costs $5 vs $6 total').whereType<MathNode>(),
          isEmpty);
    });

    test(r'price then math: $5 or $x$ parses only $x$', () {
      final m =
          tokenizeInline(r'$5 or $x$').whereType<MathNode>().single;
      expect((m.contentStart, m.contentEnd), (7, 8));
    });

    test('space just inside a delimiter is not math', () {
      expect(tokenizeInline(r'a $ x$ b').whereType<MathNode>(), isEmpty);
      expect(tokenizeInline(r'a $x $ b').whereType<MathNode>(), isEmpty);
    });

    test('math does not span lines and needs content', () {
      expect(tokenizeInline('a \$x\ny\$ b').whereType<MathNode>(), isEmpty);
      expect(tokenizeInline(r'a $$ b').whereType<MathNode>(), isEmpty);
    });

    test(r'escaped \$ neither opens nor closes math', () {
      expect(tokenizeInline(r'pay \$10 now').whereType<MathNode>(), isEmpty);
      final m = tokenizeInline(r'$a\$b$').whereType<MathNode>().single;
      expect((m.contentStart, m.contentEnd), (1, 5));
    });
  });

  group('plainTextOfInline', () {
    test('strips markers, keeps code/link labels, drops comments and tags', () {
      // The dropped comment and <br> each leave their surrounding spaces.
      expect(plainTextOfInline('a **b** `c` [d](u) <!-- x --> <br> e'),
          'a b c d   e');
    });

    test('keeps image alt text', () {
      expect(plainTextOfInline('see ![a cat](cat.png) here'),
          'see a cat here');
    });

    test('keeps math content without delimiters', () {
      expect(plainTextOfInline(r'so $x^2$ holds'), 'so x^2 holds');
    });
  });
}
