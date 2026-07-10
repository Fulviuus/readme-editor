/// Theme data model, mirroring the "readme theme JSON schema v1"
/// (docs/DESIGN-themes.md). Built-in themes ship as JSON assets; user themes
/// are the same format dropped into the app's themes folder.
library;

import 'package:flutter/material.dart';

enum LinkUnderline { none, hover, always }

/// Syntax token slots a theme may color. When [ReadmeTheme.syntaxPreset] is
/// set these are ignored in favour of the named highlight.js preset.
enum SyntaxToken {
  comment,
  keyword,
  string,
  number,
  function,
  variable,
  tag,
  attribute,
  atom,
  builtin,
  meta,
  bracket,
  link,
  quote,
}

class ReadmeTheme {
  const ReadmeTheme({
    required this.id,
    required this.name,
    required this.dark,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.caret,
    required this.selectionBackground,
    this.selectionForeground,
    required this.fontFamily,
    required this.monoFontFamily,
    this.headingFontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.lineHeight,
    required this.contentMaxWidth,
    required this.headingSizes,
    required this.headingWeights,
    required this.headingColors,
    required this.headingItalics,
    required this.headingAligns,
    this.h1BorderBottom,
    this.h1BorderWidth = 0,
    this.h2BorderBottom,
    this.h2BorderWidth = 0,
    this.codeInlineForeground,
    this.codeInlineBackground,
    this.codeInlineBorder,
    this.codeInlineRadius = 3,
    this.codeInlineFontScale = 0.9,
    this.codeBlockBackground,
    this.codeBlockForeground,
    this.codeBlockBorder,
    this.codeBlockRadius = 3,
    this.codeBlockFontScale = 0.9,
    this.syntaxPreset,
    this.syntaxTokens = const {},
    this.blockquoteForeground,
    required this.blockquoteBorder,
    this.blockquoteBorderWidth = 4,
    this.blockquoteBackground,
    this.blockquoteItalic = false,
    required this.link,
    required this.linkHover,
    this.linkUnderline = LinkUnderline.hover,
    required this.hr,
    this.hrHeight = 1,
    this.tableBorder,
    this.tableHeaderBackground,
    this.tableStripeBackground,
    required this.checkboxAccent,
    this.checkboxBorder,
    required this.sidebarBackground,
    required this.sidebarForeground,
    required this.sidebarActiveBackground,
    this.sidebarActiveForeground,
  });

  final String id;
  final String name;
  final bool dark;

  final Color background;
  final Color foreground;
  final Color accent;
  final Color caret;
  final Color selectionBackground;
  final Color? selectionForeground;

  final List<String> fontFamily;
  final List<String> monoFontFamily;
  final List<String>? headingFontFamily;
  final double fontSize;
  final int fontWeight;
  final double lineHeight;
  final double contentMaxWidth;

  final List<double> headingSizes; // h1..h6
  final List<int> headingWeights;
  final List<Color?> headingColors;
  final List<bool> headingItalics;
  final List<TextAlign> headingAligns;
  final Color? h1BorderBottom;
  final double h1BorderWidth;
  final Color? h2BorderBottom;
  final double h2BorderWidth;

  final Color? codeInlineForeground;
  final Color? codeInlineBackground;
  final Color? codeInlineBorder;
  final double codeInlineRadius;
  final double codeInlineFontScale;

  final Color? codeBlockBackground;
  final Color? codeBlockForeground;
  final Color? codeBlockBorder;
  final double codeBlockRadius;
  final double codeBlockFontScale;

  /// Named highlight.js preset ("highlightjs-github",
  /// "highlightjs-atom-one-dark") or null to use [syntaxTokens].
  final String? syntaxPreset;
  final Map<SyntaxToken, Color> syntaxTokens;

  final Color? blockquoteForeground;
  final Color blockquoteBorder;
  final double blockquoteBorderWidth;
  final Color? blockquoteBackground;
  final bool blockquoteItalic;

  final Color link;
  final Color linkHover;
  final LinkUnderline linkUnderline;

  final Color hr;
  final double hrHeight;

  final Color? tableBorder;
  final Color? tableHeaderBackground;
  final Color? tableStripeBackground;

  final Color checkboxAccent;
  final Color? checkboxBorder;

  final Color sidebarBackground;
  final Color sidebarForeground;
  final Color sidebarActiveBackground;
  final Color? sidebarActiveForeground;

  // ---- Derived styles ----

  TextStyle get bodyStyle => TextStyle(
        color: foreground,
        fontSize: fontSize,
        fontWeight: _weight(fontWeight),
        height: lineHeight,
        fontFamily: fontFamily.isEmpty ? null : fontFamily.first,
        fontFamilyFallback: fontFamily.length > 1 ? fontFamily.sublist(1) : null,
      );

  TextStyle get monoStyle => TextStyle(
        color: codeBlockForeground ?? foreground,
        fontSize: fontSize * codeBlockFontScale,
        height: 1.45,
        fontFamily: monoFontFamily.isEmpty ? null : monoFontFamily.first,
        fontFamilyFallback:
            monoFontFamily.length > 1 ? monoFontFamily.sublist(1) : null,
      );

  TextStyle headingStyle(int level) {
    final i = (level - 1).clamp(0, 5);
    final family = headingFontFamily ?? fontFamily;
    return TextStyle(
      color: headingColors[i] ?? foreground,
      fontSize: headingSizes[i],
      fontWeight: _weight(headingWeights[i]),
      fontStyle: headingItalics[i] ? FontStyle.italic : FontStyle.normal,
      height: 1.25,
      fontFamily: family.isEmpty ? null : family.first,
      fontFamilyFallback: family.length > 1 ? family.sublist(1) : null,
    );
  }

  TextStyle get inlineCodeStyle => TextStyle(
        color: codeInlineForeground ?? foreground,
        backgroundColor: codeInlineBackground,
        fontSize: fontSize * codeInlineFontScale,
        fontFamily: monoFontFamily.isEmpty ? null : monoFontFamily.first,
        fontFamilyFallback:
            monoFontFamily.length > 1 ? monoFontFamily.sublist(1) : null,
      );

  TextStyle get linkStyle => TextStyle(
        color: link,
        decoration: linkUnderline == LinkUnderline.always
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: link,
      );

  /// Color for visible markdown syntax markers (`**`, `#`, `` ` ``…) in the
  /// focused block.
  Color get syntaxMarkerColor => foreground.withValues(alpha: 0.38);

  /// Subtle color for UI hints (placeholder text, line numbers).
  Color get hintColor => foreground.withValues(alpha: 0.30);

  Color get blockquoteTextColor => blockquoteForeground ?? foreground;

  static FontWeight _weight(int w) =>
      FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)];

  /// A copy scaled by [factor] for UI zoom: every derived style flows from
  /// fontSize/headingSizes, and the writing column grows with the text.
  ReadmeTheme scaled(double factor) => ReadmeTheme(
        id: id,
        name: name,
        dark: dark,
        background: background,
        foreground: foreground,
        accent: accent,
        caret: caret,
        selectionBackground: selectionBackground,
        selectionForeground: selectionForeground,
        fontFamily: fontFamily,
        monoFontFamily: monoFontFamily,
        headingFontFamily: headingFontFamily,
        fontSize: fontSize * factor,
        fontWeight: fontWeight,
        lineHeight: lineHeight,
        contentMaxWidth: contentMaxWidth * factor,
        headingSizes: [for (final s in headingSizes) s * factor],
        headingWeights: headingWeights,
        headingColors: headingColors,
        headingItalics: headingItalics,
        headingAligns: headingAligns,
        h1BorderBottom: h1BorderBottom,
        h1BorderWidth: h1BorderWidth,
        h2BorderBottom: h2BorderBottom,
        h2BorderWidth: h2BorderWidth,
        codeInlineForeground: codeInlineForeground,
        codeInlineBackground: codeInlineBackground,
        codeInlineBorder: codeInlineBorder,
        codeInlineRadius: codeInlineRadius,
        codeInlineFontScale: codeInlineFontScale,
        codeBlockBackground: codeBlockBackground,
        codeBlockForeground: codeBlockForeground,
        codeBlockBorder: codeBlockBorder,
        codeBlockRadius: codeBlockRadius,
        codeBlockFontScale: codeBlockFontScale,
        syntaxPreset: syntaxPreset,
        syntaxTokens: syntaxTokens,
        blockquoteForeground: blockquoteForeground,
        blockquoteBorder: blockquoteBorder,
        blockquoteBorderWidth: blockquoteBorderWidth,
        blockquoteBackground: blockquoteBackground,
        blockquoteItalic: blockquoteItalic,
        link: link,
        linkHover: linkHover,
        linkUnderline: linkUnderline,
        hr: hr,
        hrHeight: hrHeight,
        tableBorder: tableBorder,
        tableHeaderBackground: tableHeaderBackground,
        tableStripeBackground: tableStripeBackground,
        checkboxAccent: checkboxAccent,
        checkboxBorder: checkboxBorder,
        sidebarBackground: sidebarBackground,
        sidebarForeground: sidebarForeground,
        sidebarActiveBackground: sidebarActiveBackground,
        sidebarActiveForeground: sidebarActiveForeground,
      );

  // ---- JSON ----

  static ReadmeTheme fromJson(String id, Map<String, dynamic> json) {
    Color? color(String key) => _parseColor(json[key] as String?);
    Color colorReq(String key, Color fallback) => color(key) ?? fallback;
    List<String> fonts(String key, List<String> fallback) =>
        (json[key] as List?)?.cast<String>() ?? fallback;
    double num_(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;

    final foreground = colorReq('foreground', const Color(0xFF333333));
    final accent = colorReq('accent', const Color(0xFF428BCA));

    final tokens = <SyntaxToken, Color>{};
    for (final t in SyntaxToken.values) {
      final key =
          'syntax${t.name[0].toUpperCase()}${t.name.substring(1)}';
      final c = color(key);
      if (c != null) tokens[t] = c;
    }

    List<T> six<T>(String key, T Function(dynamic) map, List<T> fallback) {
      final raw = json[key] as List?;
      if (raw == null || raw.length < 6) return fallback;
      return [for (var i = 0; i < 6; i++) map(raw[i])];
    }

    return ReadmeTheme(
      id: id,
      name: json['name'] as String? ?? id,
      dark: json['dark'] as bool? ?? false,
      background: colorReq('background', const Color(0xFFFFFFFF)),
      foreground: foreground,
      accent: accent,
      caret: colorReq('caret', foreground),
      selectionBackground:
          colorReq('selectionBackground', const Color(0xFFB5D6FC)),
      selectionForeground: color('selectionForeground'),
      fontFamily: fonts('fontFamily', const ['Helvetica', 'sans-serif']),
      monoFontFamily: fonts('monoFontFamily', const ['Menlo', 'monospace']),
      headingFontFamily: (json['headingFontFamily'] as List?)?.cast<String>(),
      fontSize: num_('fontSize', 16),
      fontWeight: (json['fontWeight'] as num?)?.toInt() ?? 400,
      lineHeight: num_('lineHeight', 1.6),
      contentMaxWidth: num_('contentMaxWidth', 860),
      headingSizes: six('headingSizes', (v) => (v as num).toDouble(),
          const [36, 28, 24, 20, 16, 16]),
      headingWeights: six('headingWeights', (v) => (v as num).toInt(),
          const [700, 700, 700, 700, 700, 700]),
      headingColors: six('headingColors',
          (v) => _parseColor(v as String?), const [null, null, null, null, null, null]),
      headingItalics: six('headingItalics', (v) => v as bool? ?? false,
          const [false, false, false, false, false, false]),
      headingAligns: six(
          'headingAligns',
          (v) => switch (v as String? ?? 'left') {
                'center' => TextAlign.center,
                'right' => TextAlign.right,
                _ => TextAlign.left,
              },
          const [
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left
          ]),
      h1BorderBottom: color('h1BorderBottom'),
      h1BorderWidth: num_('h1BorderWidth', 0),
      h2BorderBottom: color('h2BorderBottom'),
      h2BorderWidth: num_('h2BorderWidth', 0),
      codeInlineForeground: color('codeInlineForeground'),
      codeInlineBackground: color('codeInlineBackground'),
      codeInlineBorder: color('codeInlineBorder'),
      codeInlineRadius: num_('codeInlineRadius', 3),
      codeInlineFontScale: num_('codeInlineFontScale', 0.9),
      codeBlockBackground: color('codeBlockBackground'),
      codeBlockForeground: color('codeBlockForeground'),
      codeBlockBorder: color('codeBlockBorder'),
      codeBlockRadius: num_('codeBlockRadius', 3),
      codeBlockFontScale: num_('codeBlockFontScale', 0.9),
      syntaxPreset: json['syntaxPreset'] as String?,
      syntaxTokens: tokens,
      blockquoteForeground: color('blockquoteForeground'),
      blockquoteBorder: colorReq('blockquoteBorder', const Color(0xFFDFE2E5)),
      blockquoteBorderWidth: num_('blockquoteBorderWidth', 4),
      blockquoteBackground: color('blockquoteBackground'),
      blockquoteItalic: json['blockquoteItalic'] as bool? ?? false,
      link: colorReq('link', accent),
      linkHover: colorReq('linkHover', colorReq('link', accent)),
      linkUnderline: switch (json['linkUnderline'] as String? ?? 'hover') {
        'none' => LinkUnderline.none,
        'always' => LinkUnderline.always,
        _ => LinkUnderline.hover,
      },
      hr: colorReq('hr', const Color(0xFFE7E7E7)),
      hrHeight: num_('hrHeight', 1),
      tableBorder: color('tableBorder'),
      tableHeaderBackground: color('tableHeaderBackground'),
      tableStripeBackground: color('tableStripeBackground'),
      checkboxAccent: colorReq('checkboxAccent', accent),
      checkboxBorder: color('checkboxBorder'),
      sidebarBackground: colorReq('sidebarBackground', const Color(0xFFFAFAFA)),
      sidebarForeground: colorReq('sidebarForeground', const Color(0xFF777777)),
      sidebarActiveBackground:
          colorReq('sidebarActiveBackground', const Color(0xFFEEEEEE)),
      sidebarActiveForeground: color('sidebarActiveForeground'),
    );
  }
}

/// Parses `#RRGGBB` or `#RRGGBBAA` (CSS order — alpha LAST, unlike Flutter's
/// ARGB hex literals).
Color? _parseColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = '${h}FF';
  if (h.length != 8) return null;
  final rgba = int.tryParse(h, radix: 16);
  if (rgba == null) return null;
  final rgb = rgba >> 8;
  final a = rgba & 0xFF;
  return Color((a << 24) | rgb);
}
