/// Core document model.
///
/// A document is an ordered list of [Block]s. Each block owns a slice of raw
/// markdown source (without the blank lines that separate it from its
/// neighbours). All rendering and editing state is derived from `source`, so
/// serializing a document back to disk is lossless for untouched blocks.
library;

enum BlockKind {
  paragraph,
  heading,
  fencedCode,
  indentedCode,
  blockquote,
  list,
  table,
  thematicBreak,
  html,
  mathBlock,
  frontMatter,
}

int _idCounter = 0;

String nextBlockId() => 'b${++_idCounter}';

class Block {
  Block({
    String? id,
    required this.kind,
    required this.source,
    this.blankLinesBefore = 1,
  }) : id = id ?? nextBlockId();

  /// Stable identity used for focus tracking and undo across rebuilds.
  /// Preserved when a block's source is edited in place; new ids are minted
  /// only for blocks created by splits/inserts.
  final String id;

  final BlockKind kind;

  /// Raw markdown source, `\n`-separated lines, no trailing newline.
  final String source;

  /// Blank lines that preceded this block in the original text (0 for the
  /// first block unless the file opened with blank lines). Preserved so
  /// serialization round-trips files that use e.g. two blank lines between
  /// sections, or none after a heading.
  final int blankLinesBefore;

  Block copyWith({
    BlockKind? kind,
    String? source,
    int? blankLinesBefore,
    bool newId = false,
  }) {
    return Block(
      id: newId ? null : id,
      kind: kind ?? this.kind,
      source: source ?? this.source,
      blankLinesBefore: blankLinesBefore ?? this.blankLinesBefore,
    );
  }

  List<String> get lines => source.split('\n');

  bool get isEmpty => source.trim().isEmpty;

  // ---- Derived facts (computed on demand, cached) ----

  /// 1–6 for headings, 0 otherwise. Setext `===` is 1, `---` is 2.
  late final int headingLevel = _headingLevel();

  int _headingLevel() {
    if (kind != BlockKind.heading) return 0;
    final first = lines.first.trimLeft();
    if (first.startsWith('#')) {
      var n = 0;
      while (n < first.length && first[n] == '#') {
        n++;
      }
      return n.clamp(1, 6);
    }
    // Setext: level from the underline (last line).
    return lines.last.trimLeft().startsWith('=') ? 1 : 2;
  }

  bool get isSetextHeading =>
      kind == BlockKind.heading && !lines.first.trimLeft().startsWith('#');

  /// Text of a heading without the `#` markers (ATX) or underline (setext).
  String get headingText {
    if (kind != BlockKind.heading) return '';
    if (isSetextHeading) {
      return lines.sublist(0, lines.length - 1).join(' ').trim();
    }
    return lines.first
        .replaceFirst(RegExp(r'^ {0,3}#{1,6}\s*'), '')
        .replaceFirst(RegExp(r'\s+#+\s*$'), '')
        .trim();
  }

  /// Info string of a fenced code block (e.g. `dart`), or null.
  late final String? fenceLanguage = _fenceLanguage();

  String? _fenceLanguage() {
    if (kind != BlockKind.fencedCode) return null;
    final m = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*(\S*)').firstMatch(lines.first);
    final info = m?.group(2) ?? '';
    return info.isEmpty ? null : info;
  }

  /// Body of a fenced code / indented code / math block (between the
  /// fences). Empty for other kinds.
  String get codeBody {
    final ls = lines;
    if (kind == BlockKind.indentedCode) {
      return ls
          .map((l) => l.replaceFirst(RegExp(r'^(?: {4}|\t)'), ''))
          .join('\n');
    }
    if (kind == BlockKind.mathBlock) {
      var t = source.trim();
      if (t.startsWith(r'$$')) t = t.substring(2);
      if (t.endsWith(r'$$')) t = t.substring(0, t.length - 2);
      return t.trim();
    }
    if (kind != BlockKind.fencedCode || ls.length < 2) return '';
    final closed = _fenceClosed(ls);
    return ls.sublist(1, closed ? ls.length - 1 : ls.length).join('\n');
  }

  static bool _fenceClosed(List<String> ls) {
    if (ls.length < 2) return false;
    final open = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(ls.first);
    final close = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$').firstMatch(ls.last);
    if (open == null || close == null) return false;
    final oc = open.group(1)!, cc = close.group(1)!;
    return cc[0] == oc[0] && cc.length >= oc.length;
  }

  bool get fenceIsClosed =>
      kind == BlockKind.fencedCode && _fenceClosed(lines);

  bool get isOrderedList =>
      kind == BlockKind.list &&
      RegExp(r'^ {0,3}\d{1,9}[.)]').hasMatch(lines.first);

  bool get hasTaskItems =>
      kind == BlockKind.list &&
      lines.any((l) =>
          RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s+\[[ xX]\](\s|$)').hasMatch(l));

  @override
  String toString() =>
      'Block($id, $kind, ${source.length > 40 ? '${source.substring(0, 40)}…' : source})';
}
