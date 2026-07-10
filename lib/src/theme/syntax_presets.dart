/// Bridges [ReadmeTheme]'s syntax settings to the theme format consumed by
/// package:re_highlight's `TextSpanRenderer`: a `Map<String, TextStyle>` keyed
/// by highlight.js scope names ('root', 'comment', 'keyword', 'string',
/// 'title', 'built_in', …).
///
/// Note on key spelling: re_highlight's bundled style maps were generated from
/// highlight.js CSS and use class-selector spellings with trailing
/// underscores per dotted segment ('title.function_', 'variable.language_'),
/// while the language grammars emit the plain scope names ('title.function',
/// 'variable.language'). The renderer looks scopes up by exact string, so the
/// maps built here contain both spellings.
library;

import 'package:flutter/painting.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/github.dart';

import 'readme_theme.dart';

/// Builds the re_highlight theme map for [theme].
///
/// If [ReadmeTheme.syntaxPreset] names a known highlight.js preset its palette
/// is used; otherwise the map is built from [ReadmeTheme.syntaxTokens]. Every
/// style is merged over [baseMonoStyle] so font family and size stay
/// consistent across tokens.
Map<String, TextStyle> syntaxThemeFor(
  ReadmeTheme theme,
  TextStyle baseMonoStyle,
) {
  return switch (theme.syntaxPreset) {
    'highlightjs-github' => _fromPreset(githubTheme, baseMonoStyle),
    'highlightjs-atom-one-dark' => _fromPreset(atomOneDarkTheme, baseMonoStyle),
    _ => _fromTokens(theme.syntaxTokens, baseMonoStyle),
  };
}

Map<String, TextStyle> _fromPreset(
  Map<String, TextStyle> preset,
  TextStyle base,
) {
  final map = <String, TextStyle>{};
  for (final MapEntry(:key, :value) in preset.entries) {
    // The code block's background is painted by the widget from
    // ReadmeTheme.codeBlockBackground; keep only the preset's foreground for
    // 'root' so text runs don't paint a second, mismatched background.
    final style = base.merge(
      key == 'root' ? TextStyle(color: value.color) : value,
    );
    map[key] = style;
    // Alias the CSS-derived spelling to the emitted scope name.
    map.putIfAbsent(_normalizeScope(key), () => style);
  }
  map.putIfAbsent('root', () => base);
  return map;
}

final _trailingUnderscores = RegExp(r'_+$');

/// 'title.class_.inherited__' → 'title.class.inherited'; leaves interior
/// underscores ('built_in') untouched.
String _normalizeScope(String key) => key
    .split('.')
    .map((s) => s.replaceAll(_trailingUnderscores, ''))
    .join('.');

/// [SyntaxToken] slots → the highlight.js scope names they color.
const Map<SyntaxToken, List<String>> _tokenScopes = {
  SyntaxToken.comment: ['comment', 'code'],
  SyntaxToken.keyword: ['keyword', 'doctag', 'meta-keyword', 'type'],
  SyntaxToken.string: [
    'string',
    'meta-string',
    'regexp',
    'regex',
    'char.escape',
  ],
  SyntaxToken.number: ['number'],
  SyntaxToken.function: [
    'title',
    'title.function',
    'title.function_',
    'title.class',
    'title.class_',
    'title.class.inherited',
    'title.class_.inherited__',
    'function',
    'section',
  ],
  SyntaxToken.variable: [
    'variable',
    'template-variable',
    'variable.language',
    'variable.language_',
    'variable.constant',
  ],
  SyntaxToken.tag: ['tag', 'name', 'selector-tag', 'template-tag'],
  SyntaxToken.attribute: [
    'attr',
    'attribute',
    'property',
    'selector-attr',
    'selector-class',
    'selector-id',
    'selector-pseudo',
  ],
  SyntaxToken.atom: ['literal', 'symbol', 'bullet'],
  SyntaxToken.builtin: ['built_in', 'builtin'],
  SyntaxToken.meta: ['meta', 'meta.prompt'],
  SyntaxToken.bracket: ['punctuation', 'operator'],
  SyntaxToken.link: ['link'],
  SyntaxToken.quote: ['quote'],
};

Map<String, TextStyle> _fromTokens(
  Map<SyntaxToken, Color> tokens,
  TextStyle base,
) {
  final map = <String, TextStyle>{'root': base};
  for (final MapEntry(:key, :value) in tokens.entries) {
    final style = base.copyWith(color: value);
    for (final scope in _tokenScopes[key] ?? const <String>[]) {
      map[scope] = style;
    }
  }
  return map;
}
