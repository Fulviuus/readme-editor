/// Orchestrates hybrid editing: which block is focused, the shared editing
/// controller/focus node, and every structural editing gesture — Enter,
/// Backspace-at-0, auto-conversion, merges, formatting shortcuts, undo
/// bridging (docs/DESIGN-editor-interaction.md §2, §5, §6).
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import '../document/block.dart';
import '../document/block_splitter.dart';
import '../document/document_controller.dart';
import '../theme/readme_theme.dart';
import 'blocks/table_model.dart';
import 'inline_renderer.dart';
import 'inline_tokenizer.dart';
import 'markdown_editing_controller.dart';

final _listItemLineRe =
    RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?');
final _emptyQuoteLineRe = RegExp(r'^ {0,3}(?:> ?)+$');
final _fenceLineRe = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*(\S*)[ \t]*$');
final _thematicLineRe = RegExp(r'^ {0,3}([-_*])( *\1){2,}[ \t]*$');
final _setextLineRe = RegExp(r'^ {0,3}(=+|-+)[ \t]*$');
final _tableDelimLineRe = RegExp(
    r'^ {0,3}\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$');

class EditorController extends ChangeNotifier {
  EditorController(this.docCtrl, ReadmeTheme theme)
      : _renderer = InlineRenderer(theme),
        _theme = theme {
    editing.renderer = _renderer;
    editing.addListener(_onEditingChanged);
    focusNode.addListener(_onFocusNodeChanged);
  }

  final DocumentController docCtrl;
  final MarkdownEditingController editing = MarkdownEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'readme-editing-block');

  InlineRenderer _renderer;
  ReadmeTheme _theme;
  ReadmeTheme get theme => _theme;
  InlineRenderer get renderer => _renderer;

  set theme(ReadmeTheme t) {
    _theme = t;
    _renderer = InlineRenderer(t, imageBuilder: _renderer.imageBuilder);
    editing.renderer = _renderer;
    notifyListeners();
  }

  set imageBuilder(ImageBuilder? b) {
    _renderer = InlineRenderer(_theme, imageBuilder: b);
    editing.renderer = _renderer;
  }

  String? _focusedBlockId;
  String? get focusedBlockId => _focusedBlockId;

  /// Ephemeral trailing paragraph (§8): undo-invisible, removed if abandoned.
  String? _ephemeralBlockId;

  bool focusModeEnabled = false;
  bool typewriterModeEnabled = false;

  /// Source mode (Cmd+/): whole document as one plain-text editor; commits
  /// as a single replaceAll on exit. Owned here, rendered by the app shell.
  final ValueNotifier<bool> sourceModeEnabled = ValueNotifier(false);

  /// Find/replace bar visibility (Cmd+F). Owned here, rendered by the shell.
  final ValueNotifier<bool> findVisible = ValueNotifier(false);

  /// Set by SourceView while source mode is open: commits the source buffer
  /// into the document. The shell calls this before saves, exports and
  /// dirty checks so uncommitted source-mode edits are never lost.
  VoidCallback? commitSourceMode;

  /// Installed by the app shell: resolves and opens a link URL (http(s) in
  /// the browser, relative .md paths in the editor). The editor layer stays
  /// free of url_launcher / workspace knowledge.
  ValueChanged<String>? linkOpener;

  /// Opens [url] via the shell's opener (no-op if none installed).
  void openLink(String url) => linkOpener?.call(url);

  /// URL of the link/autolink at the caret in the focused block, or null.
  String? linkUrlAtCaret() {
    final block = focusedBlock;
    if (block == null) return null;
    final caret = editing.selection.baseOffset;
    for (final node in tokenizeInline(editing.text)) {
      if (caret >= node.start && caret <= node.end) {
        if (node is LinkNode) return node.url;
        if (node is AutolinkNode) return node.url;
      }
    }
    return null;
  }

  /// Edit-menu action: open the link at the caret.
  void openLinkAtCaret() {
    final url = linkUrlAtCaret();
    if (url != null) openLink(url);
  }

  /// Edit-menu action: copy the address of the link at the caret.
  void copyLinkAtCaret() {
    final url = linkUrlAtCaret();
    if (url != null) Clipboard.setData(ClipboardData(text: url));
  }

  void toggleFocusMode() {
    focusModeEnabled = !focusModeEnabled;
    notifyListeners();
  }

  void toggleSourceMode() => sourceModeEnabled.value = !sourceModeEnabled.value;

  /// Sticky x (in the editor's content coordinates) for vertical caret moves
  /// across blocks.
  double? goalX;

  /// Content width of the editor column, kept fresh by the view; used to lay
  /// out neighbour blocks for vertical caret transfer.
  double contentWidth = 700;

  bool _applying = false;
  TextEditingValue _lastValue = TextEditingValue.empty;

  // Per-item focus flags so a focus move rebuilds exactly two items (§9).
  final Map<String, ValueNotifier<bool>> _focusFlags = {};

  ValueNotifier<bool> focusFlag(String blockId) => _focusFlags.putIfAbsent(
      blockId, () => ValueNotifier(blockId == _focusedBlockId));

  Block? get focusedBlock =>
      _focusedBlockId == null ? null : docCtrl.doc.blockById(_focusedBlockId!);

  // ---- Focus management ----

  void focusBlock(String id, {int offset = 0, TextSelection? selection}) {
    final block = docCtrl.doc.blockById(id);
    if (block == null) return;
    final previous = _focusedBlockId;
    if (previous != null && previous != id) {
      _discardEphemeralIfAbandoned(previous);
      _prettifyTableBlock(previous);
    }
    _focusedBlockId = id;
    final sel = selection ??
        TextSelection.collapsed(offset: offset.clamp(0, block.source.length));
    _setEditingValue(block, TextEditingValue(
      text: block.source,
      selection: _clampSelection(sel, block.source.length),
    ));
    docCtrl.sealUndoGroup();
    if (previous != null && previous != id) {
      _focusFlags[previous]?.value = false;
    }
    focusFlag(id).value = true;
    focusNode.requestFocus();
    // Keep the per-item flag map bounded across splits/merges/file loads.
    // Pruned notifiers are dropped, not disposed: an unmounting item widget
    // may still remove its listener this frame.
    if (_focusFlags.length > 512) {
      final live = {for (final b in docCtrl.doc.blocks) b.id};
      _focusFlags.removeWhere(
          (flagId, _) => !live.contains(flagId) && flagId != _focusedBlockId);
    }
    notifyListeners();
  }

  void blur() {
    final previous = _focusedBlockId;
    if (previous == null) return;
    _focusedBlockId = null;
    _focusFlags[previous]?.value = false;
    docCtrl.sealUndoGroup();
    _discardEphemeralIfAbandoned(previous);
    _prettifyTableBlock(previous);
    notifyListeners();
  }

  void _onFocusNodeChanged() {
    if (!focusNode.hasFocus && _focusedBlockId != null) {
      // Focus went elsewhere (sidebar, dialog): leave rendered mode.
      blur();
    }
  }

  void _discardEphemeralIfAbandoned(String id) {
    if (id != _ephemeralBlockId) return;
    _ephemeralBlockId = null;
    final i = docCtrl.doc.indexOfBlock(id);
    if (i < 0) return;
    final b = docCtrl.doc.blocks[i];
    if (b.kind == BlockKind.paragraph && b.source.isEmpty &&
        docCtrl.doc.blocks.length > 1) {
      docCtrl.spliceBlocks(
          index: i, before: [b], after: [], kind: EditKind.blockOp,
          record: false);
    }
  }

  /// Any RECORDED edit touching the ephemeral tail makes it a real block —
  /// discarding it later (unrecorded) would desync the undo stack's splice
  /// indices and undo would corrupt the list. Called at the head of every
  /// mutating handler.
  void _materializeEphemeral() {
    if (_focusedBlockId != null && _focusedBlockId == _ephemeralBlockId) {
      _ephemeralBlockId = null;
    }
  }

  /// Click on the canvas below the last block (§8).
  void focusTail() {
    final blocks = docCtrl.doc.blocks;
    final last = blocks.last;
    if (last.kind == BlockKind.paragraph && last.source.isEmpty) {
      focusBlock(last.id);
      return;
    }
    final tail = Block(kind: BlockKind.paragraph, source: '');
    docCtrl.spliceBlocks(
        index: blocks.length, before: [], after: [tail],
        kind: EditKind.blockOp, record: false);
    _ephemeralBlockId = tail.id;
    focusBlock(tail.id);
  }

  TextSelection _clampSelection(TextSelection sel, int max) =>
      TextSelection(
        baseOffset: sel.baseOffset.clamp(0, max),
        extentOffset: sel.extentOffset.clamp(0, max),
      );

  void _setEditingValue(Block block, TextEditingValue value) {
    _applying = true;
    editing.fallbackKind = block.kind;
    editing.value = value;
    _applying = false;
    _lastValue = value;
  }

  CaretSnapshot? _snap(TextSelection sel) => _focusedBlockId == null
      ? null
      : CaretSnapshot(_focusedBlockId!, sel.baseOffset, sel.extentOffset);

  // ---- The single recording point: TextField edits → document ----

  void _onEditingChanged() {
    if (_applying) return;
    final id = _focusedBlockId;
    if (id == null) return;
    final v = editing.value;
    final old = _lastValue;
    _lastValue = v;
    if (v.text == old.text) {
      if (v.selection != old.selection) {
        docCtrl.sealUndoGroup();
        goalX = null;
      }
      return;
    }
    goalX = null;
    if (id == _ephemeralBlockId) _ephemeralBlockId = null;

    final grew = v.text.length > old.text.length;
    // Multi-line changes (paste, and deletions that create a blank line
    // inside a paragraph) may need a structural split (§2.4). Front matter
    // is exempt: fragment scanning would shatter `---` fences into thematic
    // breaks, and its kind is index-0-only anyway.
    final blockKind = docCtrl.doc.blockById(id)?.kind;
    if (v.text.contains('\n') && blockKind != BlockKind.frontMatter) {
      final parts = splitMarkdown(v.text, isFragment: true).blocks;
      if (parts.length > 1) {
        _rescanAndRefocus(id, v, old);
        return;
      }
    }
    String? committed;
    if (grew && v.selection.isCollapsed && v.selection.baseOffset > 0) {
      committed = v.text[v.selection.baseOffset - 1];
    }
    docCtrl.changeBlockSource(
      id,
      v.text,
      kind: grew ? EditKind.typing : EditKind.deleteBack,
      caretBefore: CaretSnapshot(id, old.selection.baseOffset,
          old.selection.extentOffset),
      caretAfter: _snap(v.selection),
      committedChar: committed,
    );
    final b = docCtrl.doc.blockById(id);
    if (b != null) editing.fallbackKind = b.kind;
  }

  void _rescanAndRefocus(String id, TextEditingValue v, TextEditingValue old) {
    final caret = v.selection.baseOffset;
    final parts = docCtrl.rescanBlock(id, v.text,
        caretBefore: CaretSnapshot(id, old.selection.baseOffset));
    if (parts == null || parts.isEmpty) return;
    final (target, local) = _locateOffset(parts, caret);
    focusBlock(target.id, offset: local);
  }

  /// Maps an absolute offset in the pre-split text to (block, local offset),
  /// accounting for the newlines that became block separators.
  (Block, int) _locateOffset(List<Block> parts, int offset) {
    var remaining = offset;
    for (var k = 0; k < parts.length; k++) {
      final len = parts[k].source.length;
      if (remaining <= len || k == parts.length - 1) {
        return (parts[k], remaining.clamp(0, len));
      }
      remaining -= len;
      // separator newlines: 1 + blank lines before the next part
      remaining -= 1 + parts[k + 1].blankLinesBefore;
      if (remaining < 0) return (parts[k], len);
    }
    return (parts.last, parts.last.source.length);
  }

  // ---- Programmatic text edits within the focused block ----

  /// Replaces [start, end) with [replacement], records one edit, and places
  /// the caret (defaults to just after the replacement).
  void replaceRange(int start, int end, String replacement,
      {int? caretAt, EditKind kind = EditKind.typing}) {
    final id = _focusedBlockId;
    final block = focusedBlock;
    if (id == null || block == null) return;
    _materializeEphemeral();
    final text = editing.text;
    final newText =
        text.replaceRange(start.clamp(0, text.length), end.clamp(0, text.length), replacement);
    final caret = caretAt ?? start + replacement.length;
    final before = _snap(editing.selection);
    _setEditingValue(block,
        TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: caret.clamp(0, newText.length))));
    docCtrl.changeBlockSource(id, newText,
        kind: kind, caretBefore: before, caretAfter: _snap(editing.selection));
    final b = docCtrl.doc.blockById(id);
    if (b != null) editing.fallbackKind = b.kind;
  }

  /// Replaces the focused block's whole source, one atomic (non-coalescing)
  /// edit — used by auto-conversions.
  void _convertTo(String newSource, int caret) {
    final id = _focusedBlockId;
    final block = focusedBlock;
    if (id == null || block == null) return;
    _materializeEphemeral();
    final before = _snap(editing.selection);
    docCtrl.changeBlockSource(id, newSource,
        kind: EditKind.autoConvert,
        caretBefore: before,
        caretAfter: CaretSnapshot(id, caret));
    final updated = docCtrl.doc.blockById(id);
    if (updated != null) {
      _setEditingValue(updated, TextEditingValue(
          text: newSource,
          selection: TextSelection.collapsed(offset: caret.clamp(0, newSource.length))));
    }
    notifyListeners();
  }

  // ---- Enter (§2.1 + §2.3B) ----

  bool handleEnter({bool shift = false}) {
    final block = focusedBlock;
    final id = _focusedBlockId;
    if (block == null || id == null) return false;
    _materializeEphemeral();
    var sel = editing.selection;
    if (!sel.isValid) return false;
    if (!sel.isCollapsed) {
      // Table navigation leaves the landing cell selected (so typing
      // replaces it); Enter there is a pure row move — collapse, don't
      // delete.
      if (block.kind == BlockKind.table) {
        _select(TextSelection.collapsed(offset: sel.start));
        sel = editing.selection;
      } else {
        replaceRange(sel.start, sel.end, '');
        sel = editing.selection;
      }
    }
    final text = editing.text;
    final caret = sel.baseOffset;

    if (shift) {
      // Soft break; in tables a <br>.
      replaceRange(caret, caret,
          block.kind == BlockKind.table ? '<br>' : '\n');
      return true;
    }

    final lineStart = text.lastIndexOf('\n', caret - 1 < 0 ? 0 : caret - 1) + 1;
    final lineEndIdx = text.indexOf('\n', caret);
    final lineEnd = lineEndIdx < 0 ? text.length : lineEndIdx;
    final line = text.substring(lineStart, lineEnd);

    // Newline-committed conversions (paragraph blocks only).
    if (block.kind == BlockKind.paragraph) {
      final fence = _fenceLineRe.firstMatch(text);
      if (fence != null && !text.contains('\n')) {
        final open = text.trimRight();
        final marker = fence.group(1)!;
        _convertTo('$open\n\n${marker[0] * marker.length}', open.length + 1);
        return true;
      }
      if (text.trim() == r'$$') {
        _convertTo('\$\$\n\n\$\$', 3);
        return true;
      }
      if (!text.contains('\n') && _thematicLineRe.hasMatch(text)) {
        _splitInto([
          Block(kind: BlockKind.thematicBreak, source: text),
          Block(kind: BlockKind.paragraph, source: ''),
        ], focusIndex: 1, caret: 0, replacing: block);
        return true;
      }
      if (text.contains('\n') &&
          caret == text.length &&
          _setextLineRe.hasMatch(line) &&
          lineStart > 0) {
        _splitInto([
          Block(kind: BlockKind.heading, source: text),
          Block(kind: BlockKind.paragraph, source: ''),
        ], focusIndex: 1, caret: 0, replacing: block);
        return true;
      }
      if (_tableDelimLineRe.hasMatch(line) &&
          line.contains('-') &&
          lineStart > 0 &&
          text.substring(0, lineStart - 1).split('\n').last.contains('|')) {
        final cols = '|'.allMatches(line).length;
        final row = '|${'   |' * (cols - 1).clamp(1, 99)}';
        final newSource = '$text\n$row';
        _convertTo(newSource, newSource.length - row.length + 2);
        return true;
      }
    }

    switch (block.kind) {
      case BlockKind.fencedCode:
      case BlockKind.mathBlock:
      case BlockKind.html:
      case BlockKind.frontMatter:
      case BlockKind.indentedCode:
        // A just-typed opening line (live kind re-derivation converts
        // '```lang' / '$$' to fence/math before Enter arrives): complete the
        // block with an empty body and a closing fence, caret inside.
        if (!text.contains('\n') && caret == text.length) {
          if (block.kind == BlockKind.fencedCode) {
            final m = _fenceLineRe.firstMatch(text);
            if (m != null) {
              final marker = m.group(1)!;
              _convertTo('$text\n\n${marker[0] * marker.length}',
                  text.length + 1);
              return true;
            }
          }
          if (block.kind == BlockKind.mathBlock && text.trim() == r'$$') {
            _convertTo('\$\$\n\n\$\$', 3);
            return true;
          }
        }
        // Enter after the closing fence exits the block.
        if (caret == text.length &&
            block.kind == BlockKind.fencedCode &&
            block.fenceIsClosed) {
          _insertParagraphBelow(block);
          return true;
        }
        if (caret == text.length &&
            block.kind == BlockKind.mathBlock &&
            text.split('\n').length > 1 &&
            text.trimRight().endsWith(r'$$')) {
          _insertParagraphBelow(block);
          return true;
        }
        final indent = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
        replaceRange(caret, caret, '\n$indent');
        return true;

      case BlockKind.list:
        return _handleEnterInList(block, text, caret, lineStart, lineEnd);

      case BlockKind.blockquote:
        if (_emptyQuoteLineRe.hasMatch(line)) {
          // Empty `>` line: exit the quote.
          final withoutLine = (lineStart > 0
                  ? text.substring(0, lineStart - 1)
                  : '') +
              text.substring(lineEnd);
          _splitInto([
            if (withoutLine.isNotEmpty)
              Block(kind: BlockKind.blockquote, source: withoutLine),
            Block(kind: BlockKind.paragraph, source: ''),
          ], focusIndex: withoutLine.isNotEmpty ? 1 : 0, caret: 0,
              replacing: block);
          return true;
        }
        replaceRange(caret, caret, '\n> ');
        return true;

      case BlockKind.table:
        // Enter = same column next row (append row on last).
        return _tableEnter(block, text, caret);

      case BlockKind.heading:
        if (caret == text.length) {
          _insertParagraphBelow(block);
          return true;
        }
        _splitAtCaret(block, text, caret);
        return true;

      case BlockKind.paragraph:
      case BlockKind.thematicBreak:
        _splitAtCaret(block, text, caret);
        return true;
    }
  }

  void _insertParagraphBelow(Block block) {
    final i = docCtrl.doc.indexOfBlock(block.id);
    if (i < 0) return;
    final p = Block(kind: BlockKind.paragraph, source: '');
    docCtrl.spliceBlocks(
      index: i + 1, before: [], after: [p], kind: EditKind.split,
      caretBefore: _snap(editing.selection),
      caretAfter: CaretSnapshot(p.id, 0),
    );
    focusBlock(p.id);
  }

  void _splitAtCaret(Block block, String text, int caret) {
    final left = text.substring(0, caret);
    final right = text.substring(caret);
    final leftBlock = Block(
      id: block.id,
      kind: deriveSingleKind(left) ?? BlockKind.paragraph,
      source: left,
      blankLinesBefore: block.blankLinesBefore,
    );
    final rightBlock = Block(
      kind: deriveSingleKind(right) ?? BlockKind.paragraph,
      source: right,
    );
    _splitInto([leftBlock, rightBlock],
        focusIndex: 1, caret: 0, replacing: block);
  }

  void _splitInto(List<Block> parts,
      {required int focusIndex, required int caret, required Block replacing}) {
    final i = docCtrl.doc.indexOfBlock(replacing.id);
    if (i < 0 || parts.isEmpty) return;
    docCtrl.spliceBlocks(
      index: i, before: [replacing], after: parts, kind: EditKind.split,
      caretBefore: _snap(editing.selection),
      caretAfter: CaretSnapshot(parts[focusIndex].id, caret),
    );
    focusBlock(parts[focusIndex].id, offset: caret);
  }

  bool _handleEnterInList(
      Block block, String text, int caret, int lineStart, int lineEnd) {
    final line = text.substring(lineStart, lineEnd);
    final m = _listItemLineRe.firstMatch(line);
    if (m == null) {
      // Continuation line: plain newline with indent.
      final indent = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
      replaceRange(caret, caret, '\n$indent');
      return true;
    }
    final indent = m.group(1)!;
    final content = line.substring(m.end);
    if (content.trim().isEmpty && caret >= lineStart + m.end) {
      if (indent.length >= 2) {
        // Outdent one level.
        final newLine = line.substring(2);
        replaceRange(lineStart, lineEnd, newLine,
            caretAt: caret - 2, kind: EditKind.blockOp);
        return true;
      }
      // Marker-only first-level item: exit the list.
      final beforeLines =
          lineStart > 0 ? text.substring(0, lineStart - 1) : '';
      final afterLines = lineEnd < text.length ? text.substring(lineEnd + 1) : '';
      _splitInto([
        if (beforeLines.isNotEmpty)
          Block(kind: BlockKind.list, source: beforeLines),
        Block(kind: BlockKind.paragraph, source: ''),
        if (afterLines.isNotEmpty)
          Block(kind: BlockKind.list, source: afterLines),
      ], focusIndex: beforeLines.isNotEmpty ? 1 : 0, caret: 0,
          replacing: block);
      return true;
    }
    // Split the item at the caret; tail becomes the new item's content.
    final bullet = m.group(2)!;
    final task = m.group(4) != null;
    String nextMarker;
    final ordered = RegExp(r'^(\d{1,9})([.)])$').firstMatch(bullet);
    if (ordered != null) {
      nextMarker =
          '${int.parse(ordered.group(1)!) + 1}${ordered.group(2)!} ';
    } else {
      nextMarker = '$bullet ';
    }
    if (task) nextMarker = '$nextMarker[ ] ';
    final insert = '\n$indent$nextMarker';
    replaceRange(caret, caret, insert, kind: EditKind.split);
    return true;
  }

  bool _tableEnter(Block block, String text, int caret) {
    final lines = text.split('\n');
    var lineStart = 0;
    var row = 0;
    for (; row < lines.length; row++) {
      final end = lineStart + lines[row].length;
      if (caret <= end) break;
      lineStart = end + 1;
    }
    final col = _pipeCountBefore(lines[row.clamp(0, lines.length - 1)],
        caret - lineStart);
    var targetRow = row + 1;
    if (targetRow == 1) targetRow = 2; // skip the delimiter row
    if (targetRow >= lines.length) {
      final cols = '|'.allMatches(lines[0]).length;
      final newRow = '|${'   |' * (cols - 1).clamp(1, 99)}';
      final newText = '$text\n$newRow';
      _convertTo(newText, newText.length - newRow.length + 2);
      return true;
    }
    final target = _cellRange(lines, targetRow, col);
    _select(TextSelection(baseOffset: target.$1, extentOffset: target.$2));
    return true;
  }

  // ---- Tab in lists and tables ----

  bool handleTab({bool shift = false}) {
    final block = focusedBlock;
    if (block == null) return false;
    final text = editing.text;
    final caret = editing.selection.baseOffset;
    if (block.kind == BlockKind.list) {
      final lineStart =
          text.lastIndexOf('\n', caret - 1 < 0 ? 0 : caret - 1) + 1;
      if (shift) {
        if (text.startsWith('  ', lineStart)) {
          replaceRange(lineStart, lineStart + 2, '',
              caretAt: (caret - 2).clamp(0, text.length), kind: EditKind.blockOp);
        }
      } else {
        replaceRange(lineStart, lineStart, '  ',
            caretAt: caret + 2, kind: EditKind.blockOp);
      }
      return true;
    }
    if (block.kind == BlockKind.table) {
      return _tableTab(text, caret, back: shift);
    }
    return false;
  }

  bool _tableTab(String text, int caret, {required bool back}) {
    final lines = text.split('\n');
    var lineStart = 0;
    var row = 0;
    for (; row < lines.length; row++) {
      final end = lineStart + lines[row].length;
      if (caret <= end) break;
      lineStart = end + 1;
    }
    var col = _pipeCountBefore(lines[row.clamp(0, lines.length - 1)],
        caret - lineStart);
    final cols = _cellCount(lines[0]);
    if (!back) {
      col++;
      if (col >= cols) {
        col = 0;
        row++;
        if (row == 1) row = 2;
        if (row >= lines.length) {
          final newRow = '|${'   |' * (cols).clamp(1, 99)}';
          final newText = '$text\n$newRow';
          _convertTo(newText, newText.length - newRow.length + 2);
          return true;
        }
      }
    } else {
      col--;
      if (col < 0) {
        row--;
        if (row == 1) row = 0;
        if (row < 0) return true;
        col = cols - 1;
      }
    }
    final r = _cellRange(lines, row, col);
    _select(TextSelection(baseOffset: r.$1, extentOffset: r.$2));
    return true;
  }

  int _pipeCountBefore(String line, int localOffset) {
    var pipes = 0;
    final upTo = localOffset.clamp(0, line.length);
    for (var i = 0; i < upTo; i++) {
      if (line[i] == '|' && (i == 0 || line[i - 1] != r'\')) pipes++;
    }
    final leading = line.trimLeft().startsWith('|') ? 1 : 0;
    return (pipes - leading).clamp(0, 999);
  }

  int _cellCount(String headerLine) {
    var pipes = 0;
    for (var i = 0; i < headerLine.length; i++) {
      if (headerLine[i] == '|' && (i == 0 || headerLine[i - 1] != r'\')) {
        pipes++;
      }
    }
    final t = headerLine.trim();
    var cells = pipes - 1;
    if (!t.startsWith('|')) cells++;
    if (!t.endsWith('|')) cells++;
    return cells.clamp(1, 999);
  }

  /// (start, end) source offsets of the trimmed content of cell [row]/[col].
  (int, int) _cellRange(List<String> lines, int row, int col) {
    var base = 0;
    for (var i = 0; i < row; i++) {
      base += lines[i].length + 1;
    }
    final line = lines[row];
    final bounds = <int>[];
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '|' && (i == 0 || line[i - 1] != r'\')) bounds.add(i);
    }
    final startsWithPipe = line.trimLeft().startsWith('|');
    var cellStart = 0;
    var cellEnd = line.length;
    var idx = startsWithPipe ? col : col - 1;
    // A short row (fewer cells than the header) clamps to its last cell —
    // never select the whole row with its pipes.
    if (idx >= bounds.length) idx = bounds.length - 1;
    if (idx >= 0 && idx < bounds.length) cellStart = bounds[idx] + 1;
    if (idx + 1 < bounds.length) cellEnd = bounds[idx + 1];
    // Trim whitespace inside the cell.
    while (cellStart < cellEnd && line[cellStart] == ' ') {
      cellStart++;
    }
    while (cellEnd > cellStart && line[cellEnd - 1] == ' ') {
      cellEnd--;
    }
    return (base + cellStart, base + cellEnd);
  }

  void _select(TextSelection sel) {
    final block = focusedBlock;
    if (block == null) return;
    _setEditingValue(block,
        editing.value.copyWith(selection: _clampSelection(sel, editing.text.length)));
    docCtrl.sealUndoGroup();
  }

  // ---- Backspace at offset 0 (§2.2): demote, then merge ----

  bool handleBackspaceAtStart() {
    final block = focusedBlock;
    final id = _focusedBlockId;
    if (block == null || id == null) return false;
    final sel = editing.selection;
    if (!sel.isCollapsed || sel.baseOffset != 0) return false;
    _materializeEphemeral();
    final text = editing.text;

    // Stage 1: demote own markers.
    switch (block.kind) {
      case BlockKind.heading:
        final demoted = block.isSetextHeading
            ? text.split('\n').sublist(0, text.split('\n').length - 1).join('\n')
            : text.replaceFirst(RegExp(r'^ {0,3}#{1,6}[ \t]*'), '');
        _convertTo(demoted, 0);
        return true;
      case BlockKind.blockquote:
        final demoted = text
            .split('\n')
            .map((l) => l.replaceFirst(RegExp(r'^ {0,3}> ?'), ''))
            .join('\n');
        _convertTo(demoted, 0);
        return true;
      case BlockKind.list:
        final lines = text.split('\n');
        final m = _listItemLineRe.firstMatch(lines.first);
        if (m != null) {
          if (m.group(1)!.length >= 2) {
            _convertTo(text.substring(2), 0);
            return true;
          }
          final demotedFirst = lines.first.substring(m.end);
          if (lines.length == 1) {
            _convertTo(demotedFirst, 0);
          } else {
            final rest = lines.sublist(1).join('\n');
            _splitInto([
              Block(kind: BlockKind.paragraph, source: demotedFirst),
              Block(kind: deriveSingleKind(rest) ?? BlockKind.list, source: rest),
            ], focusIndex: 0, caret: 0, replacing: block);
          }
          return true;
        }
      case BlockKind.fencedCode:
      case BlockKind.mathBlock:
        if (block.codeBody.trim().isEmpty) {
          _convertTo('', 0);
          return true;
        }
      default:
        break;
    }

    // Stage 2 applies only to blocks with no structure of their own
    // (§2.2: "current block is a plain paragraph or thematicBreak").
    // A table/fence/html block must never be glued into its neighbour —
    // Backspace at its start just moves focus up.
    if (block.kind != BlockKind.paragraph &&
        block.kind != BlockKind.thematicBreak) {
      final idx = docCtrl.doc.indexOfBlock(id);
      if (idx > 0) {
        final prevBlock = docCtrl.doc.blocks[idx - 1];
        focusBlock(prevBlock.id, offset: prevBlock.source.length);
      }
      return true;
    }

    // Backspace at the start of an HR deletes the HR itself.
    if (block.kind == BlockKind.thematicBreak) {
      final idx = docCtrl.doc.indexOfBlock(id);
      if (idx < 0) return true;
      docCtrl.spliceBlocks(
        index: idx, before: [block], after: [], kind: EditKind.merge,
        caretBefore: _snap(sel),
      );
      if (idx > 0) {
        final prevBlock = docCtrl.doc.blocks[idx - 1];
        focusBlock(prevBlock.id, offset: prevBlock.source.length);
      } else if (docCtrl.doc.blocks.isNotEmpty) {
        focusBlock(docCtrl.doc.blocks.first.id);
      }
      return true;
    }

    // Stage 2: merge with the previous block.
    final i = docCtrl.doc.indexOfBlock(id);
    if (i <= 0) return i < 0;
    final prev = docCtrl.doc.blocks[i - 1];

    const opaque = {
      BlockKind.fencedCode,
      BlockKind.indentedCode,
      BlockKind.mathBlock,
      BlockKind.table,
      BlockKind.html,
      BlockKind.frontMatter,
    };

    if (prev.kind == BlockKind.thematicBreak && text.isNotEmpty) {
      // Backspace into an HR deletes the HR itself.
      docCtrl.spliceBlocks(
        index: i - 1, before: [prev, block], after: [block],
        kind: EditKind.merge,
        caretBefore: _snap(sel), caretAfter: CaretSnapshot(id, 0),
      );
      focusBlock(id, offset: 0);
      return true;
    }
    if (opaque.contains(prev.kind)) {
      if (text.isEmpty) {
        docCtrl.spliceBlocks(
          index: i - 1, before: [prev, block], after: [prev],
          kind: EditKind.merge,
          caretBefore: _snap(sel),
          caretAfter: CaretSnapshot(prev.id, prev.source.length),
        );
      }
      focusBlock(prev.id, offset: prev.source.length);
      return true;
    }

    // Text-bearing previous block: concatenate sources.
    final merged = prev.source + text;
    final mergedBlock = Block(
      id: prev.id,
      kind: deriveSingleKind(merged) ?? prev.kind,
      source: merged,
      blankLinesBefore: prev.blankLinesBefore,
    );
    docCtrl.spliceBlocks(
      index: i - 1, before: [prev, block], after: [mergedBlock],
      kind: EditKind.merge,
      caretBefore: _snap(sel),
      caretAfter: CaretSnapshot(prev.id, prev.source.length),
    );
    focusBlock(prev.id, offset: prev.source.length);
    return true;
  }

  /// Forward-delete at end of block: §2.2 stage 2 with roles swapped —
  /// the next block merges into this one, opaque blocks never merge.
  bool handleDeleteAtEnd() {
    final block = focusedBlock;
    final id = _focusedBlockId;
    if (block == null || id == null) return false;
    final sel = editing.selection;
    if (!sel.isCollapsed || sel.baseOffset != editing.text.length) return false;
    final i = docCtrl.doc.indexOfBlock(id);
    if (i < 0 || i >= docCtrl.doc.blocks.length - 1) return false;
    _materializeEphemeral();
    final next = docCtrl.doc.blocks[i + 1];
    final caret = editing.text.length;

    // Forward-delete before an HR removes the HR itself.
    if (next.kind == BlockKind.thematicBreak) {
      docCtrl.spliceBlocks(
        index: i + 1, before: [next], after: [], kind: EditKind.merge,
        caretBefore: _snap(sel), caretAfter: CaretSnapshot(id, caret),
      );
      return true;
    }

    const opaque = {
      BlockKind.fencedCode,
      BlockKind.indentedCode,
      BlockKind.mathBlock,
      BlockKind.table,
      BlockKind.html,
      BlockKind.frontMatter,
    };
    if (opaque.contains(next.kind)) {
      // Never glue an opaque block's source into prose. An empty current
      // paragraph is simply removed, focus moving into the opaque block.
      if (editing.text.isEmpty) {
        docCtrl.spliceBlocks(
          index: i, before: [block], after: [], kind: EditKind.merge,
          caretBefore: _snap(sel), caretAfter: CaretSnapshot(next.id, 0),
        );
        focusBlock(next.id, offset: 0);
      }
      return true;
    }

    // Lists/quotes surrender their first line's content; the rest stays.
    if (next.kind == BlockKind.list || next.kind == BlockKind.blockquote) {
      final lines = next.source.split('\n');
      final first = next.kind == BlockKind.list
          ? lines.first.replaceFirst(_listItemLineRe, '')
          : lines.first.replaceFirst(RegExp(r'^ {0,3}(?:> ?)+'), '');
      final rest = lines.sublist(1).join('\n');
      final merged = editing.text + first;
      docCtrl.spliceBlocks(
        index: i,
        before: [block, next],
        after: [
          Block(
            id: id,
            kind: deriveSingleKind(merged) ?? block.kind,
            source: merged,
            blankLinesBefore: block.blankLinesBefore,
          ),
          if (rest.isNotEmpty)
            Block(kind: deriveSingleKind(rest) ?? next.kind, source: rest),
        ],
        kind: EditKind.merge,
        caretBefore: _snap(sel),
        caretAfter: CaretSnapshot(id, caret),
      );
      focusBlock(id, offset: caret);
      return true;
    }

    // Paragraphs merge verbatim; headings surrender their text (their
    // markers would otherwise appear as literal `#`s mid-paragraph).
    final nextText =
        next.kind == BlockKind.heading ? next.headingText : next.source;
    final merged = editing.text + nextText;
    final mergedBlock = Block(
      id: id,
      kind: deriveSingleKind(merged) ?? block.kind,
      source: merged,
      blankLinesBefore: block.blankLinesBefore,
    );
    docCtrl.spliceBlocks(
      index: i, before: [block, next], after: [mergedBlock],
      kind: EditKind.merge,
      caretBefore: _snap(sel), caretAfter: CaretSnapshot(id, caret),
    );
    focusBlock(id, offset: caret);
    return true;
  }

  // ---- Vertical caret transfer (§3.4) ----

  bool moveVertical({required bool up}) {
    final id = _focusedBlockId;
    if (id == null) return false;
    final i = docCtrl.doc.indexOfBlock(id);
    if (i < 0) return false;
    final targetIndex = up ? i - 1 : i + 1;
    if (targetIndex < 0) return false;
    if (targetIndex >= docCtrl.doc.blocks.length) {
      if (!up) focusTail();
      return !up;
    }
    final target = docCtrl.doc.blocks[targetIndex];
    final x = goalX ?? _caretX();
    goalX = x;
    final offset = _offsetForX(target, x, lastLine: up);
    focusBlock(target.id, offset: offset);
    goalX = x; // focusBlock's caret-move handling cleared it
    return true;
  }

  TextPainter _layoutFor(String text, BlockKind kind, {int headingLevel = 1}) {
    final span = text.isEmpty
        ? TextSpan(text: '', style: _theme.bodyStyle)
        : _renderer.buildEditingSpan(text, kind, headingLevel: headingLevel);
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: contentWidth);
    return tp;
  }

  double _caretX() {
    final block = focusedBlock;
    if (block == null) return 0;
    final tp = _layoutFor(editing.text, block.kind,
        headingLevel: block.headingLevel);
    final pos = tp.getOffsetForCaret(
        TextPosition(offset: editing.selection.baseOffset), Rect.zero);
    tp.dispose();
    return pos.dx;
  }

  /// Whether the caret is on the first/last visual line of the focused field.
  bool caretOnEdgeLine({required bool first}) {
    final block = focusedBlock;
    if (block == null) return true;
    final tp = _layoutFor(editing.text, block.kind,
        headingLevel: block.headingLevel);
    final lines = tp.computeLineMetrics();
    if (lines.length <= 1) {
      tp.dispose();
      return true;
    }
    final caretY = tp
        .getOffsetForCaret(
            TextPosition(offset: editing.selection.baseOffset), Rect.zero)
        .dy;
    var acc = 0.0;
    var lineIndex = 0;
    for (var li = 0; li < lines.length; li++) {
      if (caretY < acc + lines[li].height - 0.5) {
        lineIndex = li;
        break;
      }
      acc += lines[li].height;
      lineIndex = li;
    }
    tp.dispose();
    return first ? lineIndex == 0 : lineIndex == lines.length - 1;
  }

  int _offsetForX(Block target, double x, {required bool lastLine}) {
    final tp = _layoutFor(target.source, target.kind,
        headingLevel: target.headingLevel);
    final lines = tp.computeLineMetrics();
    double y = 0;
    if (lastLine && lines.isNotEmpty) {
      for (var li = 0; li < lines.length - 1; li++) {
        y += lines[li].height;
      }
      y += lines.last.height / 2;
    } else if (lines.isNotEmpty) {
      y = lines.first.height / 2;
    }
    final offset = tp.getPositionForOffset(Offset(x, y)).offset;
    tp.dispose();
    return offset;
  }

  // ---- Formatting (§6) ----

  static final _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  void toggleInline(String m) {
    final block = focusedBlock;
    if (block == null || _focusedBlockId == null) return;
    final text = editing.text;
    var sel = editing.selection;
    if (!sel.isValid) return;
    final l = m.length;

    if (sel.isCollapsed) {
      final w = _wordRangeAt(text, sel.baseOffset);
      if (w == null) {
        final at = sel.baseOffset;
        // Toggle-off an empty pair the caret sits inside.
        if (at >= l &&
            at + l <= text.length &&
            text.substring(at - l, at) == m &&
            text.substring(at, at + l) == m) {
          replaceRange(at - l, at + l, '', caretAt: at - l);
          return;
        }
        replaceRange(at, at, m + m, caretAt: at + l);
        return;
      }
      sel = TextSelection(baseOffset: w.$1, extentOffset: w.$2);
    }

    var a = sel.start;
    var b = sel.end;
    while (a < b && text[a] == ' ') {
      a++;
    }
    while (b > a && text[b - 1] == ' ') {
      b--;
    }
    bool has(int at, String s) =>
        at >= 0 && at + s.length <= text.length &&
        text.substring(at, at + s.length) == s;

    bool contextOk() {
      if (m != '*') return true;
      final beforeOk = a - l - 1 < 0 || text[a - l - 1] != '*';
      final afterOk = b + l >= text.length || text[b + l] != '*';
      return beforeOk && afterOk;
    }

    if (has(a - l, m) && has(b, m) && contextOk()) {
      // Unwrap, markers just outside the selection.
      final newText = text.replaceRange(b, b + l, '').replaceRange(a - l, a, '');
      _replaceAllText(newText,
          TextSelection(baseOffset: a - l, extentOffset: b - l));
      return;
    }
    if (b - a >= 2 * l && has(a, m) && has(b - l, m)) {
      // Unwrap, markers just inside.
      final newText =
          text.replaceRange(b - l, b, '').replaceRange(a, a + l, '');
      _replaceAllText(newText, TextSelection(baseOffset: a, extentOffset: b - 2 * l));
      return;
    }
    final newText = text.replaceRange(b, b, m).replaceRange(a, a, m);
    _replaceAllText(newText, TextSelection(baseOffset: a + l, extentOffset: b + l));
  }

  (int, int)? _wordRangeAt(String text, int at) {
    var a = at;
    var b = at;
    while (a > 0 && _wordChar.hasMatch(text[a - 1])) {
      a--;
    }
    while (b < text.length && _wordChar.hasMatch(text[b])) {
      b++;
    }
    return b > a ? (a, b) : null;
  }

  void _replaceAllText(String newText, TextSelection sel) {
    final id = _focusedBlockId;
    final block = focusedBlock;
    if (id == null || block == null) return;
    _materializeEphemeral();
    final before = _snap(editing.selection);
    _setEditingValue(block, TextEditingValue(
        text: newText, selection: _clampSelection(sel, newText.length)));
    docCtrl.changeBlockSource(id, newText,
        kind: EditKind.blockOp, caretBefore: before, caretAfter: _snap(sel));
  }

  void toggleBold() => toggleInline('**');
  void toggleItalic() => toggleInline('*');
  void toggleCode() => toggleInline('`');
  void toggleStrikethrough() => toggleInline('~~');

  void insertLink() {
    final text = editing.text;
    final sel = editing.selection;
    if (!sel.isValid || focusedBlock == null) return;
    if (sel.isCollapsed) {
      replaceRange(sel.baseOffset, sel.baseOffset, '[]()',
          caretAt: sel.baseOffset + 1);
      return;
    }
    final selected = text.substring(sel.start, sel.end);
    if (RegExp(r'^https?://\S+$').hasMatch(selected)) {
      final replacement = '[]($selected)';
      replaceRange(sel.start, sel.end, replacement, caretAt: sel.start + 1);
    } else {
      final replacement = '[$selected]()';
      replaceRange(sel.start, sel.end, replacement,
          caretAt: sel.start + replacement.length - 1);
    }
  }

  /// Inserts `![alt](url)` at the caret of the focused block, or as a new
  /// standalone image paragraph after the focused block when none/opaque.
  void insertImage(String url, {String alt = ''}) {
    final markdown = '![$alt]($url)';
    final block = focusedBlock;
    const inlineable = {
      BlockKind.paragraph,
      BlockKind.heading,
      BlockKind.blockquote,
      BlockKind.list,
    };
    if (block != null && inlineable.contains(block.kind)) {
      final sel = editing.selection;
      if (sel.isValid) {
        replaceRange(sel.start, sel.end, markdown, kind: EditKind.paste);
        return;
      }
    }
    _insertBlocksAfterFocused(
        [Block(kind: BlockKind.paragraph, source: markdown)],
        focusOffset: 0);
  }

  /// Cmd+1..6 sets the heading level; Cmd+0 (or the current level again)
  /// makes it a paragraph. Paragraph/heading blocks only.
  void setHeadingLevel(int n) {
    final block = focusedBlock;
    if (block == null) return;
    if (block.kind != BlockKind.paragraph && block.kind != BlockKind.heading) {
      return;
    }
    var text = editing.text;
    final caret = editing.selection.baseOffset;
    var stripped = text;
    if (block.kind == BlockKind.heading && block.isSetextHeading) {
      final lines = text.split('\n');
      stripped = lines.sublist(0, lines.length - 1).join('\n');
    } else {
      stripped = text.replaceFirst(RegExp(r'^ {0,3}#{1,6}[ \t]*'), '');
    }
    final currentLevel =
        block.kind == BlockKind.heading ? block.headingLevel : 0;
    final targetLevel = (n == 0 || n == currentLevel) ? 0 : n;
    final prefix = targetLevel == 0 ? '' : '${'#' * targetLevel} ';
    final newText = prefix + stripped;
    final delta = newText.length - text.length;
    _convertTo(newText, (caret + delta).clamp(prefix.length, newText.length));
  }

  /// Toggles `[ ]`/`[x]` on a task-list line — works on RENDERED blocks
  /// (checkbox click) without stealing focus.
  void toggleTask(String blockId, int lineIndex) {
    final block = docCtrl.doc.blockById(blockId);
    if (block == null) return;
    final lines = block.source.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final line = lines[lineIndex];
    final m = RegExp(r'^(\s*(?:[-*+]|\d{1,9}[.)])\s+\[)([ xX])(\])').firstMatch(line);
    if (m == null) return;
    final checked = m.group(2) != ' ';
    lines[lineIndex] =
        line.replaceRange(m.start + m.group(1)!.length, m.end - 1, checked ? ' ' : 'x');
    docCtrl.changeBlockSource(blockId, lines.join('\n'),
        kind: EditKind.blockOp);
    if (blockId == _focusedBlockId) {
      final b = docCtrl.doc.blockById(blockId);
      if (b != null) {
        _setEditingValue(b, TextEditingValue(
            text: b.source,
            selection: _clampSelection(editing.selection, b.source.length)));
      }
    }
  }

  // ---- Selection commands (Edit > Selection) ----

  (int, int) _lineBoundsAtCaret() {
    final text = editing.text;
    final caret = editing.selection.baseOffset.clamp(0, text.length);
    final start = text.lastIndexOf('\n', caret - 1 < 0 ? 0 : caret - 1) + 1;
    final endIdx = text.indexOf('\n', caret);
    return (start, endIdx < 0 ? text.length : endIdx);
  }

  void selectWord() {
    if (focusedBlock == null) return;
    final w = _wordRangeAt(editing.text, editing.selection.baseOffset);
    if (w != null) {
      _select(TextSelection(baseOffset: w.$1, extentOffset: w.$2));
    }
  }

  void selectLine() {
    if (focusedBlock == null) return;
    final (a, b) = _lineBoundsAtCaret();
    _select(TextSelection(baseOffset: a, extentOffset: b));
  }

  void selectBlock() {
    if (focusedBlock == null) return;
    _select(TextSelection(
        baseOffset: 0, extentOffset: editing.text.length));
  }

  /// Innermost styled inline node (emphasis/code/link…) around the caret.
  (int, int)? _styledScopeAtCaret() {
    final caret = editing.selection.baseOffset;
    (int, int)? best;
    void walk(List<InlineNode> nodes) {
      for (final n in nodes) {
        if (caret < n.start || caret > n.end) continue;
        if (n is! TextNode) best = (n.start, n.end);
        if (n is EmphasisNode) walk(n.children);
        if (n is LinkNode) walk(n.children);
      }
    }

    walk(tokenizeInline(editing.text));
    return best;
  }

  void selectStyledScope() {
    if (focusedBlock == null) return;
    final scope = _styledScopeAtCaret();
    if (scope != null) {
      _select(TextSelection(baseOffset: scope.$1, extentOffset: scope.$2));
    }
  }

  void jumpToLineStart() {
    if (focusedBlock == null) return;
    _select(TextSelection.collapsed(offset: _lineBoundsAtCaret().$1));
  }

  void jumpToLineEnd() {
    if (focusedBlock == null) return;
    _select(TextSelection.collapsed(offset: _lineBoundsAtCaret().$2));
  }

  void jumpToTop() {
    final first = docCtrl.doc.blocks.first;
    focusBlock(first.id, offset: 0);
  }

  void jumpToBottom() {
    final last = docCtrl.doc.blocks.last;
    focusBlock(last.id, offset: last.source.length);
  }

  /// Re-reveals the caret (scrolls the focused block into view).
  void jumpToSelection() {
    final id = _focusedBlockId;
    if (id == null) return;
    focusBlock(id, selection: editing.selection);
  }

  // ---- Delete Range (Edit > Delete Range) ----

  void deleteWord() {
    if (focusedBlock == null) return;
    final w = _wordRangeAt(editing.text, editing.selection.baseOffset);
    if (w != null) replaceRange(w.$1, w.$2, '', kind: EditKind.deleteBack);
  }

  void deleteLine() {
    final block = focusedBlock;
    if (block == null) return;
    var (a, b) = _lineBoundsAtCaret();
    // Take the trailing newline so the line disappears entirely.
    if (b < editing.text.length) b++;
    if (a == 0 && b >= editing.text.length) {
      deleteBlock();
      return;
    }
    replaceRange(a, b, '', kind: EditKind.deleteBack);
  }

  void deleteStyledScope() {
    if (focusedBlock == null) return;
    final scope = _styledScopeAtCaret();
    if (scope != null) {
      replaceRange(scope.$1, scope.$2, '', kind: EditKind.deleteBack);
    }
  }

  /// Deletes the whole focused block.
  void deleteBlock() {
    final id = _focusedBlockId;
    final block = focusedBlock;
    if (id == null || block == null) return;
    final i = docCtrl.doc.indexOfBlock(id);
    if (i < 0) return;
    docCtrl.spliceBlocks(
      index: i, before: [block], after: [], kind: EditKind.deleteBack,
      caretBefore: _snap(editing.selection),
    );
    final blocks = docCtrl.doc.blocks;
    final target = blocks[(i - 1).clamp(0, blocks.length - 1)];
    focusBlock(target.id, offset: target.source.length);
  }

  // ---- Code Tools (Paragraph > Code Tools) ----

  /// Copies a code block's body without its fences.
  void copyCodeContent() {
    final block = focusedBlock;
    if (block == null) return;
    if (block.kind != BlockKind.fencedCode &&
        block.kind != BlockKind.indentedCode) {
      return;
    }
    Clipboard.setData(ClipboardData(text: block.codeBody));
  }

  /// Languages where whitespace is syntax — never reindent those.
  static const _indentSensitive = {
    'python', 'py', 'yaml', 'yml', 'markdown', 'md', 'haskell', 'makefile',
  };

  /// Brace/bracket-depth reindent (2 spaces) of the focused fenced block.
  void autoIndentCode() {
    final block = focusedBlock;
    final id = _focusedBlockId;
    if (block == null || id == null || block.kind != BlockKind.fencedCode) {
      return;
    }
    final lang = block.fenceLanguage?.toLowerCase();
    if (lang != null && _indentSensitive.contains(lang)) return;
    final lines = editing.text.split('\n');
    if (lines.length < 3) return;
    var depth = 0;
    for (var i = 1; i < lines.length - 1; i++) {
      final content = lines[i].trimLeft();
      final leadingClosers =
          RegExp(r'^[)\]}]+').firstMatch(content)?.group(0)?.length ?? 0;
      final lineDepth = (depth - leadingClosers).clamp(0, 99);
      lines[i] = content.isEmpty ? '' : '${'  ' * lineDepth}$content';
      for (final ch in content.split('')) {
        if ('([{'.contains(ch)) depth++;
        if (')]}'.contains(ch)) depth = (depth - 1).clamp(0, 99);
      }
    }
    final newText = lines.join('\n');
    if (newText == editing.text) return;
    final caret = editing.selection.baseOffset.clamp(0, newText.length);
    _replaceAllText(newText,
        TextSelection.collapsed(offset: caret.clamp(0, newText.length)));
  }

  // ---- Copy As / Paste As (Edit menu) ----

  /// The markdown to act on: the focused selection, the focused block, or
  /// the whole document.
  String _copySource() {
    final block = focusedBlock;
    if (block != null) {
      final sel = editing.selection;
      if (sel.isValid && !sel.isCollapsed) {
        return editing.text.substring(sel.start, sel.end);
      }
      return editing.text;
    }
    return docCtrl.serialize();
  }

  /// Copy as Markdown: the raw source, exactly as stored.
  void copyAsMarkdown() =>
      Clipboard.setData(ClipboardData(text: _copySource()));

  /// Copy as Plain Text: markers stripped, content kept.
  void copyAsPlainText() {
    final src = _copySource();
    final plain =
        src.split('\n').map(plainTextOfInline).join('\n');
    Clipboard.setData(ClipboardData(text: plain));
  }

  /// Copy as HTML Code: the selection converted through the markdown
  /// pipeline (unstyled HTML — theme styling never travels with it).
  void copyAsHtml() {
    final html = md.markdownToHtml(_copySource(),
        extensionSet: md.ExtensionSet.gitHubFlavored);
    Clipboard.setData(ClipboardData(text: html.trimRight()));
  }

  static final _markdownSpecials = RegExp(r'[\\`*_\[\]<>|~#]');

  /// Paste as Plain Text: clipboard content inserted with markdown special
  /// characters escaped, so it reads literally instead of becoming syntax.
  Future<void> pasteAsPlainText() async {
    final block = focusedBlock;
    if (block == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final escaped = text.replaceAllMapped(
        _markdownSpecials, (m) => '\\${m.group(0)}');
    final sel = editing.selection;
    if (!sel.isValid) return;
    replaceRange(sel.start, sel.end, escaped, kind: EditKind.paste);
  }

  // ---- Paragraph-menu commands (block conversions) ----

  static final _quotePrefixRe = RegExp(r'^ {0,3}> ?');
  static final _anyListMarkerRe =
      RegExp(r'^(\s*)(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?');

  /// One step up the heading ladder: paragraph → H6 → … → H1.
  void increaseHeadingLevel() {
    final block = focusedBlock;
    if (block == null) return;
    final level = block.kind == BlockKind.heading ? block.headingLevel : 7;
    if (level <= 1) return;
    setHeadingLevel(level - 1);
  }

  /// One step down the ladder: H1 → … → H6 → paragraph.
  void decreaseHeadingLevel() {
    final block = focusedBlock;
    if (block == null || block.kind != BlockKind.heading) return;
    final level = block.headingLevel;
    setHeadingLevel(level >= 6 ? 0 : level + 1);
  }

  String _stripBlockMarkers(String source) => source
      .split('\n')
      .map((l) =>
          l.replaceFirst(_quotePrefixRe, '').replaceFirst(_anyListMarkerRe, ''))
      .join('\n');

  /// Toggles the focused block to/from a quote.
  void convertToQuote() {
    final block = focusedBlock;
    if (block == null) return;
    if (block.kind == BlockKind.blockquote) {
      _convertTo(_stripBlockMarkers(editing.text), 0);
      return;
    }
    final quoted =
        editing.text.split('\n').map((l) => '> $l').join('\n');
    _convertTo(quoted, quoted.length);
  }

  void _convertToList(String Function(int index) marker,
      {required bool Function(Block) isAlready}) {
    final block = focusedBlock;
    if (block == null) return;
    const convertible = {
      BlockKind.paragraph,
      BlockKind.heading,
      BlockKind.blockquote,
      BlockKind.list,
    };
    if (!convertible.contains(block.kind)) return;
    if (isAlready(block)) {
      _convertTo(_stripBlockMarkers(editing.text), 0);
      return;
    }
    final stripped = _stripBlockMarkers(
        block.kind == BlockKind.heading ? block.headingText : editing.text);
    final lines = stripped.split('\n');
    final converted = [
      for (var i = 0; i < lines.length; i++) '${marker(i)}${lines[i]}',
    ].join('\n');
    _convertTo(converted, converted.length);
  }

  void convertToUnorderedList() => _convertToList((_) => '- ',
      isAlready: (b) => b.kind == BlockKind.list && !b.isOrderedList &&
          !b.hasTaskItems);

  void convertToOrderedList() => _convertToList((i) => '${i + 1}. ',
      isAlready: (b) => b.kind == BlockKind.list && b.isOrderedList);

  void convertToTaskList() => _convertToList((_) => '- [ ] ',
      isAlready: (b) => b.kind == BlockKind.list && b.hasTaskItems);

  /// Toggles the focused block to/from a fenced code block.
  void convertToCodeFence() {
    final block = focusedBlock;
    if (block == null) return;
    if (block.kind == BlockKind.fencedCode) {
      final body = block.codeBody;
      _convertTo(body, 0);
      return;
    }
    final newSource = '```\n${editing.text}\n```';
    _convertTo(newSource, 4); // caret at start of the body
  }

  /// Toggles the focused block to/from a math block.
  void convertToMathBlock() {
    final block = focusedBlock;
    if (block == null) return;
    if (block.kind == BlockKind.mathBlock) {
      _convertTo(block.codeBody, 0);
      return;
    }
    final newSource = '\$\$\n${editing.text}\n\$\$';
    _convertTo(newSource, 3);
  }

  /// Inserts a horizontal rule after the focused block (or converts an
  /// empty focused paragraph) and leaves the caret on a paragraph below.
  void insertHorizontalRule() {
    final block = focusedBlock;
    if (block != null && block.kind == BlockKind.paragraph &&
        editing.text.isEmpty) {
      _splitInto([
        Block(kind: BlockKind.thematicBreak, source: '---'),
        Block(kind: BlockKind.paragraph, source: ''),
      ], focusIndex: 1, caret: 0, replacing: block);
      return;
    }
    _insertBlocksAfterFocused([
      Block(kind: BlockKind.thematicBreak, source: '---'),
      Block(kind: BlockKind.paragraph, source: ''),
    ], focusOffset: 1);
  }

  /// Inserts a `[TOC]` block (rendered as a live outline) after the focused
  /// block.
  void insertTableOfContents() {
    _insertBlocksAfterFocused(
        [Block(kind: BlockKind.paragraph, source: '[TOC]')],
        focusOffset: 0);
  }

  /// Inserts a YAML front-matter block at the top of the document.
  void insertFrontMatter() {
    if (docCtrl.doc.blocks.first.kind == BlockKind.frontMatter) {
      focusBlock(docCtrl.doc.blocks.first.id, offset: 4);
      return;
    }
    final fm = Block(
        kind: BlockKind.frontMatter, source: '---\n\n---',
        blankLinesBefore: 0);
    docCtrl.spliceBlocks(
      index: 0, before: [], after: [fm], kind: EditKind.blockOp,
      caretBefore: _snap(editing.selection),
      caretAfter: CaretSnapshot(fm.id, 4),
    );
    focusBlock(fm.id, offset: 4);
  }

  void _insertBlocksAfterFocused(List<Block> blocks,
      {required int focusOffset}) {
    final id = _focusedBlockId;
    final i = id == null
        ? docCtrl.doc.blocks.length - 1
        : docCtrl.doc.indexOfBlock(id);
    docCtrl.spliceBlocks(
      index: i + 1, before: [], after: blocks, kind: EditKind.blockOp,
      caretBefore: _snap(editing.selection),
      caretAfter: CaretSnapshot(blocks[focusOffset].id, 0),
    );
    focusBlock(blocks[focusOffset].id);
  }

  /// Inserts an empty paragraph before/after the focused block — the escape
  /// hatch around opaque blocks.
  void insertParagraphBefore() {
    final id = _focusedBlockId;
    if (id == null) return;
    final i = docCtrl.doc.indexOfBlock(id);
    if (i < 0) return;
    final p = Block(kind: BlockKind.paragraph, source: '');
    docCtrl.spliceBlocks(
      index: i, before: [], after: [p], kind: EditKind.blockOp,
      caretBefore: _snap(editing.selection), caretAfter: CaretSnapshot(p.id, 0),
    );
    focusBlock(p.id);
  }

  void insertParagraphAfter() =>
      _insertBlocksAfterFocused([Block(kind: BlockKind.paragraph, source: '')],
          focusOffset: 0);

  /// Inserts a [rows]×[cols] table (converting an empty focused paragraph,
  /// otherwise after the focused block) and focuses the first cell.
  void insertTable(int rows, int cols) {
    final r = rows.clamp(1, 99);
    final c = cols.clamp(1, 20);
    final header = '|${'   |' * c}';
    final delimiter = '|${' --- |' * c}';
    final dataRows = List.filled(r, '|${'   |' * c}');
    final source = prettifyTable([header, delimiter, ...dataRows].join('\n'));
    final block = focusedBlock;
    if (block != null && block.kind == BlockKind.paragraph &&
        editing.text.isEmpty) {
      _convertTo(source, 2);
      return;
    }
    final table = Block(kind: BlockKind.table, source: source);
    _insertBlocksAfterFocused([table], focusOffset: 0);
    focusBlock(table.id, offset: 2);
  }

  /// Converts the focused block into a GitHub-style alert quote
  /// (`> [!NOTE]` …). [type] is NOTE/TIP/IMPORTANT/WARNING/CAUTION.
  void convertToAlert(String type) {
    final block = focusedBlock;
    if (block == null) return;
    final body = block.kind == BlockKind.blockquote
        ? _stripBlockMarkers(editing.text)
        : editing.text;
    // Replace an existing alert tag instead of stacking a second one.
    final lines = body.split('\n');
    if (lines.isNotEmpty &&
        RegExp(r'^\[!\w+\]\s*$').hasMatch(lines.first.trim())) {
      lines.removeAt(0);
      if (lines.isNotEmpty && lines.first.trim().isEmpty) lines.removeAt(0);
    }
    final content = lines.join('\n');
    final quoted = [
      '> [!$type]',
      for (final l in content.split('\n')) '> $l',
    ].join('\n');
    _convertTo(quoted, quoted.length);
  }

  /// Strips inline formatting (markers, code ticks, link syntax, HTML tags)
  /// from the selection — or the whole block when the caret is collapsed.
  void clearFormat() {
    final block = focusedBlock;
    if (block == null) return;
    var sel = editing.selection;
    if (!sel.isValid) return;
    if (sel.isCollapsed) {
      sel = TextSelection(baseOffset: 0, extentOffset: editing.text.length);
    }
    final slice = editing.text.substring(sel.start, sel.end);
    final plain = plainTextOfInline(slice);
    if (plain == slice) return;
    replaceRange(sel.start, sel.end, plain, kind: EditKind.blockOp);
  }

  /// Toggles `<u>…</u>` underline around the selection (Cmd+U).
  void toggleUnderline() {
    final block = focusedBlock;
    if (block == null) return;
    final text = editing.text;
    final sel = editing.selection;
    if (!sel.isValid) return;
    const open = '<u>';
    const close = '</u>';
    if (sel.isCollapsed) {
      replaceRange(sel.baseOffset, sel.baseOffset, '$open$close',
          caretAt: sel.baseOffset + open.length);
      return;
    }
    final a = sel.start;
    final b = sel.end;
    bool has(int at, String s) =>
        at >= 0 && at + s.length <= text.length &&
        text.substring(at, at + s.length).toLowerCase() == s;
    if (has(a - open.length, open) && has(b, close)) {
      final newText =
          text.replaceRange(b, b + close.length, '').replaceRange(
              a - open.length, a, '');
      _replaceAllText(newText,
          TextSelection(baseOffset: a - open.length, extentOffset: b - open.length));
      return;
    }
    final inner = text.substring(a, b);
    if (inner.toLowerCase().startsWith(open) &&
        inner.toLowerCase().endsWith(close) &&
        inner.length >= open.length + close.length) {
      final stripped =
          inner.substring(open.length, inner.length - close.length);
      replaceRange(a, b, stripped, kind: EditKind.blockOp);
      return;
    }
    final newText =
        text.replaceRange(b, b, close).replaceRange(a, a, open);
    _replaceAllText(newText,
        TextSelection(baseOffset: a + open.length, extentOffset: b + open.length));
  }

  /// Toggles an HTML comment `<!-- … -->` around the selection — hidden in
  /// rendered mode, dimmed while editing.
  void toggleComment() {
    final block = focusedBlock;
    if (block == null) return;
    final text = editing.text;
    final sel = editing.selection;
    if (!sel.isValid) return;
    const open = '<!-- ';
    const close = ' -->';
    if (sel.isCollapsed) {
      replaceRange(sel.baseOffset, sel.baseOffset, '$open$close',
          caretAt: sel.baseOffset + open.length);
      return;
    }
    final a = sel.start;
    final b = sel.end;
    final inner = text.substring(a, b);
    final m = RegExp(r'^<!--\s?([\s\S]*?)\s?-->$').firstMatch(inner);
    if (m != null) {
      replaceRange(a, b, m.group(1)!, kind: EditKind.blockOp);
      return;
    }
    final newText =
        text.replaceRange(b, b, close).replaceRange(a, a, open);
    _replaceAllText(newText,
        TextSelection(baseOffset: a + open.length, extentOffset: b + open.length));
  }

  /// View > Typewriter Mode: keeps the caret line vertically centered
  /// (EditingBlock drives the scrolling; EditorView pads the list).
  void toggleTypewriterMode() {
    typewriterModeEnabled = !typewriterModeEnabled;
    notifyListeners();
  }

  /// Vertical offset of the caret inside the focused block's text, for the
  /// typewriter-mode scroll policy.
  double caretDyInFocusedBlock() {
    final block = focusedBlock;
    if (block == null) return 0;
    final tp = _layoutFor(editing.text, block.kind,
        headingLevel: block.headingLevel);
    final dy = tp
        .getOffsetForCaret(
            TextPosition(offset: editing.selection.baseOffset), Rect.zero)
        .dy;
    tp.dispose();
    return dy;
  }

  // ---- In-place table cell editing (Typora-style) ----

  /// (row, col) of the active cell in the focused table, derived from the
  /// shared editing selection. Rows are source lines (1 = delimiter).
  (int, int)? activeTableCell() {
    final block = focusedBlock;
    if (block == null || block.kind != BlockKind.table) return null;
    final (row, col) = TableShape(editing.text)
        .cellForOffset(editing.selection.baseOffset);
    return (row == 1 ? 2 : row, col);
  }

  /// Focuses [row]/[col] of the focused table. [selectContent] selects the
  /// whole cell (typing replaces it); otherwise the caret goes to
  /// [localCaret] within the cell.
  void focusTableCell(String blockId, int row, int col,
      {bool selectContent = true, int localCaret = 0}) {
    final block = docCtrl.doc.blockById(blockId);
    if (block == null || block.kind != BlockKind.table) return;
    final shape = TableShape(block.source);
    var r = row.clamp(0, shape.lineCount - 1);
    if (r == 1) r = 2;
    final (a, b) = shape.rangeOf(r, col);
    focusBlock(blockId,
        selection: selectContent
            ? TextSelection(baseOffset: a, extentOffset: b)
            : TextSelection.collapsed(
                offset: (a + localCaret).clamp(a, b)));
  }

  /// Rewrites the active cell's content to [newText] with the caret at
  /// [localCaret], re-prettifying the whole table so the source stays
  /// aligned. The active cell survives the reformat.
  void updateActiveTableCell(String newText, int localCaret) {
    final id = _focusedBlockId;
    final cell = activeTableCell();
    if (id == null || cell == null) return;
    _materializeEphemeral();
    final (row, col) = cell;
    final shape = TableShape(editing.text);
    final (a, b) = shape.rangeOf(row, col);
    final raw = editing.text.replaceRange(a, b, newText);
    final pretty = prettifyTable(raw);
    final (na, nb) = TableShape(pretty).rangeOf(row, col);
    final caret = (na + localCaret).clamp(na, nb);
    final block = focusedBlock;
    if (block == null) return;
    final before = _snap(editing.selection);
    _setEditingValue(block, TextEditingValue(
        text: pretty, selection: TextSelection.collapsed(offset: caret)));
    docCtrl.changeBlockSource(id, pretty,
        kind: EditKind.typing,
        caretBefore: before,
        caretAfter: _snap(editing.selection),
        committedChar:
            newText.isNotEmpty && localCaret > 0 && localCaret <= newText.length
                ? newText[localCaret - 1]
                : null);
  }

  /// Moves the active cell by rows (skipping the delimiter row); appends a
  /// row when moving past the last one. Leaving the table top/bottom moves
  /// block focus instead.
  void moveTableCellVertically({required bool up}) {
    final id = _focusedBlockId;
    final cell = activeTableCell();
    if (id == null || cell == null) return;
    final (row, col) = cell;
    var target = up ? row - 1 : row + 1;
    if (target == 1) target = up ? 0 : 2;
    final shape = TableShape(editing.text);
    if (target < 0) {
      moveVertical(up: true);
      return;
    }
    if (target >= shape.lineCount) {
      moveVertical(up: false);
      return;
    }
    focusTableCell(id, target, col);
  }

  // ---- Table row/column operations (Paragraph > Table) ----

  /// Runs [op] over the focused table's cell matrix (header first, no
  /// delimiter row) and alignments, rebuilds prettified source, and focuses
  /// ([focusRow], [focusCol]) — line-index based. A table emptied of
  /// columns is deleted.
  void _applyTableOp(
    void Function(List<List<String>> rows, List<TextAlign> alignments,
            int dataIndex, int col)
        op, {
    int Function(int row, int dataIndex)? focusRow,
    int Function(int col)? focusCol,
  }) {
    final id = _focusedBlockId;
    final cell = activeTableCell();
    final block = focusedBlock;
    if (id == null || cell == null || block == null) return;
    final (row, col) = cell;
    final shape = TableShape(editing.text);
    final rows = <List<String>>[];
    for (var li = 0; li < shape.lineCount; li++) {
      if (li == 1) continue;
      rows.add([
        for (var c = 0; c < shape.columnCount; c++)
          c < shape.cellsOnLine(li).length ? shape.textOf(li, c) : '',
      ]);
    }
    final alignments = List<TextAlign>.of(shape.alignments);
    while (alignments.length < shape.columnCount) {
      alignments.add(TextAlign.left);
    }
    final dataIndex = row == 0 ? 0 : row - 1; // rows-list index
    op(rows, alignments, dataIndex, col);
    if (rows.isEmpty || rows.every((r) => r.isEmpty)) {
      deleteTable();
      return;
    }
    final source = buildTableSource(rows, alignments);
    docCtrl.changeBlockSource(id, source,
        kind: EditKind.blockOp,
        caretBefore: _snap(editing.selection));
    final targetRow = focusRow?.call(row, dataIndex) ?? row;
    final targetCol = focusCol?.call(col) ?? col;
    final lineCount = source.split('\n').length;
    focusTableCell(id, targetRow.clamp(0, lineCount - 1), targetCol);
  }

  void addTableRowAbove() => _applyTableOp(
        (rows, aligns, d, c) => rows.insert(d == 0 ? 1 : d, // header pinned
            List.filled(rows.first.length, '')),
        focusRow: (row, d) => row == 0 ? 2 : row,
      );

  void addTableRowBelow() => _applyTableOp(
        (rows, aligns, d, c) =>
            rows.insert(d + 1, List.filled(rows.first.length, '')),
        focusRow: (row, d) => row == 0 ? 2 : row + 1,
      );

  void addTableColumnBefore() => _applyTableOp(
        (rows, aligns, d, c) {
          for (final r in rows) {
            r.insert(c.clamp(0, r.length), '');
          }
          aligns.insert(c.clamp(0, aligns.length), TextAlign.left);
        },
      );

  void addTableColumnAfter() => _applyTableOp(
        (rows, aligns, d, c) {
          for (final r in rows) {
            r.insert((c + 1).clamp(0, r.length), '');
          }
          aligns.insert((c + 1).clamp(0, aligns.length), TextAlign.left);
        },
        focusCol: (c) => c + 1,
      );

  void deleteTableRow() => _applyTableOp(
        (rows, aligns, d, c) {
          if (d > 0 && d < rows.length) rows.removeAt(d); // header pinned
        },
        focusRow: (row, d) => row <= 2 ? 2 : row - 1,
      );

  void deleteTableColumn() => _applyTableOp(
        (rows, aligns, d, c) {
          for (final r in rows) {
            if (c < r.length) r.removeAt(c);
          }
          if (c < aligns.length) aligns.removeAt(c);
        },
        focusCol: (c) => c > 0 ? c - 1 : 0,
      );

  void _moveTableColumn({required bool left}) => _applyTableOp(
        (rows, aligns, d, c) {
          final t = left ? c - 1 : c + 1;
          if (t < 0 || t >= rows.first.length) return;
          for (final r in rows) {
            if (c < r.length && t < r.length) {
              final tmp = r[c];
              r[c] = r[t];
              r[t] = tmp;
            }
          }
          if (c < aligns.length && t < aligns.length) {
            final tmp = aligns[c];
            aligns[c] = aligns[t];
            aligns[t] = tmp;
          }
        },
        focusCol: (c) => left ? (c > 0 ? c - 1 : 0) : c + 1,
      );

  void moveTableColumnLeft() => _moveTableColumn(left: true);

  void moveTableColumnRight() => _moveTableColumn(left: false);

  /// Copies the focused table's raw markdown source.
  void copyTable() {
    final block = focusedBlock;
    if (block == null || block.kind != BlockKind.table) return;
    Clipboard.setData(ClipboardData(text: block.source));
  }

  /// Deletes the focused table block entirely.
  void deleteTable() {
    final id = _focusedBlockId;
    final block = focusedBlock;
    if (id == null || block == null || block.kind != BlockKind.table) return;
    final i = docCtrl.doc.indexOfBlock(id);
    if (i < 0) return;
    docCtrl.spliceBlocks(
      index: i, before: [block], after: [], kind: EditKind.blockOp,
      caretBefore: _snap(editing.selection),
    );
    final blocks = docCtrl.doc.blocks;
    final target = blocks[(i - 1).clamp(0, blocks.length - 1)];
    focusBlock(target.id, offset: target.source.length);
  }

  /// Prettifies a table block's source in place (used on blur so the stored
  /// markdown always looks clean in source mode and on disk).
  void _prettifyTableBlock(String blockId) {
    final block = docCtrl.doc.blockById(blockId);
    if (block == null || block.kind != BlockKind.table) return;
    final pretty = prettifyTable(block.source);
    if (pretty == block.source) return;
    docCtrl.changeBlockSource(blockId, pretty, kind: EditKind.blockOp);
  }

  // ---- Task status (Paragraph > Task Status) ----

  int _caretLineIndex() {
    final caret = editing.selection.baseOffset;
    if (caret <= 0) return 0;
    return editing.text.substring(0, caret.clamp(0, editing.text.length))
        .split('\n').length - 1;
  }

  /// Sets the task checkbox on the caret line; null toggles.
  void setTaskStatusAtCaret({bool? checked}) {
    final block = focusedBlock;
    final id = _focusedBlockId;
    if (block == null || id == null || block.kind != BlockKind.list) return;
    final li = _caretLineIndex();
    final line = editing.text.split('\n')[li];
    final m = RegExp(r'\[([ xX])\]').firstMatch(line);
    if (m == null) return;
    final isChecked = m.group(1) != ' ';
    final target = checked ?? !isChecked;
    if (target == isChecked) return;
    toggleTask(id, li);
  }

  /// Menu wrappers for list indentation (Tab/Shift+Tab do the same).
  void indentListItem() {
    if (focusedBlock?.kind == BlockKind.list) handleTab();
  }

  void outdentListItem() {
    if (focusedBlock?.kind == BlockKind.list) handleTab(shift: true);
  }

  // ---- Move row / block up & down (Edit > Move Row) ----

  /// Moves the caret line within a list/table block, or the whole focused
  /// block otherwise. [up] chooses the direction.
  void moveRow({required bool up}) {
    final block = focusedBlock;
    final id = _focusedBlockId;
    if (block == null || id == null) return;
    if (block.kind == BlockKind.list || block.kind == BlockKind.table) {
      final lines = editing.text.split('\n');
      final li = _caretLineIndex();
      final target = up ? li - 1 : li + 1;
      // Table: never move the header or across the delimiter row.
      final minLine = block.kind == BlockKind.table ? 2 : 0;
      if (li >= minLine && target >= minLine && target < lines.length) {
        final caretInLine = editing.selection.baseOffset -
            lines.sublist(0, li).fold<int>(0, (n, l) => n + l.length + 1);
        final tmp = lines[li];
        lines[li] = lines[target];
        lines[target] = tmp;
        final newText = lines.join('\n');
        final newCaret = lines.sublist(0, target)
                .fold<int>(0, (n, l) => n + l.length + 1) +
            caretInLine.clamp(0, lines[target].length);
        replaceRange(0, editing.text.length, newText,
            caretAt: newCaret, kind: EditKind.blockOp);
        return;
      }
      if (block.kind == BlockKind.table) return;
    }
    // Whole-block move.
    final i = docCtrl.doc.indexOfBlock(id);
    final j = up ? i - 1 : i + 1;
    if (i < 0 || j < 0 || j >= docCtrl.doc.blocks.length) return;
    final caret = editing.selection.baseOffset;
    final neighbour = docCtrl.doc.blocks[j];
    final lo = up ? j : i;
    docCtrl.spliceBlocks(
      index: lo,
      before: up ? [neighbour, block] : [block, neighbour],
      after: up ? [block, neighbour] : [neighbour, block],
      kind: EditKind.blockOp,
      caretBefore: _snap(editing.selection),
      caretAfter: CaretSnapshot(id, caret),
    );
    focusBlock(id, offset: caret);
  }

  // ---- Undo / redo ----

  void undo() => _applyHistory(docCtrl.undo());

  void redo() => _applyHistory(docCtrl.redo());

  void _applyHistory(CaretSnapshot? caret) {
    if (caret == null) {
      // Nothing to restore; if a block is focused re-sync its text.
      final b = focusedBlock;
      if (b != null) {
        _setEditingValue(b, TextEditingValue(
            text: b.source,
            selection: _clampSelection(editing.selection, b.source.length)));
      }
      notifyListeners();
      return;
    }
    final block = docCtrl.doc.blockById(caret.blockId);
    if (block == null) {
      blur();
      return;
    }
    focusBlock(caret.blockId,
        selection: TextSelection(
            baseOffset: caret.base, extentOffset: caret.extent));
  }

  @override
  void dispose() {
    editing.removeListener(_onEditingChanged);
    focusNode.removeListener(_onFocusNodeChanged);
    editing.dispose();
    focusNode.dispose();
    sourceModeEnabled.dispose();
    findVisible.dispose();
    for (final n in _focusFlags.values) {
      n.dispose();
    }
    super.dispose();
  }
}
