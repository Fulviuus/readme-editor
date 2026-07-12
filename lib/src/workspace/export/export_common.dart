/// Shared inline flattening for the native exporters (docx/rtf/latex):
/// the tokenizer's nested nodes become a flat run list each format can
/// serialize without knowing markdown.
library;

import '../../editor/inline_tokenizer.dart';

class InlineRun {
  const InlineRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.math = false,
    this.superscript = false,
    this.linkUrl,
    this.imagePath,
    this.imageAlt,
    this.lineBreak = false,
  });

  final String text;
  final bool bold, italic, strike, code, math, superscript;
  final String? linkUrl;

  /// Set for image runs ([text] is empty then).
  final String? imagePath;
  final String? imageAlt;

  /// A hard line break within the block.
  final bool lineBreak;
}

final _brRe = RegExp(r'^<br\s*/?>$', caseSensitive: false);

/// Flattens [source]'s inline markdown into styled runs. [linkDefinitions]
/// resolves `[text][ref]` links; [footnoteNumbers] numbers `[^id]` marks.
List<InlineRun> flattenInline(
  String source, {
  Map<String, String> linkDefinitions = const {},
  Map<String, int> footnoteNumbers = const {},
}) {
  final out = <InlineRun>[];

  void walk(List<InlineNode> nodes, String s,
      {bool bold = false,
      bool italic = false,
      bool strike = false,
      String? link}) {
    for (final n in nodes) {
      switch (n) {
        case TextNode():
          out.add(InlineRun(s.substring(n.start, n.end),
              bold: bold, italic: italic, strike: strike, linkUrl: link));
        case EscapeNode():
          out.add(InlineRun(s.substring(n.start + 1, n.end),
              bold: bold, italic: italic, strike: strike, linkUrl: link));
        case CodeNode():
          out.add(InlineRun(s.substring(n.contentStart, n.contentEnd),
              code: true, linkUrl: link));
        case MathNode():
          out.add(InlineRun(s.substring(n.contentStart, n.contentEnd),
              math: true, code: true));
        case EmphasisNode():
          walk(n.children, s,
              bold: bold || n.isStrong,
              italic: italic || n.isEmphasis,
              strike: strike || n.isStrikethrough,
              link: link);
        case LinkNode():
          walk(n.children, s,
              bold: bold, italic: italic, strike: strike, link: n.url);
        case RefLinkNode():
          final url = linkDefinitions[n.reference];
          if (url == null) {
            out.add(InlineRun(s.substring(n.start, n.end),
                bold: bold, italic: italic, strike: strike));
          } else {
            walk(n.children, s,
                bold: bold, italic: italic, strike: strike, link: url);
          }
        case AutolinkNode():
          out.add(InlineRun(n.url, linkUrl: n.url));
        case ImageNode():
          out.add(InlineRun('', imagePath: n.url, imageAlt: n.alt));
        case FootnoteRefNode():
          out.add(InlineRun(
              (footnoteNumbers[n.id] ?? n.id).toString(),
              superscript: true));
        case HtmlTagNode():
          final tag = s.substring(n.start, n.end);
          if (_brRe.hasMatch(tag)) {
            out.add(const InlineRun('', lineBreak: true));
          }
          // Other tags (incl. <u> pairs) are dropped in exports.
        case CommentNode():
          break;
      }
    }
  }

  walk(tokenizeInline(source), source);
  return out.where((r) => r.text.isNotEmpty || r.lineBreak || r.imagePath != null).toList();
}

/// Matches one list-item line: indent, marker, optional task box.
final listItemRe =
    RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+)?');

/// XML/HTML text escaping used by the zip-based exporters.
String escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
