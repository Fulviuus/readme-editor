import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/editor/spell/spell_decoration.dart';

const _red = Color(0xFFFF0000);

String plain(InlineSpan span) {
  final buf = StringBuffer();
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) buf.write(s.text);
    return true;
  });
  return buf.toString();
}

/// Collects (text, isWavy) leaf segments in order.
List<(String, bool)> segments(InlineSpan span) {
  final out = <(String, bool)>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null && s.text!.isNotEmpty) {
      out.add((
        s.text!,
        s.style?.decorationStyle == TextDecorationStyle.wavy,
      ));
    }
    return true;
  });
  return out;
}

void main() {
  group('decorateMisspellings', () {
    test('splits a flat span at range boundaries, text preserved', () {
      final root = const TextSpan(text: 'helo wrld ok');
      final out = decorateMisspellings(
        root,
        const [
          TextRange(start: 0, end: 4),
          TextRange(start: 5, end: 9),
        ],
        _red,
      );
      expect(plain(out), 'helo wrld ok');
      expect(segments(out), [
        ('helo', true),
        (' ', false),
        ('wrld', true),
        (' ok', false),
      ]);
    });

    test('crosses styled child spans without changing total text', () {
      final root = const TextSpan(children: [
        TextSpan(text: 'a '),
        TextSpan(
            text: 'boldd',
            style: TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' z'),
      ]);
      final out = decorateMisspellings(
          root, const [TextRange(start: 2, end: 7)], _red);
      expect(plain(out), 'a boldd z');
      final segs = segments(out);
      expect(segs, [('a ', false), ('boldd', true), (' z', false)]);
    });

    test('range inside a leaf splits only that leaf', () {
      final root = const TextSpan(text: 'say teh word');
      final out = decorateMisspellings(
          root, const [TextRange(start: 4, end: 7)], _red);
      expect(plain(out), 'say teh word');
      expect(segments(out), [
        ('say ', false),
        ('teh', true),
        (' word', false),
      ]);
    });

    test('no ranges returns the original span', () {
      const root = TextSpan(text: 'fine');
      expect(decorateMisspellings(root, const [], _red), same(root));
    });

    test('keeps existing decorations on misspelled segments', () {
      final root = const TextSpan(
        text: 'wrld',
        style: TextStyle(decoration: TextDecoration.lineThrough),
      );
      final out = decorateMisspellings(
          root, const [TextRange(start: 0, end: 4)], _red);
      final seg = segments(out).single;
      expect(seg.$2, isTrue);
      final style = _firstStyle(out)!;
      expect(style.decoration!.contains(TextDecoration.underline), isTrue);
      expect(style.decoration!.contains(TextDecoration.lineThrough), isTrue);
    });
  });
}

TextStyle? _firstStyle(InlineSpan span) {
  TextStyle? found;
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null && s.style != null) {
      found ??= s.style;
      return false;
    }
    return true;
  });
  return found;
}
