/// Word / character / reading-time statistics for the status bar.
///
/// Deliberately naive: markdown markers, link URLs and table plumbing are
/// stripped from the counted text, while fenced-code content still counts as
/// words. Splitting is whitespace-based with one extra rule for space-free
/// scripts — every CJK character counts as a word of its own.
///
/// Pure Dart (no Flutter imports), like the rest of the document layer.
library;

import '../document/block.dart';
import '../document/document.dart';

class WordCountResult {
  const WordCountResult({
    required this.words,
    required this.characters,
    required this.readingMinutes,
  });

  factory WordCountResult.fromDocument(Document doc) {
    var words = 0;
    var characters = 0;
    for (final block in doc.blocks) {
      final (w, c) = _count(_visibleText(block));
      words += w;
      characters += c;
    }
    return WordCountResult(
      words: words,
      characters: characters,
      readingMinutes: words == 0 ? 0 : (words / _wordsPerMinute).ceil(),
    );
  }

  /// Whitespace-separated words (each CJK character counts as one word).
  final int words;

  /// Non-whitespace characters of the visible (marker-stripped) text.
  final int characters;

  /// Estimated reading time at ~200 words per minute; 0 when empty, and
  /// never 0 for a non-empty document.
  final int readingMinutes;

  @override
  String toString() => 'WordCountResult(words: $words, '
      'characters: $characters, readingMinutes: $readingMinutes)';
}

const _wordsPerMinute = 200;

// ---- Per-block visible text ----

String _visibleText(Block block) {
  switch (block.kind) {
    case BlockKind.thematicBreak:
    case BlockKind.frontMatter:
      return '';
    case BlockKind.fencedCode:
    case BlockKind.indentedCode:
      // Code content counts as words; the fence markers do not.
      return block.codeBody;
    case BlockKind.heading:
      return _stripInline(block.headingText);
    case BlockKind.mathBlock:
      return block.source.replaceAll(r'$$', ' ');
    case BlockKind.html:
      return _stripInline(block.source.replaceAll(_htmlTag, ' '));
    case BlockKind.table:
      return [
        for (final line in block.lines)
          if (!_isTableAlignmentRow(line))
            _stripInline(line.replaceAll('|', ' ')),
      ].join('\n');
    case BlockKind.paragraph:
    case BlockKind.blockquote:
    case BlockKind.list:
      return [
        for (final line in block.lines) _stripInline(_stripLineMarkers(line)),
      ].join('\n');
  }
}

final _htmlTag = RegExp(r'</?[a-zA-Z][^>]*>');
final _quoteMarkers = RegExp(r'^(\s*>)+\s?');
final _listMarker = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s+');
final _taskBox = RegExp(r'^\[[ xX]\]\s*');
final _atxMarker = RegExp(r'^\s*#{1,6}\s+');
final _tableAlignChars = RegExp(r'^[\s|:-]+$');

bool _isTableAlignmentRow(String line) =>
    line.contains('-') && _tableAlignChars.hasMatch(line);

/// Strips leading block-level markers from one line: blockquote `>`s, a list
/// bullet / ordered marker, a task checkbox, ATX heading hashes.
String _stripLineMarkers(String line) => line
    .replaceFirst(_quoteMarkers, '')
    .replaceFirst(_listMarker, '')
    .replaceFirst(_taskBox, '')
    .replaceFirst(_atxMarker, '');

final _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final _inlineLink = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _refLink = RegExp(r'\[([^\]]*)\]\[[^\]]*\]');
final _autoLink = RegExp(r'<https?://[^>]+>');
final _bareUrl = RegExp(r'https?://\S+');
final _backticks = RegExp('`+');
final _emphasisMarkers = RegExp(r'\*{1,3}|_{2,3}|~~');

/// Strips inline markdown, keeping the human-visible text: link/image labels
/// stay, URLs and emphasis/code markers go.
String _stripInline(String line) => line
    .replaceAllMapped(_image, (m) => m[1]!)
    .replaceAllMapped(_inlineLink, (m) => m[1]!)
    .replaceAllMapped(_refLink, (m) => m[1]!)
    .replaceAll(_autoLink, ' ')
    .replaceAll(_bareUrl, ' ')
    .replaceAll(_backticks, '')
    .replaceAll(_emphasisMarkers, '')
    .replaceAll(_htmlTag, ' ');

// ---- Counting ----

final _wordRune = RegExp(r'[\p{L}\p{N}]', unicode: true);

(int words, int characters) _count(String text) {
  var words = 0;
  var characters = 0;
  var runHasWordChar = false;

  void flushRun() {
    if (runHasWordChar) words++;
    runHasWordChar = false;
  }

  for (final rune in text.runes) {
    final s = String.fromCharCode(rune);
    if (s.trim().isEmpty) {
      // Unicode whitespace ends the current word run.
      flushRun();
      continue;
    }
    characters++;
    if (_isCjk(rune)) {
      flushRun();
      words++;
    } else if (!runHasWordChar && _wordRune.hasMatch(s)) {
      runHasWordChar = true;
    }
  }
  flushRun();
  return (words, characters);
}

/// CJK code points counted one word each: Han (incl. extensions A/B+ and
/// compatibility), kana, and Hangul syllables.
bool _isCjk(int rune) =>
    (rune >= 0x3040 && rune <= 0x30FF) || // Hiragana + Katakana
    (rune >= 0x3400 && rune <= 0x4DBF) || // CJK extension A
    (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK unified ideographs
    (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul syllables
    (rune >= 0xF900 && rune <= 0xFAFF) || // CJK compatibility ideographs
    (rune >= 0xFF66 && rune <= 0xFF9D) || // Halfwidth katakana
    (rune >= 0x20000 && rune <= 0x2FA1F); // CJK extensions B and beyond
