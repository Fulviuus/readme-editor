/// Builds Flutter spans from tokenized inline markdown, in two modes:
///
/// - RENDERED (unfocused blocks): markers hidden, full styling, plus an
///   [OffsetRun] list so a click can be mapped back to a source offset.
/// - EDITING (the focused block): every source character present exactly
///   once — markers visible but dimmed — because the TextField's span text
///   must equal `block.source` for editing to work.
///
/// Links deliberately get no tap recognizers in rendered mode: clicking any
/// rendered content focuses the block for editing; URL opening goes through
/// the context/app menu.
library;

import 'package:flutter/widgets.dart';

import '../document/block.dart';
import '../theme/readme_theme.dart';
import 'inline_tokenizer.dart';
import 'offset_runs.dart';

class InlineRenderResult {
  const InlineRenderResult(this.span, this.renderedText, this.runs, this.links);
  final InlineSpan span;
  final String renderedText;
  final List<OffsetRun> runs;

  /// Hyperlink hotspots in RENDERED-text coordinates (same space as the
  /// runs' r-offsets) — used for Cmd+click / context-menu link actions.
  final List<LinkRange> links;
}

/// A clickable link region within one rendered text region.
class LinkRange {
  const LinkRange(this.rStart, this.rEnd, this.url);
  final int rStart;
  final int rEnd;
  final String url;

  bool contains(int renderedOffset) =>
      renderedOffset >= rStart && renderedOffset < rEnd;
}

/// Provides a widget for an image URL (injected by the app so the editor
/// layer stays free of dart:io / workspace knowledge).
typedef ImageBuilder = Widget Function(String url, String alt);

class InlineRenderer {
  InlineRenderer(this.theme, {this.imageBuilder});

  final ReadmeTheme theme;
  final ImageBuilder? imageBuilder;

  /// Document-level `[ref]: url` definitions, updated by the editor when the
  /// document changes. Used to resolve reference-style links.
  Map<String, String> linkDefinitions = const {};

  /// Footnote id → 1-based number, for superscript markers.
  Map<String, int> footnoteNumbers = const {};

  // ---- Rendered mode ----

  /// Renders [source] (or a slice of it) with markers hidden. Run offsets in
  /// the result are relative to the slice; callers add their `sourceBase`.
  InlineRenderResult renderInline(
    String source, {
    required TextStyle baseStyle,
  }) {
    final nodes = tokenizeInline(source);
    final rb = RunBuilder();
    final text = StringBuffer();
    final links = <LinkRange>[];
    final children = _renderNodes(source, nodes, baseStyle, rb, text, links);
    return InlineRenderResult(
      TextSpan(style: baseStyle, children: children),
      text.toString(),
      rb.runs,
      links,
    );
  }

  static final _uOpenRe = RegExp(r'^<u\s*>$', caseSensitive: false);
  static final _uCloseRe = RegExp(r'^</u\s*>$', caseSensitive: false);

  List<InlineSpan> _renderNodes(
    String s,
    List<InlineNode> nodes,
    TextStyle style,
    RunBuilder rb,
    StringBuffer out,
    List<LinkRange> links,
  ) {
    final spans = <InlineSpan>[];
    // <u>…</u> spans toggle underline for the nodes between the tags.
    var underline = 0;
    TextStyle active() => underline > 0
        ? style.copyWith(decoration: TextDecoration.underline)
        : style;

    void emitText(int start, int end, TextStyle st) {
      if (end <= start) return;
      final t = s.substring(start, end);
      spans.add(TextSpan(text: t, style: st));
      rb.text(start, end);
      out.write(t);
    }

    for (final node in nodes) {
      switch (node) {
        case TextNode():
          emitText(node.start, node.end, active());
        case EscapeNode():
          rb.hidden(node.start, node.start + 1);
          emitText(node.start + 1, node.end, active());
        case CodeNode():
          rb.hidden(node.start, node.contentStart);
          emitText(node.contentStart, node.contentEnd,
              theme.inlineCodeStyle.copyWith(height: style.height));
          rb.hidden(node.contentEnd, node.end);
        case EmphasisNode():
          rb.hidden(node.start, node.start + node.delimiterLength);
          var st = active();
          if (node.isStrikethrough) {
            st = st.copyWith(decoration: TextDecoration.lineThrough);
          } else {
            if (node.isStrong) st = st.copyWith(fontWeight: FontWeight.w700);
            if (node.isEmphasis) st = st.copyWith(fontStyle: FontStyle.italic);
          }
          spans.addAll(_renderNodes(s, node.children, st, rb, out, links));
          rb.hidden(node.end - node.delimiterLength, node.end);
        case LinkNode():
          rb.hidden(node.start, node.labelStart);
          final st = active().merge(theme.linkStyle);
          final linkStart = rb.renderedLength;
          spans.addAll(_renderNodes(s, node.children, st, rb, out, links));
          if (rb.renderedLength > linkStart) {
            links.add(LinkRange(linkStart, rb.renderedLength, node.url));
          }
          rb.hidden(node.labelEnd, node.end);
        case RefLinkNode():
          final url = linkDefinitions[node.reference];
          if (url == null) {
            // Unresolved: show the literal source.
            emitText(node.start, node.end, active());
          } else {
            rb.hidden(node.start, node.labelStart);
            final st = active().merge(theme.linkStyle);
            final linkStart = rb.renderedLength;
            spans.addAll(_renderNodes(s, node.children, st, rb, out, links));
            if (rb.renderedLength > linkStart) {
              links.add(LinkRange(linkStart, rb.renderedLength, url));
            }
            rb.hidden(node.labelEnd, node.end);
          }
        case FootnoteRefNode():
          final n = footnoteNumbers[node.id];
          final label = n?.toString() ?? node.id;
          spans.add(TextSpan(
            text: label,
            style: active().copyWith(
              color: theme.link,
              fontFeatures: const [FontFeature.superscripts()],
              fontSize: (active().fontSize ?? theme.fontSize) * 0.85,
            ),
          ));
          rb.atomic(node.start, node.end, label.length);
          out.write(label);
        case ImageNode():
          final w = imageBuilder?.call(node.url, node.alt);
          if (w != null) {
            spans.add(WidgetSpan(child: w));
            rb.atomic(node.start, node.end, 1);
            out.write('￼');
          } else {
            // No image pipeline (tests): show the alt text.
            emitText(node.start, node.end, style);
          }
        case AutolinkNode():
          if (node.bracketed) rb.hidden(node.start, node.contentStart);
          final autoStart = rb.renderedLength;
          emitText(node.contentStart, node.contentEnd,
              active().merge(theme.linkStyle));
          links.add(LinkRange(autoStart, rb.renderedLength, node.url));
          if (node.bracketed) rb.hidden(node.contentEnd, node.end);
        case HtmlTagNode():
          final tag = s.substring(node.start, node.end);
          if (_uOpenRe.hasMatch(tag)) {
            underline++;
            rb.hidden(node.start, node.end);
          } else if (_uCloseRe.hasMatch(tag)) {
            if (underline > 0) underline--;
            rb.hidden(node.start, node.end);
          } else {
            emitText(node.start, node.end,
                style.copyWith(color: theme.syntaxMarkerColor));
          }
        case CommentNode():
          rb.hidden(node.start, node.end);
      }
    }
    return spans;
  }

  // ---- Editing mode (focused block) ----

  TextStyle editingBaseStyle(Block block) => switch (block.kind) {
        BlockKind.heading => theme.headingStyle(block.headingLevel),
        BlockKind.fencedCode ||
        BlockKind.indentedCode ||
        BlockKind.mathBlock ||
        BlockKind.frontMatter ||
        BlockKind.html =>
          theme.monoStyle,
        _ => theme.bodyStyle,
      };

  /// Builds the focused-block span: concatenated text == [source] exactly.
  TextSpan buildEditingSpan(String source, BlockKind kind,
      {int? headingLevel}) {
    final marker = TextStyle(color: theme.syntaxMarkerColor);
    switch (kind) {
      case BlockKind.fencedCode:
      case BlockKind.indentedCode:
      case BlockKind.mathBlock:
      case BlockKind.frontMatter:
      case BlockKind.html:
        return _buildVerbatimSpan(source, kind, marker);
      case BlockKind.heading:
        return _buildHeadingSpan(source, headingLevel ?? 1, marker);
      case BlockKind.blockquote:
        return _buildPrefixedSpan(
          source,
          RegExp(r'^ {0,3}(?:> ?)+'),
          marker,
          theme.bodyStyle.copyWith(
            color: theme.blockquoteTextColor,
            fontStyle: theme.blockquoteItalic ? FontStyle.italic : null,
          ),
        );
      case BlockKind.list:
        // Marker must be followed by whitespace (or end the line) — a
        // continuation line starting with `*emphasis*` is not a marker.
        return _buildPrefixedSpan(
          source,
          RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])(?:[ \t]+\[[ xX]\])?(?:[ \t]+|$)'),
          TextStyle(color: theme.accent),
          theme.bodyStyle,
        );
      case BlockKind.table:
        return _buildTableSpan(source, marker);
      case BlockKind.thematicBreak:
        return TextSpan(text: source, style: theme.bodyStyle.merge(marker));
      case BlockKind.paragraph:
        return TextSpan(
          style: theme.bodyStyle,
          children: _editingNodes(source, 0, source.length, theme.bodyStyle),
        );
    }
  }

  /// Inline content with visible, dimmed markers.
  List<InlineSpan> _editingNodes(
      String s, int from, int to, TextStyle style) {
    final nodes = _parseSlice(s, from, to);
    final spans = <InlineSpan>[];
    final marker = TextStyle(color: theme.syntaxMarkerColor);
    var underline = 0;
    TextStyle active() => underline > 0
        ? style.copyWith(decoration: TextDecoration.underline)
        : style;

    void put(int a, int b, TextStyle st) {
      if (b > a) spans.add(TextSpan(text: s.substring(a, b), style: st));
    }

    for (final node in nodes) {
      switch (node) {
        case TextNode():
          put(node.start, node.end, active());
        case EscapeNode():
          put(node.start, node.start + 1, style.merge(marker));
          put(node.start + 1, node.end, style);
        case CodeNode():
          put(node.start, node.contentStart, marker.copyWith(
              fontFamily: theme.monoFontFamily.firstOrNull));
          put(node.contentStart, node.contentEnd,
              theme.inlineCodeStyle.copyWith(height: style.height));
          put(node.contentEnd, node.end, marker.copyWith(
              fontFamily: theme.monoFontFamily.firstOrNull));
        case EmphasisNode():
          var st = style;
          if (node.isStrikethrough) {
            st = st.copyWith(decoration: TextDecoration.lineThrough);
          } else {
            if (node.isStrong) st = st.copyWith(fontWeight: FontWeight.w700);
            if (node.isEmphasis) st = st.copyWith(fontStyle: FontStyle.italic);
          }
          put(node.start, node.start + node.delimiterLength, style.merge(marker));
          spans.addAll(_editingNodes(
              s, node.start + node.delimiterLength,
              node.end - node.delimiterLength, st));
          put(node.end - node.delimiterLength, node.end, style.merge(marker));
        case LinkNode():
          put(node.start, node.labelStart, style.merge(marker));
          spans.addAll(_editingNodes(
              s, node.labelStart, node.labelEnd, style.merge(theme.linkStyle)));
          put(node.labelEnd, node.urlStart, style.merge(marker));
          put(node.urlStart, node.urlEnd,
              style.copyWith(color: theme.syntaxMarkerColor));
          put(node.urlEnd, node.end, style.merge(marker));
        case ImageNode():
          put(node.start, node.end, style.merge(marker));
        case AutolinkNode():
          if (node.bracketed) put(node.start, node.contentStart, style.merge(marker));
          put(node.contentStart, node.contentEnd, style.merge(theme.linkStyle));
          if (node.bracketed) put(node.contentEnd, node.end, style.merge(marker));
        case HtmlTagNode():
          final tag = s.substring(node.start, node.end);
          if (_uOpenRe.hasMatch(tag)) underline++;
          if (_uCloseRe.hasMatch(tag) && underline > 0) underline--;
          put(node.start, node.end, style.merge(marker));
        case CommentNode():
          put(node.start, node.end, style.merge(marker));
        case RefLinkNode():
          put(node.start, node.labelStart, style.merge(marker));
          spans.addAll(_editingNodes(
              s, node.labelStart, node.labelEnd, style.merge(theme.linkStyle)));
          put(node.labelEnd, node.end, style.merge(marker));
        case FootnoteRefNode():
          put(node.start, node.end, style.merge(theme.linkStyle));
      }
    }
    return spans;
  }

  List<InlineNode> _parseSlice(String s, int from, int to) {
    if (from == 0 && to == s.length) return tokenizeInline(s);
    final slice = s.substring(from, to);
    return tokenizeInline(slice)
        .map((n) => _shift(n, from))
        .toList(growable: false);
  }

  InlineNode _shift(InlineNode n, int d) => switch (n) {
        TextNode() => TextNode(n.start + d, n.end + d),
        EscapeNode() => EscapeNode(n.start + d, n.end + d),
        CodeNode() => CodeNode(n.start + d, n.end + d, n.contentStart + d,
            n.contentEnd + d),
        EmphasisNode() => EmphasisNode(n.start + d, n.end + d,
            n.delimiterLength, n.marker,
            n.children.map((c) => _shift(c, d)).toList(growable: false)),
        LinkNode() => LinkNode(n.start + d, n.end + d, n.labelStart + d,
            n.labelEnd + d, n.urlStart + d, n.urlEnd + d, n.url,
            n.children.map((c) => _shift(c, d)).toList(growable: false)),
        ImageNode() => ImageNode(n.start + d, n.end + d, n.alt, n.url),
        AutolinkNode() =>
          AutolinkNode(n.start + d, n.end + d, n.url, bracketed: n.bracketed),
        HtmlTagNode() => HtmlTagNode(n.start + d, n.end + d),
        CommentNode() => CommentNode(n.start + d, n.end + d),
        RefLinkNode() => RefLinkNode(n.start + d, n.end + d, n.labelStart + d,
            n.labelEnd + d, n.reference,
            n.children.map((c) => _shift(c, d)).toList(growable: false)),
        FootnoteRefNode() => FootnoteRefNode(n.start + d, n.end + d, n.id),
      };

  TextSpan _buildHeadingSpan(String source, int level, TextStyle marker) {
    final style = theme.headingStyle(level);
    final lines = source.split('\n');
    // Setext heading: content lines + fully-dimmed underline.
    if (!lines.first.trimLeft().startsWith('#') && lines.length > 1) {
      final contentLen =
          lines.sublist(0, lines.length - 1).join('\n').length;
      return TextSpan(style: style, children: [
        ..._editingNodes(source, 0, contentLen, style),
        TextSpan(text: source.substring(contentLen), style: style.merge(marker)),
      ]);
    }
    final m = RegExp(r'^ {0,3}#{1,6}[ \t]*').firstMatch(source);
    final prefixEnd = m?.end ?? 0;
    return TextSpan(style: style, children: [
      TextSpan(text: source.substring(0, prefixEnd), style: style.merge(marker)),
      ..._editingNodes(source, prefixEnd, source.length, style),
    ]);
  }

  /// Per-line prefix (quote `>`, list markers) dimmed/tinted, rest inline.
  TextSpan _buildPrefixedSpan(String source, RegExp prefixRe,
      TextStyle prefixStyle, TextStyle contentStyle) {
    final children = <InlineSpan>[];
    var lineStart = 0;
    while (lineStart <= source.length) {
      final lineEnd = source.indexOf('\n', lineStart);
      final end = lineEnd < 0 ? source.length : lineEnd;
      final line = source.substring(lineStart, end);
      final m = prefixRe.firstMatch(line);
      final prefixEnd = lineStart + (m?.end ?? 0);
      if (m != null && m.end > 0) {
        children.add(TextSpan(
            text: source.substring(lineStart, prefixEnd),
            style: contentStyle.merge(prefixStyle)));
      }
      children.addAll(_editingNodes(source, prefixEnd, end, contentStyle));
      if (lineEnd < 0) break;
      children.add(TextSpan(text: '\n', style: contentStyle));
      lineStart = lineEnd + 1;
    }
    return TextSpan(style: contentStyle, children: children);
  }

  TextSpan _buildTableSpan(String source, TextStyle marker) {
    final body = theme.bodyStyle;
    final children = <InlineSpan>[];
    final lines = source.split('\n');
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      if (li == 1) {
        // Delimiter row: fully dimmed.
        children.add(TextSpan(text: line, style: body.merge(marker)));
      } else {
        var start = 0;
        for (var i = 0; i <= line.length; i++) {
          final isPipe = i < line.length &&
              line[i] == '|' &&
              (i == 0 || line[i - 1] != r'\');
          if (isPipe || i == line.length) {
            if (i > start) {
              children.add(TextSpan(text: line.substring(start, i),
                  style: li == 0 ? body.copyWith(fontWeight: FontWeight.w700) : body));
            }
            if (isPipe) {
              children.add(TextSpan(text: '|', style: body.merge(marker)));
            }
            start = i + 1;
          }
        }
      }
      if (li < lines.length - 1) {
        children.add(TextSpan(text: '\n', style: body));
      }
    }
    return TextSpan(style: body, children: children);
  }

  /// Fence/math/front-matter: delimiter lines dimmed, body mono.
  TextSpan _buildVerbatimSpan(String source, BlockKind kind, TextStyle marker) {
    final mono = theme.monoStyle;
    if (kind == BlockKind.indentedCode || kind == BlockKind.html) {
      return TextSpan(text: source, style: mono);
    }
    final lines = source.split('\n');
    final children = <InlineSpan>[];
    final delimiterRe = switch (kind) {
      BlockKind.fencedCode => RegExp(r'^ {0,3}(`{3,}|~{3,})'),
      BlockKind.mathBlock => RegExp(r'^\s*\$\$|\$\$\s*$'),
      _ => RegExp(r'^(---|\.\.\.)[ \t]*$'),
    };
    for (var i = 0; i < lines.length; i++) {
      final isDelimiter = (i == 0 || i == lines.length - 1) &&
          delimiterRe.hasMatch(lines[i]);
      children.add(TextSpan(
          text: lines[i], style: isDelimiter ? mono.merge(marker) : mono));
      if (i < lines.length - 1) {
        children.add(TextSpan(text: '\n', style: mono));
      }
    }
    return TextSpan(style: mono, children: children);
  }
}
