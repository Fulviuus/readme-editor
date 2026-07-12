/// TextEditingController for source mode: live markdown syntax coloring
/// over the whole raw document. Line-based with fenced-code state, inline
/// tokens styled through the shared tokenizer. The concatenated span text
/// is always byte-identical to [text] — the same invariant the focused
/// block editor keeps.
library;

import 'package:flutter/widgets.dart';

import '../theme/readme_theme.dart';
import 'inline_tokenizer.dart';

class SourceHighlightController extends TextEditingController {
  SourceHighlightController({super.text});

  /// Swapped by the view when the theme changes.
  ReadmeTheme? theme;

  /// Preferences > Editor > Source mode.
  bool highlightEnabled = true;

  static final _fenceRe = RegExp(r'^( {0,3})(`{3,}|~{3,})(.*)$');
  static final _headingRe = RegExp(r'^( {0,3}#{1,6}[ \t]+)(.*?)([ \t]+#+[ \t]*)?$');
  static final _setextRe = RegExp(r'^ {0,3}(=+|-{3,})[ \t]*$');
  static final _quoteRe = RegExp(r'^( {0,3}(?:> ?)+)(.*)$');
  static final _listRe = RegExp(
      r'^(\s*(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)(.*)$');
  static final _hrRe = RegExp(r'^ {0,3}([-_*])( *\1){2,}[ \t]*$');
  static final _refDefRe = RegExp(r'^ {0,3}\[[^\]]+\]:\s');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = theme;
    if (t == null || !highlightEnabled || text.isEmpty) {
      return TextSpan(style: style, text: text);
    }
    final base = style ?? t.monoStyle;
    final marker = base.copyWith(color: t.syntaxMarkerColor);
    final spans = <InlineSpan>[];
    var inFence = false;
    String? fenceChar;

    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final fence = _fenceRe.firstMatch(line);
      if (inFence) {
        final closes = fence != null && fence.group(2)![0] == fenceChar;
        if (closes) {
          spans.add(TextSpan(text: line, style: marker));
          inFence = false;
        } else {
          spans.add(TextSpan(
              text: line,
              style: base.copyWith(
                  color: t.codeBlockForeground ?? t.foreground)));
        }
      } else if (fence != null) {
        inFence = true;
        fenceChar = fence.group(2)![0];
        final markerEnd =
            fence.group(1)!.length + fence.group(2)!.length;
        spans
          ..add(TextSpan(
              text: line.substring(0, markerEnd), style: marker))
          ..add(TextSpan(
              text: line.substring(markerEnd),
              style: base.copyWith(color: t.accent)));
      } else if (_hrRe.hasMatch(line) || _setextRe.hasMatch(line)) {
        spans.add(TextSpan(text: line, style: marker));
      } else if (_headingRe.firstMatch(line) case final m?) {
        spans.add(TextSpan(text: m.group(1), style: marker));
        _inline(spans, m.group(2)!,
            base.copyWith(fontWeight: FontWeight.w700), t);
        if (m.group(3) != null) {
          spans.add(TextSpan(text: m.group(3), style: marker));
        }
      } else if (_quoteRe.firstMatch(line) case final m?
          when line.trimLeft().startsWith('>')) {
        spans.add(TextSpan(text: m.group(1), style: marker));
        _inline(
            spans,
            m.group(2)!,
            base.copyWith(
                color: t.blockquoteTextColor, fontStyle: FontStyle.italic),
            t);
      } else if (_listRe.firstMatch(line) case final m?) {
        spans.add(TextSpan(
            text: m.group(1), style: base.copyWith(color: t.accent)));
        _inline(spans, m.group(2)!, base, t);
      } else if (line.contains('|')) {
        // Table-ish line: dim the pipes.
        var start = 0;
        for (var c = 0; c < line.length; c++) {
          if (line[c] == '|') {
            if (c > start) {
              _inline(spans, line.substring(start, c), base, t);
            }
            spans.add(TextSpan(text: '|', style: marker));
            start = c + 1;
          }
        }
        if (start < line.length) {
          _inline(spans, line.substring(start), base, t);
        }
      } else if (_refDefRe.hasMatch(line)) {
        spans.add(TextSpan(
            text: line, style: base.copyWith(color: t.syntaxMarkerColor)));
      } else {
        _inline(spans, line, base, t);
      }
      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: base));
      }
    }
    return TextSpan(style: base, children: spans);
  }

  /// Inline markdown within one line, markers dimmed — the source-mode
  /// (monospace) cousin of the block editor's editing spans.
  void _inline(
      List<InlineSpan> out, String s, TextStyle style, ReadmeTheme t) {
    if (s.isEmpty) return;
    final marker = style.copyWith(color: t.syntaxMarkerColor);

    void walk(List<InlineNode> nodes, int from, int to, TextStyle st) {
      var cursor = from;
      void plain(int upTo) {
        if (upTo > cursor) {
          out.add(TextSpan(text: s.substring(cursor, upTo), style: st));
        }
        cursor = upTo;
      }

      for (final n in nodes) {
        plain(n.start);
        switch (n) {
          case TextNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.end), style: st));
          case EscapeNode():
            out
              ..add(TextSpan(
                  text: s.substring(n.start, n.start + 1), style: marker))
              ..add(TextSpan(
                  text: s.substring(n.start + 1, n.end), style: st));
          case CodeNode():
            out
              ..add(TextSpan(
                  text: s.substring(n.start, n.contentStart),
                  style: marker))
              ..add(TextSpan(
                  text: s.substring(n.contentStart, n.contentEnd),
                  style: t.inlineCodeStyle
                      .copyWith(fontSize: st.fontSize, height: st.height)))
              ..add(TextSpan(
                  text: s.substring(n.contentEnd, n.end), style: marker));
          case EmphasisNode():
            var inner = st;
            if (n.isStrikethrough) {
              inner =
                  inner.copyWith(decoration: TextDecoration.lineThrough);
            } else {
              if (n.isStrong) {
                inner = inner.copyWith(fontWeight: FontWeight.w700);
              }
              if (n.isEmphasis) {
                inner = inner.copyWith(fontStyle: FontStyle.italic);
              }
            }
            out.add(TextSpan(
                text: s.substring(n.start, n.start + n.delimiterLength),
                style: marker));
            walk(n.children, n.start + n.delimiterLength,
                n.end - n.delimiterLength, inner);
            out.add(TextSpan(
                text: s.substring(n.end - n.delimiterLength, n.end),
                style: marker));
          case LinkNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.labelStart), style: marker));
            walk(n.children, n.labelStart, n.labelEnd,
                st.copyWith(color: t.link));
            out
              ..add(TextSpan(
                  text: s.substring(n.labelEnd, n.urlStart),
                  style: marker))
              ..add(TextSpan(
                  text: s.substring(n.urlStart, n.urlEnd), style: marker))
              ..add(TextSpan(
                  text: s.substring(n.urlEnd, n.end), style: marker));
          case RefLinkNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.labelStart), style: marker));
            walk(n.children, n.labelStart, n.labelEnd,
                st.copyWith(color: t.link));
            out.add(TextSpan(
                text: s.substring(n.labelEnd, n.end), style: marker));
          case ImageNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.end), style: marker));
          case AutolinkNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.end),
                style: st.copyWith(color: t.link)));
          case HtmlTagNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.end), style: marker));
          case CommentNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.end), style: marker));
          case FootnoteRefNode():
            out.add(TextSpan(
                text: s.substring(n.start, n.end),
                style: st.copyWith(color: t.link)));
          case MathNode():
            out
              ..add(TextSpan(
                  text: s.substring(n.start, n.contentStart),
                  style: marker))
              ..add(TextSpan(
                  text: s.substring(n.contentStart, n.contentEnd),
                  style: st.copyWith(color: t.accent)))
              ..add(TextSpan(
                  text: s.substring(n.contentEnd, n.end), style: marker));
          case SpanSyntaxNode():
            out
              ..add(TextSpan(
                  text: s.substring(n.start, n.contentStart),
                  style: marker))
              ..add(TextSpan(
                  text: s.substring(n.contentStart, n.contentEnd),
                  style: st))
              ..add(TextSpan(
                  text: s.substring(n.contentEnd, n.end), style: marker));
        }
        cursor = n.end;
      }
      plain(to);
    }

    walk(tokenizeInline(s), 0, s.length, style);
  }
}
