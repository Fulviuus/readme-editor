/// Applies misspelling squiggles to an editing span tree: leaf text spans
/// are split at range boundaries and the misspelled segments get a wavy
/// underline. Pure span surgery — total text is preserved exactly, which
/// the editing TextField requires.
library;

import 'package:flutter/widgets.dart';

TextSpan decorateMisspellings(
    TextSpan root, List<TextRange> ranges, Color color) {
  if (ranges.isEmpty) return root;
  final sorted = [...ranges]..sort((a, b) => a.start - b.start);
  var offset = 0;

  bool misspelledAt(int i) {
    for (final r in sorted) {
      if (i >= r.start && i < r.end) return true;
      if (r.start > i) break;
    }
    return false;
  }

  /// Next boundary (range start or end) strictly after [i], or null.
  int? nextBoundary(int i) {
    for (final r in sorted) {
      if (r.start > i) return r.start;
      if (r.end > i) return r.end;
    }
    return null;
  }

  TextStyle squiggle(TextStyle? base) => (base ?? const TextStyle()).copyWith(
        decoration: base?.decoration == null
            ? TextDecoration.underline
            : TextDecoration.combine(
                [base!.decoration!, TextDecoration.underline]),
        decorationColor: color,
        decorationStyle: TextDecorationStyle.wavy,
      );

  InlineSpan walk(InlineSpan span) {
    if (span is! TextSpan) {
      // Placeholders occupy one character in the concatenated text.
      offset += 1;
      return span;
    }
    final children = <InlineSpan>[];
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      var i = 0;
      while (i < text.length) {
        final at = offset + i;
        final wrong = misspelledAt(at);
        final boundary = nextBoundary(at);
        var end = text.length;
        if (boundary != null && boundary - offset < end) {
          end = boundary - offset;
        }
        final segment = text.substring(i, end);
        children.add(TextSpan(
            text: segment, style: wrong ? squiggle(span.style) : null));
        i = end;
      }
      offset += text.length;
    }
    for (final c in span.children ?? const <InlineSpan>[]) {
      children.add(walk(c));
    }
    // Single unstyled segment and no children: keep the original leaf.
    if (text != null &&
        children.length == 1 &&
        (span.children?.isEmpty ?? true) &&
        children.first is TextSpan &&
        (children.first as TextSpan).style == null) {
      return span;
    }
    return TextSpan(style: span.style, children: children);
  }

  return walk(root) as TextSpan;
}
