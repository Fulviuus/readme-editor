/// The document: an ordered list of blocks plus the byte-level facts needed
/// to serialize back exactly what was loaded (line endings, BOM, final
/// newline, trailing blank lines).
library;

import 'block.dart';
import 'block_splitter.dart';

const _bom = '\u{FEFF}';

class Document {
  Document({
    required this.blocks,
    this.lineEnding = '\n',
    this.hadBom = false,
    this.hadFinalNewline = true,
    this.trailingBlankLines = 0,
  }) {
    if (blocks.isEmpty) {
      blocks.add(Block(
          kind: BlockKind.paragraph, source: '', blankLinesBefore: 0));
    }
  }

  /// Never empty — an empty document is one empty paragraph.
  final List<Block> blocks;

  String lineEnding;
  bool hadBom;
  bool hadFinalNewline;
  int trailingBlankLines;

  factory Document.parse(String text) {
    var t = text;
    final hadBom = t.startsWith(_bom);
    if (hadBom) t = t.substring(_bom.length);
    final lineEnding = t.contains('\r\n') ? '\r\n' : '\n';
    t = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final hadFinalNewline = t.endsWith('\n') || t.isEmpty;
    if (t.endsWith('\n')) t = t.substring(0, t.length - 1);
    final result = splitMarkdown(t);
    return Document(
      blocks: result.blocks,
      lineEnding: lineEnding,
      hadBom: hadBom,
      hadFinalNewline: hadFinalNewline,
      trailingBlankLines: result.trailingBlankLines,
    );
  }

  /// Round-trip contract: `Document.parse(text).serialize() == text` for any
  /// input (see block_splitter.dart). Edited blocks re-serialize with exactly
  /// what the editor holds; separators use each block's [Block.blankLinesBefore].
  String serialize() {
    final buf = StringBuffer();
    if (hadBom) buf.write(_bom);
    final effective = List<Block>.of(blocks);
    // A trailing empty paragraph (the always-editable tail) never reaches
    // disk as phantom blank lines.
    while (effective.length > 1 &&
        effective.last.kind == BlockKind.paragraph &&
        effective.last.source.isEmpty) {
      effective.removeLast();
    }
    if (effective.length == 1 && effective.first.source.isEmpty) {
      return hadBom ? _bom : '';
    }
    for (var k = 0; k < effective.length; k++) {
      if (k > 0) {
        buf.write('\n' * (1 + effective[k].blankLinesBefore));
      } else {
        buf.write('\n' * effective[k].blankLinesBefore);
      }
      buf.write(effective[k].source);
    }
    buf.write('\n' * trailingBlankLines);
    if (hadFinalNewline) buf.write('\n');
    var out = buf.toString();
    if (lineEnding != '\n') out = out.replaceAll('\n', lineEnding);
    return out;
  }

  int indexOfBlock(String id) => blocks.indexWhere((b) => b.id == id);

  Block? blockById(String id) {
    final i = indexOfBlock(id);
    return i < 0 ? null : blocks[i];
  }

  static final _linkDefRe =
      RegExp(r'^ {0,3}\[([^\]^]+)\]:\s*(\S+)', multiLine: true);
  static final _footnoteDefRe =
      RegExp(r'^ {0,3}\[\^([^\]\s]+)\]:\s*(.*)$', multiLine: true);

  /// `[ref]: url` definitions across the document, keyed by normalized ref.
  Map<String, String> get linkDefinitions {
    final defs = <String, String>{};
    for (final b in blocks) {
      for (final m in _linkDefRe.allMatches(b.source)) {
        final key = m.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();
        defs.putIfAbsent(key, () => m.group(2)!);
      }
    }
    return defs;
  }

  /// Footnote ids in first-reference order → their 1-based number, plus the
  /// definition text keyed by id.
  ({Map<String, int> numbers, Map<String, String> texts}) get footnotes {
    final texts = <String, String>{};
    for (final b in blocks) {
      for (final m in _footnoteDefRe.allMatches(b.source)) {
        texts.putIfAbsent(m.group(1)!, () => m.group(2)!.trim());
      }
    }
    // Number footnotes by first reference appearance across the document.
    final numbers = <String, int>{};
    final refRe = RegExp(r'\[\^([^\]\s]+)\]');
    for (final b in blocks) {
      for (final line in b.source.split('\n')) {
        if (_footnoteDefRe.hasMatch(line)) continue; // skip definitions
        for (final m in refRe.allMatches(line)) {
          numbers.putIfAbsent(m.group(1)!, () => numbers.length + 1);
        }
      }
    }
    return (numbers: numbers, texts: texts);
  }

  /// Heading outline for the sidebar: (level, text, blockId).
  List<OutlineEntry> get outline => [
        for (final b in blocks)
          if (b.kind == BlockKind.heading)
            OutlineEntry(b.headingLevel, b.headingText, b.id),
      ];
}

class OutlineEntry {
  const OutlineEntry(this.level, this.text, this.blockId);
  final int level;
  final String text;
  final String blockId;
}
