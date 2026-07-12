/// Native RTF export: plain-text markup, no container. Covers headings,
/// inline styles, links (as colored underlined text with the URL field),
/// lists, quotes, code blocks, simple tables and horizontal rules.
library;

import '../../document/block.dart';
import '../../document/document.dart';
import '../../editor/blocks/table_model.dart';
import 'export_common.dart';

String buildRtf(Document doc) {
  final b = _RtfBuilder(doc);
  return b.build();
}

class _RtfBuilder {
  _RtfBuilder(this.doc)
      : linkDefs = doc.linkDefinitions,
        footnotes = doc.footnotes.numbers;

  final Document doc;
  final Map<String, String> linkDefs;
  final Map<String, int> footnotes;
  final _out = StringBuffer();

  String build() {
    _out.write(r'{\rtf1\ansi\deff0'
        r'{\fonttbl{\f0\fswiss Helvetica;}{\f1\fmodern Courier New;}}'
        r'{\colortbl;\red5\green99\blue193;\red89\green89\blue89;}'
        '\n');
    for (final block in doc.blocks) {
      _block(block);
    }
    _out.write('}');
    return _out.toString();
  }

  // Heading sizes in half-points.
  static const _headingSizes = [48, 36, 28, 24, 22, 22];

  void _block(Block b) {
    switch (b.kind) {
      case BlockKind.heading:
        final level = b.headingLevel.clamp(1, 6);
        _out.write('{\\pard\\sb240\\sa120\\b\\fs'
            '${_headingSizes[level - 1]} ');
        _inline(_headingText(b));
        _out.write('\\par}\n');
      case BlockKind.paragraph:
        _out.write(r'{\pard\sa160\fs22 ');
        _inline(b.source);
        _out.write(r'\par}' '\n');
      case BlockKind.blockquote:
        for (final line in b.source.split('\n')) {
          final content =
              line.replaceFirst(RegExp(r'^ {0,3}(?:> ?)+'), '');
          _out.write(r'{\pard\li720\sa60\i\cf2\fs22 ');
          _inline(content);
          _out.write(r'\par}' '\n');
        }
      case BlockKind.fencedCode ||
            BlockKind.indentedCode ||
            BlockKind.mathBlock:
        for (final line in b.codeBody.split('\n')) {
          _out
            ..write(r'{\pard\f1\fs20 ')
            ..write(_escape(line))
            ..write(r'\par}' '\n');
        }
      case BlockKind.list:
        _list(b);
      case BlockKind.table:
        _table(b);
      case BlockKind.thematicBreak:
        _out.write(r'{\pard\brdrb\brdrs\brdrw10\sa160\par}' '\n');
      case BlockKind.html || BlockKind.frontMatter:
        for (final line in b.source.split('\n')) {
          _out
            ..write(r'{\pard\f1\fs20 ')
            ..write(_escape(line))
            ..write(r'\par}' '\n');
        }
    }
  }

  String _headingText(Block b) {
    if (b.isSetextHeading) {
      final lines = b.source.split('\n');
      return lines.sublist(0, lines.length - 1).join(' ');
    }
    return b.source
        .replaceFirst(RegExp(r'^ {0,3}#{1,6}[ \t]*'), '')
        .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '');
  }

  void _list(Block b) {
    var ordinal = 0;
    for (final line in b.source.split('\n')) {
      final m = listItemRe.firstMatch(line);
      if (m == null) {
        _out.write(r'{\pard\li720\sa40\fs22 ');
        _inline(line.trimLeft());
        _out.write(r'\par}' '\n');
        continue;
      }
      final content = line.substring(m.end);
      final level =
          ((m.group(1) ?? '').replaceAll('\t', '  ').length ~/ 2) + 1;
      final ordered = RegExp(r'^\d').hasMatch(m.group(2)!);
      final checkbox = m.group(3);
      final String glyph;
      if (checkbox != null) {
        glyph = checkbox.toLowerCase().contains('x') ? '☑' : '☐';
      } else if (ordered) {
        ordinal++;
        glyph = '$ordinal.';
      } else {
        glyph = '•';
      }
      _out.write('{\\pard\\li${720 * level}\\sa40\\fs22 '
          '${_escape(glyph)}\\tab ');
      _inline(content);
      _out.write(r'\par}' '\n');
    }
  }

  void _table(Block b) {
    final shape = TableShape(b.source);
    if (shape.lineCount < 2) return;
    const width = 2400;
    for (var li = 0; li < shape.lineCount; li++) {
      if (li == 1) continue;
      _out.write(r'\trowd');
      for (var c = 0; c < shape.columnCount; c++) {
        _out.write('\\clbrdrt\\brdrs\\clbrdrb\\brdrs\\clbrdrl\\brdrs'
            '\\clbrdrr\\brdrs\\cellx${width * (c + 1)}');
      }
      for (var c = 0; c < shape.columnCount; c++) {
        final text =
            c < shape.cellsOnLine(li).length ? shape.textOf(li, c) : '';
        _out.write(r'\pard\intbl\fs22 ');
        if (li == 0) _out.write(r'\b ');
        _inline(text);
        _out.write(r'\cell ');
      }
      _out.write(r'\row' '\n');
    }
    _out.write(r'{\pard\sa160\par}' '\n');
  }

  void _inline(String source) {
    for (final r in flattenInline(source,
        linkDefinitions: linkDefs, footnoteNumbers: footnotes)) {
      if (r.lineBreak) {
        _out.write(r'\line ');
        continue;
      }
      if (r.imagePath != null) {
        if ((r.imageAlt ?? '').isNotEmpty) {
          _out.write('{\\i ${_escape('[${r.imageAlt}]')}}');
        }
        continue;
      }
      final open = StringBuffer('{');
      if (r.bold) open.write(r'\b ');
      if (r.italic) open.write(r'\i ');
      if (r.strike) open.write(r'\strike ');
      if (r.superscript) open.write(r'\super ');
      if (r.code || r.math) open.write(r'\f1 ');
      if (r.linkUrl != null) open.write(r'\cf1\ul ');
      _out
        ..write(open)
        ..write(_escape(r.text))
        ..write('}');
    }
  }

  String _escape(String s) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      if (rune == 0x5C) {
        out.write(r'\\');
      } else if (rune == 0x7B) {
        out.write(r'\{');
      } else if (rune == 0x7D) {
        out.write(r'\}');
      } else if (rune < 0x80) {
        out.writeCharCode(rune);
      } else {
        // RTF unicode escape: signed 16-bit value + one-byte fallback.
        final v = rune > 0xFFFF ? 0x3F : rune;
        out.write('\\u${v > 0x7FFF ? v - 0x10000 : v}?');
      }
    }
    return out.toString();
  }
}
