/// Inline markdown tokenizer with SOURCE OFFSETS.
///
/// package:markdown's AST carries no source positions, and the hybrid editor
/// lives or dies on offset fidelity (caret transfer, marker dimming), so
/// inline parsing is done here. Both the rendered view (markers hidden) and
/// the focused editing view (markers dimmed) consume the same node list.
///
/// Deliberately simpler than CommonMark's delimiter-stack emphasis algorithm;
/// the degradation mode for pathological nesting is "shown as literal text",
/// which is acceptable for an editor (the source is never mangled).
library;

sealed class InlineNode {
  InlineNode(this.start, this.end);

  /// Source offsets (relative to the tokenized string).
  final int start;
  final int end;
}

class TextNode extends InlineNode {
  TextNode(super.start, super.end);
}

/// `\*` — backslash + one punctuation char.
class EscapeNode extends InlineNode {
  EscapeNode(super.start, super.end);
}

/// `` `code` `` — [contentStart]/[contentEnd] exclude the backtick runs.
class CodeNode extends InlineNode {
  CodeNode(super.start, super.end, this.contentStart, this.contentEnd);
  final int contentStart;
  final int contentEnd;
}

/// `*em*`, `**strong**`, `***both***`, `~~strike~~`.
class EmphasisNode extends InlineNode {
  EmphasisNode(super.start, super.end, this.delimiterLength, this.marker,
      this.children);
  final int delimiterLength; // 1, 2 or 3 (3 = strong + em)
  final String marker; // '*', '_' or '~'
  final List<InlineNode> children;

  bool get isStrong => delimiterLength >= 2;
  bool get isEmphasis => delimiterLength == 1 || delimiterLength == 3;
  bool get isStrikethrough => marker == '~';
}

/// `[label](url "title")`
class LinkNode extends InlineNode {
  LinkNode(super.start, super.end, this.labelStart, this.labelEnd,
      this.urlStart, this.urlEnd, this.url, this.children);
  final int labelStart, labelEnd;
  final int urlStart, urlEnd;
  final String url; // without title
  final List<InlineNode> children;
}

/// `![alt](url)`
class ImageNode extends InlineNode {
  ImageNode(super.start, super.end, this.alt, this.url);
  final String alt;
  final String url;
}

/// `<https://…>` or a bare `https://…` URL.
class AutolinkNode extends InlineNode {
  AutolinkNode(super.start, super.end, this.url, {required this.bracketed});
  final String url;
  final bool bracketed;

  int get contentStart => bracketed ? start + 1 : start;
  int get contentEnd => bracketed ? end - 1 : end;
}

/// An inline HTML tag like `<br>` or `<span class=…>` — rendered dimmed.
class HtmlTagNode extends InlineNode {
  HtmlTagNode(super.start, super.end);
}

/// `<!-- … -->` — hidden entirely in rendered mode, dimmed while editing.
class CommentNode extends InlineNode {
  CommentNode(super.start, super.end);
}

final _punct = RegExp(r'''[!-/:-@\[-`{-~]''');

/// Cap on how far a single delimiter (link bracket, emphasis run) scans for
/// its closer. Bounds the tokenizer to O(n·window) on adversarial input
/// (chains of unmatched `[` or `*`) — beyond this a construct just renders
/// literally, which is the tokenizer's degradation mode anyway.
const _scanWindow = 4096;
final _htmlTagRe = RegExp(r'''^</?[a-zA-Z][a-zA-Z0-9-]*(\s[^<>]*)?/?>''');
final _bracketAutolinkRe =
    RegExp(r'^<([a-zA-Z][a-zA-Z0-9+.\-]*:[^ <>]+|[^ <>@]+@[^ <>]+\.[^ <>]+)>');
final _bareUrlRe = RegExp(r'^https?://[^\s<>]+');
bool _isAlnum(String c) => RegExp(r'[a-zA-Z0-9]').hasMatch(c);

List<InlineNode> tokenizeInline(String s) => _parse(s, 0, s.length);

/// The rendered plain text of [s] with all inline syntax stripped: markers
/// gone, code/link labels kept, image alt kept, HTML tags dropped.
/// Used by Clear Format and copy-as-plain-text.
String plainTextOfInline(String s) {
  final buf = StringBuffer();
  void walk(List<InlineNode> nodes) {
    for (final n in nodes) {
      switch (n) {
        case TextNode():
          buf.write(s.substring(n.start, n.end));
        case EscapeNode():
          buf.write(s.substring(n.start + 1, n.end));
        case CodeNode():
          buf.write(s.substring(n.contentStart, n.contentEnd));
        case EmphasisNode():
          walk(n.children);
        case LinkNode():
          walk(n.children);
        case ImageNode():
          buf.write(n.alt);
        case AutolinkNode():
          buf.write(n.url);
        case HtmlTagNode():
          break;
        case CommentNode():
          break;
      }
    }
  }

  walk(tokenizeInline(s));
  return buf.toString();
}

List<InlineNode> _parse(String s, int from, int to) {
  final nodes = <InlineNode>[];
  var i = from;
  var textStart = from;

  void flushText(int upTo) {
    if (upTo > textStart) nodes.add(TextNode(textStart, upTo));
  }

  int runLen(int at, String ch) {
    var n = 0;
    while (at + n < to && s[at + n] == ch) {
      n++;
    }
    return n;
  }

  while (i < to) {
    final c = s[i];

    // Backslash escape.
    if (c == r'\' && i + 1 < to && _punct.hasMatch(s[i + 1])) {
      flushText(i);
      nodes.add(EscapeNode(i, i + 2));
      i += 2;
      textStart = i;
      continue;
    }

    // Code span: run of N backticks closed by a run of exactly N.
    if (c == '`') {
      final n = runLen(i, '`');
      final close = _findBacktickClose(s, i + n, to, n);
      if (close >= 0) {
        flushText(i);
        nodes.add(CodeNode(i, close + n, i + n, close));
        i = close + n;
        textStart = i;
        continue;
      }
      i += n;
      continue;
    }

    // Image.
    if (c == '!' && i + 1 < to && s[i + 1] == '[') {
      final link = _tryParseLink(s, i + 1, to);
      if (link != null) {
        flushText(i);
        nodes.add(ImageNode(i, link.end,
            s.substring(link.labelStart, link.labelEnd), link.url));
        i = link.end;
        textStart = i;
        continue;
      }
    }

    // Link.
    if (c == '[') {
      final link = _tryParseLink(s, i, to);
      if (link != null) {
        flushText(i);
        nodes.add(LinkNode(i, link.end, link.labelStart, link.labelEnd,
            link.urlStart, link.urlEnd, link.url,
            _parse(s, link.labelStart, link.labelEnd)));
        i = link.end;
        textStart = i;
        continue;
      }
    }

    // Emphasis / strong / strikethrough.
    if (c == '*' || c == '_' || c == '~') {
      final l = runLen(i, c);
      final maxD = c == '~' ? (l >= 2 ? 2 : 0) : (l > 3 ? 3 : l);
      var matched = false;
      for (var d = maxD; d >= (c == '~' ? 2 : 1); d--) {
        // Opener: must be followed by non-space; `_` must not be intraword.
        final after = i + l;
        if (after >= to || s[after] == ' ') break;
        if (c == '_' && i > from && _isAlnum(s[i - 1])) break;
        final closeAt = _findEmphasisClose(s, i + d, to, c, d, from);
        if (closeAt >= 0) {
          flushText(i);
          nodes.add(EmphasisNode(
              i, closeAt + d, d, c, _parse(s, i + d, closeAt)));
          i = closeAt + d;
          textStart = i;
          matched = true;
          break;
        }
      }
      if (matched) continue;
      i += l;
      continue;
    }

    // Bracketed autolink, HTML comment, or inline HTML tag.
    if (c == '<') {
      if (s.startsWith('<!--', i)) {
        final close = s.indexOf('-->', i + 4);
        if (close >= 0 && close + 3 <= to && close - i < _scanWindow) {
          flushText(i);
          nodes.add(CommentNode(i, close + 3));
          i = close + 3;
          textStart = i;
          continue;
        }
      }
      final rest = s.substring(i, to);
      final auto = _bracketAutolinkRe.firstMatch(rest);
      if (auto != null) {
        flushText(i);
        nodes.add(AutolinkNode(i, i + auto.end, auto.group(1)!,
            bracketed: true));
        i += auto.end;
        textStart = i;
        continue;
      }
      final tag = _htmlTagRe.firstMatch(rest);
      if (tag != null) {
        flushText(i);
        nodes.add(HtmlTagNode(i, i + tag.end));
        i += tag.end;
        textStart = i;
        continue;
      }
    }

    // Bare URL (GFM-style autolink) at a word boundary. `http://` with
    // nothing after the slashes is not a URL — stays literal text.
    if (c == 'h' &&
        (i == from || !_isAlnum(s[i - 1])) &&
        (s.startsWith('http://', i) || s.startsWith('https://', i))) {
      final m = _bareUrlRe.firstMatch(s.substring(i, to));
      if (m == null) {
        i += 7;
        continue;
      }
      var end = i + m.end;
      // Trailing punctuation is not part of the URL.
      while (end > i && ')].,;:!?\'"'.contains(s[end - 1])) {
        end--;
      }
      flushText(i);
      nodes.add(AutolinkNode(i, end, s.substring(i, end), bracketed: false));
      i = end;
      textStart = i;
      continue;
    }

    i++;
  }

  flushText(to);
  return nodes;
}

/// Finds a closing run of exactly [n] backticks; returns its start or -1.
int _findBacktickClose(String s, int from, int to, int n) {
  var j = from;
  while (j < to) {
    if (s[j] == '`') {
      var k = 0;
      while (j + k < to && s[j + k] == '`') {
        k++;
      }
      if (k == n) return j;
      j += k;
    } else {
      j++;
    }
  }
  return -1;
}

/// Finds a closing delimiter run (>= [d] chars of [m]) whose preceding char
/// is not a space, skipping over code spans. Returns its start or -1.
int _findEmphasisClose(String s, int from, int to, String m, int d, int parseFrom) {
  if (to - from > _scanWindow) to = from + _scanWindow;
  var j = from;
  while (j < to) {
    final c = s[j];
    if (c == r'\' && j + 1 < to && _punct.hasMatch(s[j + 1])) {
      j += 2;
      continue;
    }
    if (c == '`') {
      var n = 0;
      while (j + n < to && s[j + n] == '`') {
        n++;
      }
      final close = _findBacktickClose(s, j + n, to, n);
      j = close >= 0 ? close + n : j + n;
      continue;
    }
    if (c == m) {
      var n = 0;
      while (j + n < to && s[j + n] == m) {
        n++;
      }
      final validCloser = n >= d &&
          j > parseFrom &&
          s[j - 1] != ' ' &&
          (m != '_' || j + n >= to || !_isAlnum(s[j + n]));
      if (validCloser) return j;
      j += n;
      continue;
    }
    j++;
  }
  return -1;
}

class _ParsedLink {
  _ParsedLink(this.end, this.labelStart, this.labelEnd, this.urlStart,
      this.urlEnd, this.url);
  final int end;
  final int labelStart, labelEnd;
  final int urlStart, urlEnd;
  final String url;
}

/// Parses `[label](url "title")` starting at `[`; returns null if malformed.
_ParsedLink? _tryParseLink(String s, int at, int to) {
  if (to - at > _scanWindow) to = at + _scanWindow;
  var depth = 0;
  var j = at;
  var closeBracket = -1;
  while (j < to) {
    final c = s[j];
    if (c == r'\') {
      j += 2;
      continue;
    }
    if (c == '[') depth++;
    if (c == ']') {
      depth--;
      if (depth == 0) {
        closeBracket = j;
        break;
      }
    }
    j++;
  }
  if (closeBracket < 0 || closeBracket + 1 >= to || s[closeBracket + 1] != '(') {
    return null;
  }
  var parenDepth = 1;
  var k = closeBracket + 2;
  while (k < to) {
    final c = s[k];
    if (c == r'\') {
      k += 2;
      continue;
    }
    if (c == '(') parenDepth++;
    if (c == ')') {
      parenDepth--;
      if (parenDepth == 0) break;
    }
    k++;
  }
  if (k >= to) return null;
  final urlStart = closeBracket + 2;
  final urlEnd = k;
  var url = s.substring(urlStart, urlEnd).trim();
  // Strip an optional quoted title.
  final title = RegExp(r'''\s+("[^"]*"|'[^']*')$''').firstMatch(url);
  if (title != null) url = url.substring(0, title.start).trim();
  if (url.startsWith('<') && url.endsWith('>')) {
    url = url.substring(1, url.length - 1);
  }
  return _ParsedLink(k + 1, at + 1, closeBracket, urlStart, urlEnd, url);
}
