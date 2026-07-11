import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/block.dart';
import 'package:readme/src/document/block_splitter.dart';
import 'package:readme/src/editor/inline_renderer.dart';
import 'package:readme/src/editor/offset_runs.dart';
import 'package:readme/src/theme/readme_theme.dart';

ReadmeTheme theme() => ReadmeTheme.fromJson('t', {
      'blockquoteBorder': '#dfe2e5',
      'link': '#4183C4',
      'linkHover': '#4183C4',
      'hr': '#e7e7e7',
      'checkboxAccent': '#4183C4',
      'sidebarBackground': '#fafafa',
      'sidebarForeground': '#777777',
      'sidebarActiveBackground': '#eeeeee',
    });

String spanText(InlineSpan span) {
  final buf = StringBuffer();
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) buf.write(s.text);
    if (s is WidgetSpan) buf.write('￼');
    return true;
  });
  return buf.toString();
}

void main() {
  final r = InlineRenderer(theme());
  final base = theme().bodyStyle;

  group('renderInline', () {
    test('hides markers and produces contiguous runs', () {
      const src = 'a **bold** and `code` end';
      final res = r.renderInline(src, baseStyle: base);
      expect(res.renderedText, 'a bold and code end');
      expect(spanText(res.span), res.renderedText);

      // Runs must cover the whole source contiguously.
      var s = 0;
      for (final run in res.runs) {
        expect(run.sStart, s, reason: 'gap before $run');
        expect(run.sEnd, greaterThanOrEqualTo(run.sStart));
        s = run.sEnd;
      }
      expect(s, src.length);
    });

    test('editing span always preserves every character', () {
      for (final src in [
        '**b** _i_ `c` ~~s~~ [l](u) ![img](x) <https://a.b> \\* text',
        '# heading with **bold**',
        '> quoted *line*\n> two',
        '- item one\n  - nested `two`',
        '| a | **b** |\n|---|---|\n| c | d |',
        '```dart\ncode **not bold**\n```',
      ]) {
        // Editing spans are built per kind; use the renderer's internal path
        // through buildEditingSpan for each derived kind.
        final kind = deriveSingleKind(src) ?? BlockKind.paragraph;
        final span = r.buildEditingSpan(src, kind);
        expect(spanText(span), src, reason: 'kind=$kind src=$src');
      }
    });

    test('inline math renders as one atomic placeholder', () {
      const src = r'so $x^2$ holds';
      final res = r.renderInline(src, baseStyle: base);
      expect(res.renderedText, 'so \u{FFFC} holds');
      expect(spanText(res.span), res.renderedText);
      // Clicking the placeholder or crossing it maps to the math's edges.
      expect(renderedToSource(res.runs, 3), 3);
      expect(renderedToSource(res.runs, 4), 8);
    });

    test('math editing span preserves every character', () {
      const src = r'so $x^2$ holds';
      final span = r.buildEditingSpan(src, BlockKind.paragraph);
      expect(spanText(span), src);
    });

    test('renderedToSource maps clicks through hidden markers', () {
      const src = 'x **bold** y';
      final res = r.renderInline(src, baseStyle: base);
      // rendered: 'x bold y'
      //            01234567
      expect(renderedToSource(res.runs, 0), 0); // before 'x'
      // Boundary between 'x ' and 'bold': either side of the ** is valid.
      expect(renderedToSource(res.runs, 2), anyOf(2, 4));
      expect(renderedToSource(res.runs, 3), 5); // inside 'bold'
      expect(renderedToSource(res.runs, 6), 8); // after 'd'
      expect(renderedToSource(res.runs, 8), 12); // end
    });

    test('sourceToRendered collapses marker positions', () {
      const src = 'x **bold** y';
      final res = r.renderInline(src, baseStyle: base);
      expect(sourceToRendered(res.runs, 4), 2); // 'b'
      expect(sourceToRendered(res.runs, 3), 2); // inside '**' → start of bold
    });

    test('link renders label only', () {
      const src = 'see [docs](https://x.dev) now';
      final res = r.renderInline(src, baseStyle: base);
      expect(res.renderedText, 'see docs now');
    });

    test('link ranges cover labels and autolinks in rendered coords', () {
      const src = 'see [docs](https://x.dev) or https://a.b now';
      final res = r.renderInline(src, baseStyle: base);
      // rendered: 'see docs or https://a.b now'
      expect(res.links, hasLength(2));
      final label = res.links[0];
      expect(res.renderedText.substring(label.rStart, label.rEnd), 'docs');
      expect(label.url, 'https://x.dev');
      final auto = res.links[1];
      expect(res.renderedText.substring(auto.rStart, auto.rEnd),
          'https://a.b');
      expect(auto.url, 'https://a.b');
      expect(label.contains(label.rStart), isTrue);
      expect(label.contains(label.rEnd), isFalse);
    });

    test('bold text produces no link ranges', () {
      final res = r.renderInline('**no links here**', baseStyle: base);
      expect(res.links, isEmpty);
    });

    test('image without builder falls back to alt-ish text', () {
      const src = '![alt](u.png)';
      final res = r.renderInline(src, baseStyle: base);
      expect(res.renderedText, src); // shown literally when no image pipeline
    });
  });
}
