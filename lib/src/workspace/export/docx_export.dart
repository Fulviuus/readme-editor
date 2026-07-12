/// Native Word export: builds a minimal-but-valid OOXML package (a zip of
/// XML parts) straight from the block model — no external converter.
/// Headings, inline styles, links, ordered/unordered/task lists, code
/// blocks, quotes, tables, horizontal rules and embedded local images are
/// covered; math is emitted as literal TeX in mono.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../document/block.dart';
import '../../document/document.dart';
import '../../editor/blocks/table_model.dart';
import 'export_common.dart';

/// Reads image bytes for embedding; returns null when unavailable (web,
/// missing file, remote URL). Injected so this library stays io-free.
typedef ImageBytesResolver = List<int>? Function(String url);

Uint8List buildDocx(Document doc, {String? title, ImageBytesResolver? images}) {
  final b = _DocxBuilder(doc, images);
  return b.build(title ?? 'Untitled');
}

class _DocxBuilder {
  _DocxBuilder(this.doc, this.resolveImage)
      : linkDefs = doc.linkDefinitions,
        footnotes = doc.footnotes.numbers;

  final Document doc;
  final ImageBytesResolver? resolveImage;
  final Map<String, String> linkDefs;
  final Map<String, int> footnotes;

  final _body = StringBuffer();
  final _rels = <String>[]; // relationship XML fragments
  final _media = <String, List<int>>{}; // media/imageN.ext -> bytes
  final _extraNums = <int>[]; // numbering instances for ordered lists
  var _relId = 0;
  var _imgId = 0;

  String _nextRel() => 'rId${++_relId + 10}'; // 1..10 reserved for parts

  Uint8List build(String title) {
    for (final block in doc.blocks) {
      _block(block);
    }
    final archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes()))
      ..add(ArchiveFile.string('_rels/.rels', _packageRels()))
      ..add(ArchiveFile.string('word/document.xml', _document()))
      ..add(ArchiveFile.string('word/styles.xml', _styles()))
      ..add(ArchiveFile.string('word/numbering.xml', _numbering()))
      ..add(ArchiveFile.string(
          'word/_rels/document.xml.rels', _documentRels()));
    _media.forEach((name, bytes) {
      archive.add(ArchiveFile.bytes('word/$name', bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // ---- Blocks ----

  void _block(Block b) {
    switch (b.kind) {
      case BlockKind.heading:
        _paragraph(_headingText(b), style: 'Heading${b.headingLevel}');
      case BlockKind.paragraph:
        if (b.source.trim().isEmpty) {
          _body.write('<w:p/>');
        } else {
          _paragraph(b.source);
        }
      case BlockKind.blockquote:
        for (final line in b.source.split('\n')) {
          final content =
              line.replaceFirst(RegExp(r'^ {0,3}(?:> ?)+'), '');
          _paragraph(content, style: 'Quote');
        }
      case BlockKind.fencedCode || BlockKind.indentedCode:
        for (final line in b.codeBody.split('\n')) {
          _codeParagraph(line);
        }
      case BlockKind.mathBlock:
        _codeParagraph(b.codeBody);
      case BlockKind.list:
        _list(b);
      case BlockKind.table:
        _table(b);
      case BlockKind.thematicBreak:
        _body.write('<w:p><w:pPr><w:pBdr><w:bottom w:val="single" '
            'w:sz="6" w:space="1" w:color="auto"/></w:pBdr></w:pPr></w:p>');
      case BlockKind.html || BlockKind.frontMatter:
        for (final line in b.source.split('\n')) {
          _codeParagraph(line);
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

  void _paragraph(String source, {String? style, String? extraPPr}) {
    _body.write('<w:p>');
    if (style != null || extraPPr != null) {
      _body.write('<w:pPr>');
      if (style != null) _body.write('<w:pStyle w:val="$style"/>');
      if (extraPPr != null) _body.write(extraPPr);
      _body.write('</w:pPr>');
    }
    _runs(source);
    _body.write('</w:p>');
  }

  void _codeParagraph(String line) {
    _body
      ..write('<w:p><w:pPr><w:pStyle w:val="CodeBlock"/></w:pPr>')
      ..write(_run(InlineRun(line, code: true)))
      ..write('</w:p>');
  }

  void _runs(String source) {
    for (final r in flattenInline(source,
        linkDefinitions: linkDefs, footnoteNumbers: footnotes)) {
      if (r.imagePath != null) {
        _image(r);
        continue;
      }
      if (r.linkUrl != null) {
        final id = _nextRel();
        _rels.add('<Relationship Id="$id" Type="http://schemas.openxml'
            'formats.org/officeDocument/2006/relationships/hyperlink" '
            'Target="${escapeXml(r.linkUrl!)}" TargetMode="External"/>');
        _body
          ..write('<w:hyperlink r:id="$id">')
          ..write(_run(r, link: true))
          ..write('</w:hyperlink>');
      } else {
        _body.write(_run(r));
      }
    }
  }

  String _run(InlineRun r, {bool link = false}) {
    if (r.lineBreak) return '<w:r><w:br/></w:r>';
    final props = StringBuffer();
    if (r.bold) props.write('<w:b/>');
    if (r.italic) props.write('<w:i/>');
    if (r.strike) props.write('<w:strike/>');
    if (r.superscript) props.write('<w:vertAlign w:val="superscript"/>');
    if (r.code) {
      props.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" '
          'w:cs="Consolas"/><w:shd w:val="clear" w:color="auto" '
          'w:fill="F2F2F2"/>');
    }
    if (link) {
      props.write('<w:color w:val="0563C1"/><w:u w:val="single"/>');
    }
    final rPr = props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
    return '<w:r>$rPr<w:t xml:space="preserve">'
        '${escapeXml(r.text)}</w:t></w:r>';
  }

  // ---- Lists ----

  void _list(Block b) {
    int? orderedNum;
    for (final line in b.source.split('\n')) {
      final m = listItemRe.firstMatch(line);
      if (m == null) {
        _paragraph(line.trimLeft(), extraPPr: '<w:ind w:left="720"/>');
        continue;
      }
      final content = line.substring(m.end);
      final level =
          ((m.group(1) ?? '').replaceAll('\t', '  ').length ~/ 2).clamp(0, 8);
      final ordered = RegExp(r'^\d').hasMatch(m.group(2)!);
      final checkbox = m.group(3);
      if (checkbox != null) {
        // Task item: a checkbox glyph, indented like its level.
        final mark = checkbox.toLowerCase().contains('x') ? '☑' : '☐';
        _paragraph('$mark $content',
            extraPPr: '<w:ind w:left="${720 * (level + 1)}"/>');
        continue;
      }
      final int numId;
      if (ordered) {
        // One numbering instance per ordered list so numbering restarts.
        orderedNum ??= _newOrderedNum();
        numId = orderedNum;
      } else {
        numId = 1;
      }
      _paragraph(content,
          style: 'ListParagraph',
          extraPPr: '<w:numPr><w:ilvl w:val="$level"/>'
              '<w:numId w:val="$numId"/></w:numPr>');
    }
  }

  int _newOrderedNum() {
    final id = 100 + _extraNums.length;
    _extraNums.add(id);
    return id;
  }

  // ---- Tables ----

  void _table(Block b) {
    final shape = TableShape(b.source);
    if (shape.lineCount < 2) {
      _paragraph(b.source);
      return;
    }
    _body.write('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/></w:tblPr>');
    for (var li = 0; li < shape.lineCount; li++) {
      if (li == 1) continue; // delimiter row
      _body.write('<w:tr>');
      for (var c = 0; c < shape.columnCount; c++) {
        final text =
            c < shape.cellsOnLine(li).length ? shape.textOf(li, c) : '';
        _body.write('<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>');
        _body.write('<w:p>');
        if (li == 0) {
          _body.write(_run(InlineRun(text, bold: true)));
        } else {
          _runs(text);
        }
        _body.write('</w:p></w:tc>');
      }
      _body.write('</w:tr>');
    }
    _body.write('</w:tbl>');
  }

  // ---- Images ----

  void _image(InlineRun r) {
    final bytes = resolveImage?.call(r.imagePath!);
    final size = bytes == null ? null : _imageSize(bytes);
    if (bytes == null || size == null) {
      if ((r.imageAlt ?? '').isNotEmpty) {
        _body.write(_run(InlineRun('[${r.imageAlt}]', italic: true)));
      }
      return;
    }
    final ext = _imageExt(bytes);
    _imgId++;
    final name = 'media/image$_imgId.$ext';
    _media[name] = bytes;
    final relId = _nextRel();
    _rels.add('<Relationship Id="$relId" Type="http://schemas.openxml'
        'formats.org/officeDocument/2006/relationships/image" '
        'Target="$name"/>');
    // EMUs at 96 dpi, capped to ~6.5in content width.
    var cx = size.$1 * 9525;
    var cy = size.$2 * 9525;
    const maxCx = 5943600;
    if (cx > maxCx) {
      cy = (cy * maxCx / cx).round();
      cx = maxCx;
    }
    final alt = escapeXml(r.imageAlt ?? '');
    _body.write('<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" '
        'distR="0"><wp:extent cx="$cx" cy="$cy"/>'
        '<wp:docPr id="$_imgId" name="Image$_imgId" descr="$alt"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/'
        '2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/'
        'drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxml'
        'formats.org/drawingml/2006/picture"><pic:nvPicPr>'
        '<pic:cNvPr id="$_imgId" name="Image$_imgId"/><pic:cNvPicPr/>'
        '</pic:nvPicPr><pic:blipFill><a:blip r:embed="$relId"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr>'
        '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>'
        '</w:r>');
  }

  /// (width, height) in pixels from PNG/JPEG/GIF headers, or null.
  (int, int)? _imageSize(List<int> b) {
    if (b.length > 24 &&
        b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      int be(int o) =>
          (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      return (be(16), be(20));
    }
    if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return (b[6] | (b[7] << 8), b[8] | (b[9] << 8));
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) return null;
        final marker = b[i + 1];
        final len = (b[i + 2] << 8) | b[i + 3];
        if (marker >= 0xC0 && marker <= 0xCF &&
            marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
          return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
        }
        i += 2 + len;
      }
    }
    return null;
  }

  String _imageExt(List<int> b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
    return 'jpeg';
  }

  // ---- Package parts ----

  String _contentTypes() {
    final imageTypes = <String>{};
    for (final name in _media.keys) {
      final ext = name.split('.').last;
      imageTypes.add('<Default Extension="$ext" ContentType="image/'
          '${ext == 'jpeg' ? 'jpeg' : ext}"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxml'
        'formats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '${imageTypes.join()}'
        '<Override PartName="/word/document.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.wordprocessingml.document.main'
        '+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/numbering.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
        '</Types>';
  }

  String _packageRels() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
      '2006/relationships"><Relationship Id="rId1" Type="http://schemas.'
      'openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/></Relationships>';

  String _documentRels() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
      '2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
      '${_rels.join()}'
      '</Relationships>';

  String _document() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/'
      'wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.'
      'org/officeDocument/2006/relationships" xmlns:wp="http://schemas.'
      'openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
      '<w:body>$_body'
      '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
      '</w:sectPr></w:body></w:document>';

  String _styles() {
    String heading(int n, int halfPts) =>
        '<w:style w:type="paragraph" w:styleId="Heading$n">'
        '<w:name w:val="heading $n"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:spacing w:before="${n <= 2 ? 320 : 240}" w:after="120"/>'
        '<w:outlineLvl w:val="${n - 1}"/></w:pPr>'
        '<w:rPr><w:b/><w:sz w:val="$halfPts"/><w:szCs w:val="$halfPts"/>'
        '</w:rPr></w:style>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/><w:pPr><w:spacing w:after="160" '
        'w:line="276" w:lineRule="auto"/></w:pPr>'
        '<w:rPr><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style>'
        '${heading(1, 48)}${heading(2, 36)}${heading(3, 28)}'
        '${heading(4, 24)}${heading(5, 22)}${heading(6, 22)}'
        '<w:style w:type="paragraph" w:styleId="Quote">'
        '<w:name w:val="Quote"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:ind w:left="720"/></w:pPr>'
        '<w:rPr><w:i/><w:color w:val="595959"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="CodeBlock">'
        '<w:name w:val="Code Block"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
        '<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/></w:pPr>'
        '<w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>'
        '<w:sz w:val="20"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="ListParagraph">'
        '<w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:spacing w:after="40"/></w:pPr></w:style>'
        '<w:style w:type="table" w:styleId="TableGrid">'
        '<w:name w:val="Table Grid"/>'
        '<w:tblPr><w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="BFBFBF"/>'
        '<w:left w:val="single" w:sz="4" w:color="BFBFBF"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="BFBFBF"/>'
        '<w:right w:val="single" w:sz="4" w:color="BFBFBF"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="BFBFBF"/>'
        '<w:insideV w:val="single" w:sz="4" w:color="BFBFBF"/>'
        '</w:tblBorders></w:tblPr></w:style>'
        '</w:styles>';
  }

  String _numbering() {
    const bullets = ['•', '◦', '▪'];
    final bulletLevels = StringBuffer();
    final decimalLevels = StringBuffer();
    for (var l = 0; l < 9; l++) {
      bulletLevels.write('<w:lvl w:ilvl="$l"><w:numFmt w:val="bullet"/>'
          '<w:lvlText w:val="${bullets[l % 3]}"/>'
          '<w:pPr><w:ind w:left="${720 * (l + 1)}" w:hanging="360"/></w:pPr>'
          '</w:lvl>');
      decimalLevels.write('<w:lvl w:ilvl="$l"><w:start w:val="1"/>'
          '<w:numFmt w:val="decimal"/><w:lvlText w:val="%${l + 1}."/>'
          '<w:pPr><w:ind w:left="${720 * (l + 1)}" w:hanging="360"/></w:pPr>'
          '</w:lvl>');
    }
    final orderedNums = StringBuffer();
    for (final id in _extraNums) {
      orderedNums.write('<w:num w:numId="$id">'
          '<w:abstractNumId w:val="2"/></w:num>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:numbering xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main">'
        '<w:abstractNum w:abstractNumId="1">$bulletLevels</w:abstractNum>'
        '<w:abstractNum w:abstractNumId="2">$decimalLevels</w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>'
        '$orderedNums'
        '</w:numbering>';
  }
}

