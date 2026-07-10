/// Splits markdown text into [Block]s along block boundaries.
///
/// This is intentionally NOT a full CommonMark parser — inline content is
/// parsed later, per block, by package:markdown. This scanner only decides
/// where one block ends and the next begins, and it must be conservative:
/// every line of input ends up in exactly one block or in a blank-line count,
/// so `serialize(split(text)) == text` for normalized (`\n`, no BOM) input.
///
/// Precedence order (per docs/DESIGN-editor-interaction.md §1.1):
/// front matter (document start only) → fenced code → math → thematic break
/// → ATX heading → blockquote → list → HTML → table → indented code →
/// paragraph (with setext post-pass).
library;

import 'block.dart';

final _blankRe = RegExp(r'^[ \t]*$');
final _fenceStartRe = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final _atxHeadingRe = RegExp(r'^ {0,3}#{1,6}(\s|$)');
final _thematicBreakRe = RegExp(r'^ {0,3}([-_*])( *\1){2,}[ \t]*$');
final _blockquoteRe = RegExp(r'^ {0,3}>');
final _listItemRe = RegExp(r'^( {0,3})((?:[-*+])|\d{1,9}[.)])([ \t]+|$)');
final _setextUnderlineRe = RegExp(r'^ {0,3}(=+|-+)[ \t]*$');
final _tableDelimiterRe = RegExp(
    r'^ {0,3}\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$');
final _mathFenceRe = RegExp(r'^ {0,3}\$\$');
final _htmlStartRe = RegExp(r'^ {0,3}<[a-zA-Z!/?]');
final _indentedRe = RegExp(r'^(?: {4,}|\t)\S');
final _listContinuationRe = RegExp(r'^(?: {2,}|\t)\S');

bool isBlank(String line) => _blankRe.hasMatch(line);

class SplitResult {
  SplitResult(this.blocks, {required this.trailingBlankLines});
  final List<Block> blocks;

  /// Blank lines after the last block (before the final newline, if any).
  final int trailingBlankLines;
}

/// Splits normalized text (LF line endings, no BOM, no trailing newline
/// requirement) into blocks. When [isFragment] is true (re-splitting one
/// edited block's source), front-matter detection is disabled — `---` at the
/// start of a fragment is a thematic break, not YAML.
SplitResult splitMarkdown(String text, {bool isFragment = false}) {
  if (text.isEmpty) return SplitResult([], trailingBlankLines: 0);
  final lines = text.split('\n');

  final blocks = <Block>[];
  var i = 0;
  var pendingBlanks = 0;

  void emit(BlockKind kind, int startLine, int endLineExclusive) {
    blocks.add(Block(
      kind: kind,
      source: lines.sublist(startLine, endLineExclusive).join('\n'),
      blankLinesBefore: pendingBlanks,
    ));
    pendingBlanks = 0;
  }

  // Front matter: `---` on the very first line, closed by `---` or `...`.
  if (!isFragment &&
      lines.isNotEmpty &&
      RegExp(r'^---[ \t]*$').hasMatch(lines[0])) {
    for (var j = 1; j < lines.length; j++) {
      if (RegExp(r'^(---|\.\.\.)[ \t]*$').hasMatch(lines[j])) {
        emit(BlockKind.frontMatter, 0, j + 1);
        i = j + 1;
        break;
      }
    }
  }

  while (i < lines.length) {
    final line = lines[i];

    if (isBlank(line)) {
      pendingBlanks++;
      i++;
      continue;
    }

    // Fenced code: swallow everything (blank lines included) until a closing
    // fence — same char, length >= opening, nothing else on the line. An
    // unclosed fence owns everything to the end of input.
    final fence = _fenceStartRe.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      // CommonMark: a backtick fence's info string may not contain backticks
      // (so ``` `x` ``` is inline code, not a fence).
      if (!(marker[0] == '`' && fence.group(2)!.contains('`'))) {
        final closeRe = RegExp(
            '^ {0,3}\\${marker[0]}{${marker.length},}[ \t]*\$');
        var j = i + 1;
        while (j < lines.length && !closeRe.hasMatch(lines[j])) {
          j++;
        }
        final end = j < lines.length ? j + 1 : lines.length;
        emit(BlockKind.fencedCode, i, end);
        i = end;
        continue;
      }
    }

    // Math block: `$$ ... $$`; single-line `$$x$$` allowed.
    if (_mathFenceRe.hasMatch(line)) {
      final rest = line.trim().substring(2);
      if (rest.isNotEmpty && rest.endsWith(r'$$')) {
        emit(BlockKind.mathBlock, i, i + 1);
        i++;
        continue;
      }
      var j = i + 1;
      while (j < lines.length && !lines[j].trimRight().endsWith(r'$$')) {
        j++;
      }
      final end = j < lines.length ? j + 1 : lines.length;
      emit(BlockKind.mathBlock, i, end);
      i = end;
      continue;
    }

    // Thematic break — before list, so `- - -` and `***` win over list items.
    if (_thematicBreakRe.hasMatch(line)) {
      emit(BlockKind.thematicBreak, i, i + 1);
      i++;
      continue;
    }

    // ATX heading: exactly one line.
    if (_atxHeadingRe.hasMatch(line)) {
      emit(BlockKind.heading, i, i + 1);
      i++;
      continue;
    }

    // Blockquote: `>` lines plus lazy continuation; a blank line ends it.
    if (_blockquoteRe.hasMatch(line)) {
      var j = i + 1;
      while (j < lines.length &&
          !isBlank(lines[j]) &&
          (_blockquoteRe.hasMatch(lines[j]) || _isLazyContinuation(lines[j]))) {
        j++;
      }
      emit(BlockKind.blockquote, i, j);
      i = j;
      continue;
    }

    // List: the whole list — all items, nested/indented continuations, and
    // single interior blank lines — is ONE block. Two consecutive blank
    // lines always end the list.
    if (_listItemRe.hasMatch(line)) {
      var j = i + 1;
      var end = i + 1; // exclusive end of confirmed list content
      while (j < lines.length) {
        final l = lines[j];
        if (isBlank(l)) {
          // At most one interior blank, and only if list content follows.
          if (j + 1 < lines.length &&
              !isBlank(lines[j + 1]) &&
              (_listItemRe.hasMatch(lines[j + 1]) ||
                  _listContinuationRe.hasMatch(lines[j + 1]))) {
            j++;
            continue;
          }
          break;
        }
        if (_listItemRe.hasMatch(l) ||
            _listContinuationRe.hasMatch(l) ||
            _isLazyContinuation(l)) {
          j++;
          end = j;
          continue;
        }
        break;
      }
      emit(BlockKind.list, i, end);
      i = end;
      continue;
    }

    // HTML block: consume until blank line.
    if (_htmlStartRe.hasMatch(line)) {
      var j = i + 1;
      while (j < lines.length && !isBlank(lines[j])) {
        j++;
      }
      emit(BlockKind.html, i, j);
      i = j;
      continue;
    }

    // Table: header row containing `|` with a delimiter row right below.
    if (_isTableStart(lines, i)) {
      var j = i + 2;
      while (j < lines.length &&
          !isBlank(lines[j]) &&
          lines[j].contains('|')) {
        j++;
      }
      emit(BlockKind.table, i, j);
      i = j;
      continue;
    }

    // Indented code block (4 spaces / tab) at block start.
    if (_indentedRe.hasMatch(line)) {
      var j = i + 1;
      var end = i + 1;
      while (j < lines.length) {
        if (isBlank(lines[j])) {
          if (j + 1 < lines.length && _indentedRe.hasMatch(lines[j + 1])) {
            j++;
            continue;
          }
          break;
        }
        if (_indentedRe.hasMatch(lines[j])) {
          j++;
          end = j;
          continue;
        }
        break;
      }
      emit(BlockKind.indentedCode, i, end);
      i = end;
      continue;
    }

    // Paragraph: consume until blank line, an interrupting construct, a
    // table start, or a setext underline (which turns it into a heading).
    {
      final start = i;
      var j = i + 1;
      var isHeading = false;
      while (j < lines.length) {
        final l = lines[j];
        if (isBlank(l)) break;
        if (_setextUnderlineRe.hasMatch(l)) {
          j++;
          isHeading = true;
          break;
        }
        if (_fenceStartRe.hasMatch(l) ||
            _atxHeadingRe.hasMatch(l) ||
            _thematicBreakRe.hasMatch(l) ||
            _blockquoteRe.hasMatch(l) ||
            _listItemRe.hasMatch(l) ||
            _mathFenceRe.hasMatch(l) ||
            _htmlStartRe.hasMatch(l) ||
            _isTableStart(lines, j)) {
          break;
        }
        j++;
      }
      emit(isHeading ? BlockKind.heading : BlockKind.paragraph, start, j);
      i = j;
    }
  }

  return SplitResult(blocks, trailingBlankLines: pendingBlanks);
}

bool _isTableStart(List<String> lines, int i) {
  if (!lines[i].contains('|') || i + 1 >= lines.length) return false;
  final delimiter = lines[i + 1];
  if (!delimiter.contains('-') || !_tableDelimiterRe.hasMatch(delimiter)) {
    return false;
  }
  // DESIGN-editor-interaction.md §1.1 rule 6: the delimiter row must have at
  // least as many cells as the header row, so `x | y` above a lone `---`
  // stays a paragraph (→ setext heading), not a one-column table.
  return _tableCellCount(delimiter) >= _tableCellCount(lines[i]);
}

int _tableCellCount(String line) {
  var l = line.trim();
  if (l.startsWith('|')) l = l.substring(1);
  if (l.endsWith('|')) l = l.substring(0, l.length - 1);
  return l.split('|').length;
}

/// A lazy continuation line: plain text that visually continues the previous
/// list item / quote line without markers. Anything that would start its own
/// block is not a continuation.
bool _isLazyContinuation(String l) {
  return !isBlank(l) &&
      !_fenceStartRe.hasMatch(l) &&
      !_atxHeadingRe.hasMatch(l) &&
      !_thematicBreakRe.hasMatch(l) &&
      !_blockquoteRe.hasMatch(l) &&
      !_listItemRe.hasMatch(l) &&
      !_mathFenceRe.hasMatch(l) &&
      !_htmlStartRe.hasMatch(l);
}

/// Re-derives the [BlockKind] of a single edited block from its source.
/// Returns null when the source no longer scans as exactly one block (the
/// caller should then run a structural re-scan and split).
BlockKind? deriveSingleKind(String source) {
  final result = splitMarkdown(source, isFragment: true);
  if (result.blocks.length != 1 || result.trailingBlankLines > 0) return null;
  if (result.blocks.first.blankLinesBefore > 0) return null;
  return result.blocks.first.kind;
}
