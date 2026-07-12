/// Standalone HTML export: the body comes from package:markdown
/// (GitHub-flavored), wrapped in a single self-contained document whose
/// embedded CSS mirrors a [ReadmeTheme] — page colors, fonts, headings
/// (including h1/h2 borders), code, blockquotes, links, tables, task
/// checkboxes and the content column width.
library;

import 'dart:ui' show Color, TextAlign;

import 'package:file_selector/file_selector.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/readme_theme.dart';
import 'file_io.dart';

/// Renders [markdownSource] to a complete standalone HTML document styled
/// like [theme]. [title] fills the `<title>` element (default "Untitled").
String exportHtml(String markdownSource, ReadmeTheme theme, {String? title}) {
  final body = md.markdownToHtml(
    markdownSource,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  return '<!DOCTYPE html>\n'
      '<html lang="en">\n'
      '<head>\n'
      '<meta charset="utf-8">\n'
      '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
      '<title>${_escapeHtml(title ?? 'Untitled')}</title>\n'
      '<style>\n'
      '${_themeCss(theme)}'
      '</style>\n'
      '</head>\n'
      '<body>\n'
      '<article class="markdown-body">\n'
      '$body'
      '</article>\n'
      '</body>\n'
      '</html>\n';
}

/// Prompts for an .html save location and writes the export. Returns false
/// when cancelled or on platforms without a save dialog (web).
Future<bool> exportHtmlDialog(
  String markdownSource,
  ReadmeTheme theme, {
  String? title,
  String? suggestedName,
}) async {
  if (!supportsFileSystem) return false;
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'HTML', extensions: <String>['html', 'htm']),
    ],
    suggestedName: suggestedName ?? 'Untitled.html',
  );
  if (location == null) return false;
  var path = location.path;
  final lower = path.toLowerCase();
  if (!lower.endsWith('.html') && !lower.endsWith('.htm')) {
    path = '$path.html';
  }
  await writeTextFile(path, exportHtml(markdownSource, theme, title: title));
  return true;
}

// ---- Theme -> CSS ----

/// The theme stylesheet, shared with the EPUB exporter.
String themeCssFor(ReadmeTheme t) => _themeCss(t);

String _themeCss(ReadmeTheme t) {
  final buf = StringBuffer();

  void rule(String selector, List<String> declarations) {
    if (declarations.isEmpty) return;
    buf.writeln('$selector {');
    for (final declaration in declarations) {
      buf.writeln('  $declaration;');
    }
    buf.writeln('}');
  }

  final bodyFamily = _cssFontFamily(t.fontFamily);
  final monoFamily = _cssFontFamily(t.monoFontFamily);
  final headingFamily = _cssFontFamily(t.headingFontFamily ?? t.fontFamily);

  rule('*', ['box-sizing: border-box']);
  rule('body', [
    'margin: 0',
    'background: ${_css(t.background)}',
    'color: ${_css(t.foreground)}',
    'font-family: $bodyFamily',
    'font-size: ${_px(t.fontSize)}',
    'font-weight: ${t.fontWeight}',
    'line-height: ${_n(t.lineHeight)}',
  ]);
  rule('.markdown-body', [
    'max-width: ${_px(t.contentMaxWidth)}',
    'margin: 0 auto',
    'padding: 3rem 2rem 6rem',
  ]);
  rule('::selection', [
    'background: ${_css(t.selectionBackground)}',
    if (t.selectionForeground != null)
      'color: ${_css(t.selectionForeground!)}',
  ]);
  rule('img', ['max-width: 100%']);

  // Headings h1-h6, including the optional h1/h2 bottom borders.
  for (var i = 0; i < 6; i++) {
    final color = t.headingColors[i];
    final align = t.headingAligns[i];
    rule('h${i + 1}', [
      'font-family: $headingFamily',
      'font-size: ${_px(t.headingSizes[i])}',
      'font-weight: ${t.headingWeights[i]}',
      'line-height: 1.25',
      'margin: 1.4em 0 0.6em',
      if (color != null) 'color: ${_css(color)}',
      if (t.headingItalics[i]) 'font-style: italic',
      if (align != TextAlign.left)
        'text-align: ${align == TextAlign.center ? 'center' : 'right'}',
    ]);
  }
  if (t.h1BorderBottom != null && t.h1BorderWidth > 0) {
    rule('h1', [
      'border-bottom: ${_px(t.h1BorderWidth)} solid ${_css(t.h1BorderBottom!)}',
      'padding-bottom: 0.3em',
    ]);
  }
  if (t.h2BorderBottom != null && t.h2BorderWidth > 0) {
    rule('h2', [
      'border-bottom: ${_px(t.h2BorderWidth)} solid ${_css(t.h2BorderBottom!)}',
      'padding-bottom: 0.3em',
    ]);
  }

  // Inline code, then code blocks (pre code resets the inline styling).
  rule('code', [
    'font-family: $monoFamily',
    'font-size: ${_n(t.codeInlineFontScale * 100)}%',
    'padding: 0.15em 0.4em',
    'border-radius: ${_px(t.codeInlineRadius)}',
    if (t.codeInlineForeground != null)
      'color: ${_css(t.codeInlineForeground!)}',
    if (t.codeInlineBackground != null)
      'background: ${_css(t.codeInlineBackground!)}',
    if (t.codeInlineBorder != null)
      'border: 1px solid ${_css(t.codeInlineBorder!)}',
  ]);
  rule('pre', [
    'padding: 0.8em 1em',
    'overflow-x: auto',
    'line-height: 1.45',
    'border-radius: ${_px(t.codeBlockRadius)}',
    if (t.codeBlockBackground != null)
      'background: ${_css(t.codeBlockBackground!)}',
    if (t.codeBlockForeground != null)
      'color: ${_css(t.codeBlockForeground!)}',
    if (t.codeBlockBorder != null)
      'border: 1px solid ${_css(t.codeBlockBorder!)}',
  ]);
  rule('pre code', [
    'font-size: ${_n(t.codeBlockFontScale * 100)}%',
    'color: inherit',
    'background: none',
    'border: none',
    'padding: 0',
    'border-radius: 0',
  ]);

  rule('blockquote', [
    'margin: 1em 0',
    'padding: 0 1em',
    'border-left: ${_px(t.blockquoteBorderWidth)} solid '
        '${_css(t.blockquoteBorder)}',
    if (t.blockquoteForeground != null)
      'color: ${_css(t.blockquoteForeground!)}',
    if (t.blockquoteBackground != null)
      'background: ${_css(t.blockquoteBackground!)}',
    if (t.blockquoteItalic) 'font-style: italic',
  ]);

  rule('a', [
    'color: ${_css(t.link)}',
    'text-decoration: '
        '${t.linkUnderline == LinkUnderline.always ? 'underline' : 'none'}',
  ]);
  rule('a:hover', [
    'color: ${_css(t.linkHover)}',
    if (t.linkUnderline != LinkUnderline.none) 'text-decoration: underline',
  ]);

  rule('hr', [
    'border: none',
    'height: ${_px(t.hrHeight)}',
    'background: ${_css(t.hr)}',
    'margin: 1.5em 0',
  ]);

  rule('table', ['border-collapse: collapse', 'margin: 1em 0']);
  rule('th, td', [
    'padding: 6px 13px',
    if (t.tableBorder != null) 'border: 1px solid ${_css(t.tableBorder!)}',
  ]);
  rule('th', [
    'font-weight: 600',
    if (t.tableHeaderBackground != null)
      'background: ${_css(t.tableHeaderBackground!)}',
  ]);
  if (t.tableStripeBackground != null) {
    rule('tbody tr:nth-child(2n)', [
      'background: ${_css(t.tableStripeBackground!)}',
    ]);
  }

  // GFM task lists (package:markdown emits class="task-list-item").
  rule('input[type="checkbox"]', [
    'accent-color: ${_css(t.checkboxAccent)}',
    'vertical-align: middle',
  ]);
  rule('li.task-list-item', ['list-style-type: none']);
  rule('li.task-list-item input[type="checkbox"]', [
    'margin: 0 0.35em 0.25em -1.4em',
  ]);

  return buf.toString();
}

/// CSS color: `#RRGGBB`, or `rgba(...)` when the color has translucency.
/// [Color.r]/[Color.g]/[Color.b]/[Color.a] are doubles in 0..1.
String _css(Color color) {
  int channel(double v) => (v * 255.0).round().clamp(0, 255).toInt();
  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  final a = channel(color.a);
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  if (a >= 255) return '#${hex(r)}${hex(g)}${hex(b)}';
  return 'rgba($r, $g, $b, ${_n((color.a * 1000).roundToDouble() / 1000)})';
}

/// Number without a trailing `.0` (and at most 3 decimals).
String _n(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  var s = v.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String _px(double v) => '${_n(v)}px';

final _cssIdentifier = RegExp(r'^-?[A-Za-z_][A-Za-z0-9_-]*$');

/// Font stack -> CSS `font-family` value; names that are not plain CSS
/// identifiers (spaces, digits first, ...) get quoted.
String _cssFontFamily(List<String> fonts) {
  final parts = [
    for (final font in fonts)
      if (font.trim().isNotEmpty)
        _cssIdentifier.hasMatch(font.trim())
            ? font.trim()
            : '"${font.trim().replaceAll('"', r'\"')}"',
  ];
  return parts.isEmpty ? 'sans-serif' : parts.join(', ');
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
