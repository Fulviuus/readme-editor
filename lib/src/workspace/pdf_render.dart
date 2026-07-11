/// Pure-Dart PDF rendering of a document, themed to a [ReadmeTheme], built
/// on package:pdf's widget tree. No native channel — works on every platform
/// and is unit-testable (unlike WebView-based HTML→PDF).
///
/// Layout mirrors the live editor: Flutter's logical px map to PDF points at
/// the CSS convention (1px = 0.75pt), block spacing follows the same
/// per-kind rules as the editor's blockPadding, and the theme's line-height
/// applies to every text run.
///
/// Text uses the bundled DejaVu family (assets/fonts/) so Unicode
/// punctuation, check marks and symbols render natively; the 14 standard
/// PDF fonts are only a fallback if the assets cannot be loaded.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../document/block.dart';
import '../document/document.dart';
import '../editor/blocks/table_model.dart';
import '../editor/inline_tokenizer.dart';
import '../theme/readme_theme.dart';

/// CSS px → PDF pt.
const _pxToPt = 0.75;

PdfColor _c(int argb) => PdfColor(
      ((argb >> 16) & 0xFF) / 255,
      ((argb >> 8) & 0xFF) / 255,
      (argb & 0xFF) / 255,
    );

PdfColor _color(dynamic flutterColor) {
  // ReadmeTheme colors are dart:ui Color; read the 0xAARRGGBB via toARGB32.
  final v = (flutterColor as dynamic).toARGB32() as int;
  return _c(v);
}

// Bundled Unicode fonts, loaded once. Null after a failed load → fall back
// to the Latin-1 standard fonts (never expected outside broken bundles).
pw.Font? _dvSans, _dvBold, _dvItalic, _dvBoldItalic, _dvMono;
bool _fontsAttempted = false;

Future<void> _ensureFonts() async {
  if (_fontsAttempted) return;
  _fontsAttempted = true;
  try {
    Future<pw.Font> load(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));
    _dvSans = await load('DejaVuSans.ttf');
    _dvBold = await load('DejaVuSans-Bold.ttf');
    _dvItalic = await load('DejaVuSans-Oblique.ttf');
    _dvBoldItalic = await load('DejaVuSans-BoldOblique.ttf');
    _dvMono = await load('DejaVuSansMono.ttf');
  } catch (_) {
    _dvSans = _dvBold = _dvItalic = _dvBoldItalic = _dvMono = null;
  }
}

/// Renders [doc] to PDF bytes styled like [theme].
Future<Uint8List> renderDocumentPdf(Document doc, ReadmeTheme theme,
    {String? title}) async {
  await _ensureFonts();
  final pdf = pw.Document(title: title);
  final fg = _color(theme.foreground);
  final r = _PdfRenderer(
    theme,
    _dvSans ?? pw.Font.helvetica(),
    _dvBold ?? pw.Font.helveticaBold(),
    _dvItalic ?? pw.Font.helveticaOblique(),
    _dvBoldItalic ?? pw.Font.helveticaBoldOblique(),
    _dvMono ?? pw.Font.courier(),
    fg,
  );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 54, vertical: 60),
      build: (context) => [
        for (final block in doc.blocks) r.block(block),
      ],
    ),
  );
  return pdf.save();
}

class _PdfRenderer {
  _PdfRenderer(this.theme, this.base, this.bold, this.italic, this.boldItalic,
      this.mono, this.fg);

  final ReadmeTheme theme;
  final pw.Font base, bold, italic, boldItalic, mono;
  final PdfColor fg;

  /// Body size in POINTS (theme px × 0.75).
  double get size => theme.fontSize * _pxToPt;

  /// Extra space between wrapped lines, from the theme's line-height.
  double get _lineSpacing => size * (theme.lineHeight - 1);

  double _headingPt(int level) =>
      theme.headingSizes[(level - 1).clamp(0, 5)] * _pxToPt;

  pw.TextStyle _bodyStyle({PdfColor? color}) => pw.TextStyle(
        font: base,
        fontSize: size,
        color: color ?? fg,
        lineSpacing: _lineSpacing,
      );

  /// Mirrors the editor's blockPadding (block_padding.dart) so the page
  /// rhythm matches the app.
  pw.EdgeInsets _blockPadding(Block b) {
    final u = size;
    return switch (b.kind) {
      BlockKind.heading => pw.EdgeInsets.only(
          top: u * (b.headingLevel <= 2 ? 0.9 : 0.7), bottom: u * 0.35),
      BlockKind.thematicBreak => pw.EdgeInsets.symmetric(vertical: u * 0.9),
      BlockKind.fencedCode ||
      BlockKind.indentedCode ||
      BlockKind.mathBlock ||
      BlockKind.table =>
        pw.EdgeInsets.symmetric(vertical: u * 0.5),
      _ => pw.EdgeInsets.symmetric(vertical: u * 0.35),
    };
  }

  pw.Widget block(Block b) =>
      pw.Padding(padding: _blockPadding(b), child: _blockBody(b));

  pw.Widget _blockBody(Block b) {
    switch (b.kind) {
      case BlockKind.heading:
        final level = b.headingLevel;
        final i = (level - 1).clamp(0, 5);
        final heavy = theme.headingWeights[i] >= 600;
        final headingColor = theme.headingColors[i];
        final text = pw.Text((b.headingText),
            style: pw.TextStyle(
              font: heavy ? bold : base,
              fontSize: _headingPt(level),
              color: headingColor == null ? fg : _color(headingColor),
              fontWeight: heavy ? pw.FontWeight.bold : pw.FontWeight.normal,
            ));
        final border = level == 1
            ? (theme.h1BorderBottom, theme.h1BorderWidth)
            : level == 2
                ? (theme.h2BorderBottom, theme.h2BorderWidth)
                : (null, 0.0);
        if (border.$1 != null && border.$2 > 0) {
          return pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.only(bottom: size * 0.3),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(
                      color: _color(border.$1), width: border.$2 * _pxToPt)),
            ),
            child: text,
          );
        }
        return text;
      case BlockKind.paragraph:
        return pw.RichText(text: _inlineSpan(b.source));
      case BlockKind.blockquote:
        final text = b.source
            .split('\n')
            .map((l) => l.replaceFirst(RegExp(r'^ {0,3}> ?'), ''))
            .join('\n');
        return pw.Container(
          padding: pw.EdgeInsets.only(
              left: size * 0.9, top: size * 0.15, bottom: size * 0.15),
          decoration: pw.BoxDecoration(
            border: pw.Border(
                left: pw.BorderSide(
                    color: _color(theme.blockquoteBorder),
                    width: theme.blockquoteBorderWidth * _pxToPt)),
          ),
          child: pw.RichText(
              text: _inlineSpan(text,
                  color: _color(theme.blockquoteTextColor))),
        );
      case BlockKind.fencedCode:
      case BlockKind.indentedCode:
        return _codeBox(b.codeBody);
      case BlockKind.mathBlock:
      case BlockKind.html:
      case BlockKind.frontMatter:
        return _codeBox(b.source);
      case BlockKind.thematicBreak:
        return pw.Container(
            height: theme.hrHeight * _pxToPt, color: _color(theme.hr));
      case BlockKind.list:
        return _list(b);
      case BlockKind.table:
        return _table(b);
    }
  }

  pw.Widget _codeBox(String code) {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.symmetric(
          horizontal: size * 0.9, vertical: size * 0.7),
      decoration: pw.BoxDecoration(
        color: theme.codeBlockBackground == null
            ? null
            : _color(theme.codeBlockBackground),
        borderRadius: pw.BorderRadius.circular(theme.codeBlockRadius),
        border: theme.codeBlockBorder == null
            ? null
            : pw.Border.all(color: _color(theme.codeBlockBorder)),
      ),
      child: pw.Text((code),
          style: pw.TextStyle(
            font: mono,
            fontSize: size * theme.codeBlockFontScale,
            color: fg,
            lineSpacing: size * 0.45,
          )),
    );
  }

  pw.Widget _bullet() => pw.Container(
        width: size * 0.28,
        height: size * 0.28,
        margin: pw.EdgeInsets.only(
            top: size * 0.42, right: size * 0.55, left: size * 0.1),
        decoration: pw.BoxDecoration(
          color: _color(theme.accent),
          shape: pw.BoxShape.circle,
        ),
      );

  pw.Widget _checkbox(bool checked) => pw.Container(
        width: size * 0.7,
        height: size * 0.7,
        margin: pw.EdgeInsets.only(top: size * 0.22, right: size * 0.45),
        decoration: pw.BoxDecoration(
          color: checked ? _color(theme.checkboxAccent) : null,
          border: pw.Border.all(
              color: _color(theme.checkboxAccent), width: 0.8),
          borderRadius: pw.BorderRadius.circular(1.5),
        ),
      );

  pw.Widget _list(Block b) {
    final rows = <pw.Widget>[];
    for (final line in b.source.split('\n')) {
      final m = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+)?')
          .firstMatch(line);
      final content = m == null ? line.trimLeft() : line.substring(m.end);
      final indentChars =
          (m?.group(1) ?? '').replaceAll('\t', '  ').length;
      final indent = (indentChars ~/ 2) * size * 1.4;
      final ordered = m != null && RegExp(r'\d').hasMatch(m.group(2)!);
      final checkbox = m?.group(3);

      pw.Widget glyph;
      if (m == null) {
        glyph = pw.SizedBox(width: size * 0.93);
      } else if (checkbox != null) {
        glyph = _checkbox(checkbox.toLowerCase().contains('x'));
      } else if (ordered) {
        glyph = pw.Padding(
          padding: pw.EdgeInsets.only(right: size * 0.4),
          child: pw.Text('${m.group(2)}',
              style: pw.TextStyle(
                  font: bold, fontSize: size, color: fg,
                  lineSpacing: _lineSpacing)),
        );
      } else {
        glyph = _bullet();
      }

      rows.add(pw.Padding(
        padding: pw.EdgeInsets.only(left: indent, top: 1, bottom: 1),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            glyph,
            pw.Expanded(child: pw.RichText(text: _inlineSpan(content))),
          ],
        ),
      ));
    }
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: rows);
  }

  pw.Widget _table(Block b) {
    final shape = TableShape(b.source);
    if (shape.lineCount < 2) return pw.Text((b.source));
    final data = <List<String>>[];
    for (var li = 0; li < shape.lineCount; li++) {
      if (li == 1) continue;
      data.add([
        for (var c = 0; c < shape.columnCount; c++)
          c < shape.cellsOnLine(li).length ? (shape.textOf(li, c)) : '',
      ]);
    }
    final border = theme.tableBorder;
    return pw.TableHelper.fromTextArray(
      headers: data.first,
      data: data.skip(1).toList(),
      border: border == null
          ? null
          : pw.TableBorder.all(color: _color(border), width: 0.75),
      cellPadding: pw.EdgeInsets.symmetric(
          horizontal: size * 0.6, vertical: size * 0.35),
      headerStyle: pw.TextStyle(font: bold, fontSize: size, color: fg),
      cellStyle: pw.TextStyle(font: base, fontSize: size, color: fg),
      headerDecoration: theme.tableHeaderBackground == null
          ? null
          : pw.BoxDecoration(color: _color(theme.tableHeaderBackground)),
    );
  }

  pw.TextSpan _inlineSpan(String source, {PdfColor? color}) {
    final children = <pw.TextSpan>[];
    _walk(tokenizeInline(source), source, _bodyStyle(color: color), children);
    return pw.TextSpan(children: children);
  }

  void _walk(List<InlineNode> nodes, String s, pw.TextStyle style,
      List<pw.TextSpan> out) {
    for (final n in nodes) {
      switch (n) {
        case TextNode():
          out.add(pw.TextSpan(
              text: (s.substring(n.start, n.end)), style: style));
        case EscapeNode():
          out.add(pw.TextSpan(
              text: (s.substring(n.start + 1, n.end)), style: style));
        case CodeNode():
          out.add(pw.TextSpan(
              text: (s.substring(n.contentStart, n.contentEnd)),
              style: style.copyWith(
                  font: mono, fontSize: size * theme.codeInlineFontScale)));
        case EmphasisNode():
          var st = style;
          if (n.isStrikethrough) {
            st = st.copyWith(decoration: pw.TextDecoration.lineThrough);
          } else {
            st = st.copyWith(
              font: n.isStrong && n.isEmphasis
                  ? boldItalic
                  : n.isStrong
                      ? bold
                      : italic,
              fontWeight:
                  n.isStrong ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontStyle:
                  n.isEmphasis ? pw.FontStyle.italic : pw.FontStyle.normal,
            );
          }
          _walk(n.children, s, st, out);
        case LinkNode():
          _walk(n.children, s, style.copyWith(color: _color(theme.link)), out);
        case ImageNode():
          out.add(pw.TextSpan(text: (n.alt), style: style));
        case AutolinkNode():
          out.add(pw.TextSpan(
              text: (n.url),
              style: style.copyWith(color: _color(theme.link))));
        case RefLinkNode():
          _walk(n.children, s, style.copyWith(color: _color(theme.link)), out);
        case FootnoteRefNode():
          out.add(pw.TextSpan(
              text: n.id, style: style.copyWith(color: _color(theme.link))));
        case HtmlTagNode():
          break; // tags dropped (underline pairs included — no glyphs)
        case CommentNode():
          break;
      }
    }
  }
}
