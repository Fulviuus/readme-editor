/// Owns the document and every mutation to it, including the single
/// document-level undo/redo stack (docs/DESIGN-editor-interaction.md §5).
///
/// The editor layer builds [DocEdit]s (splice ops over the block list) and
/// hands them to [apply]; TextField-internal undo is bypassed entirely.
library;

import 'package:flutter/foundation.dart';

import 'block.dart';
import 'block_splitter.dart';
import 'document.dart';

enum EditKind {
  typing,
  deleteBack,
  deleteFwd,
  split,
  merge,
  typeChange,
  autoConvert,
  paste,
  blockOp,
  replaceAll,
}

/// Caret position in SOURCE offsets of one block.
class CaretSnapshot {
  const CaretSnapshot(this.blockId, this.base, [int? extent])
      : extent = extent ?? base;
  final String blockId;
  final int base;
  final int extent;

  bool get isCollapsed => base == extent;

  @override
  String toString() => 'Caret($blockId, $base..$extent)';
}

/// The universal splice op: replaces `before` (blocks currently at [index])
/// with `after`. Covers in-place text change (1→1), split (1→n), merge
/// (n→1), type change, auto-convert and whole-document replacement.
class DocEdit {
  DocEdit({
    required this.index,
    required this.before,
    required this.after,
    required this.kind,
    this.caretBefore,
    this.caretAfter,
    this.committedChar,
  }) : at = DateTime.now();

  final int index;
  List<Block> before;
  List<Block> after;
  final EditKind kind;
  CaretSnapshot? caretBefore;
  CaretSnapshot? caretAfter;

  /// Document-level byte facts, captured by [EditKind.replaceAll] edits so
  /// undo restores trailing blank lines / final-newline state too.
  ({int trailingBlankLines, bool hadFinalNewline})? docMetaBefore;
  ({int trailingBlankLines, bool hadFinalNewline})? docMetaAfter;

  /// Last character this edit inserted (typing edits only) — used for
  /// word-boundary coalescing flushes.
  String? committedChar;

  DateTime at;

  int get coalescedLength =>
      after.isEmpty || before.isEmpty
          ? 0
          : (after.first.source.length - before.first.source.length).abs();
}

const _wordBoundaryChars = {' ', '\t', '\n', '.', ',', ';', ':', '!', '?'};

/// Opaque per-tab snapshot; see [DocumentController.captureState].
class DocumentState {
  DocumentState._(this._doc, this._filePath, this._undo, this._redo,
      this._revision, this._savedRevision);

  /// A fresh empty document (a new tab).
  factory DocumentState.empty() =>
      DocumentState._(Document.parse(''), null, [], [], 0, 0);

  final Document _doc;
  final String? _filePath;
  final List<DocEdit> _undo;
  final List<DocEdit> _redo;
  final int _revision;
  final int _savedRevision;

  String? get filePath => _filePath;
  bool get dirty => _revision != _savedRevision;
}

class DocumentController extends ChangeNotifier {
  DocumentController() : _doc = Document(blocks: []);

  Document _doc;
  Document get doc => _doc;

  String? filePath;

  final List<DocEdit> _undoStack = [];
  final List<DocEdit> _redoStack = [];
  static const _maxUndoDepth = 1000;

  /// Monotonic count of net applied edits; equality with [_savedRevision]
  /// means the buffer matches disk.
  int _revision = 0;
  int _savedRevision = 0;

  bool get dirty => _revision != _savedRevision;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Current revision — snapshot this BEFORE an async save write and pass it
  /// to [markSavedAt], so keystrokes typed during the write stay dirty.
  int get revision => _revision;

  void markSaved() => markSavedAt(_revision);

  void markSavedAt(int revision) {
    _savedRevision = revision;
    // A save point must never sit inside an open coalescing group, or a
    // post-save typing edit would merge into the pre-save entry and undo
    // could not land exactly on the saved state.
    sealUndoGroup();
    notifyListeners();
  }

  /// Switches the on-disk line-ending style ('\n' or '\r\n'). Marks the
  /// document dirty; not undoable (a file-level setting, not a text edit).
  void setLineEnding(String ending) {
    if (ending != '\n' && ending != '\r\n') return;
    if (_doc.lineEnding == ending) return;
    _doc.lineEnding = ending;
    _revision++;
    notifyListeners();
  }

  /// Toggles whether the file ends with a final newline on save. Marks the
  /// document dirty; not undoable.
  void setFinalNewline(bool enabled) {
    if (_doc.hadFinalNewline == enabled) return;
    _doc.hadFinalNewline = enabled;
    _revision++;
    notifyListeners();
  }

  void loadText(String text, {String? path}) {
    _doc = Document.parse(text);
    filePath = path;
    _undoStack.clear();
    _redoStack.clear();
    _revision = 0;
    _savedRevision = 0;
    notifyListeners();
  }

  // ---- Tab support: whole-state capture/restore ----

  /// Snapshot of everything a document tab owns: content, file binding,
  /// undo history and dirty tracking. While a tab is inactive its snapshot
  /// is the sole owner of the [Document] instance inside.
  DocumentState captureState() => DocumentState._(_doc, filePath,
      [..._undoStack], [..._redoStack], _revision, _savedRevision);

  /// Swaps the controller onto [state] (a tab switch). The outgoing state
  /// must have been [captureState]d first or it is lost.
  void restoreState(DocumentState state) {
    _doc = state._doc;
    filePath = state._filePath;
    _undoStack
      ..clear()
      ..addAll(state._undo);
    _redoStack
      ..clear()
      ..addAll(state._redo);
    _revision = state._revision;
    _savedRevision = state._savedRevision;
    notifyListeners();
  }

  String serialize() => _doc.serialize();

  // ---- Mutation ----

  /// Applies [edit] and records it for undo. Set [record] false for
  /// undo-invisible changes (the ephemeral trailing paragraph).
  void apply(DocEdit edit, {bool record = true}) {
    _splice(edit.index, edit.before.length, edit.after);
    if (record) {
      _redoStack.clear();
      if (!_tryCoalesce(edit)) {
        _undoStack.add(edit);
        if (_undoStack.length > _maxUndoDepth) _undoStack.removeAt(0);
        // One revision per undo step: undo/redo move the revision by one
        // entry, so coalesced edits must not bump it again or an undone
        // document would still count as dirty.
        _revision++;
      }
    }
    notifyListeners();
  }

  bool _tryCoalesce(DocEdit edit) {
    if (_undoStack.isEmpty) return false;
    final top = _undoStack.last;
    final coalescable = (edit.kind == EditKind.typing &&
            top.kind == EditKind.typing) ||
        (edit.kind == top.kind &&
            (edit.kind == EditKind.deleteBack ||
                edit.kind == EditKind.deleteFwd));
    if (!coalescable) return false;
    if (top.after.length != 1 ||
        edit.before.length != 1 ||
        edit.after.length != 1) {
      return false;
    }
    if (top.after.first.id != edit.before.first.id) return false;
    if (edit.at.difference(top.at).inMilliseconds >= 1000) return false;
    // Caret continuity: no intervening caret move.
    final prevCaret = top.caretAfter;
    final nextCaret = edit.caretBefore;
    if (prevCaret == null ||
        nextCaret == null ||
        prevCaret.blockId != nextCaret.blockId ||
        prevCaret.base != nextCaret.base) {
      return false;
    }
    // Word-boundary flush: the burst breaks after a boundary char.
    final prevChar = top.committedChar;
    if (edit.kind == EditKind.typing &&
        prevChar != null &&
        _wordBoundaryChars.contains(prevChar)) {
      return false;
    }
    // Cap the size of one coalesced group.
    if ((edit.after.first.source.length - top.before.first.source.length)
            .abs() >
        100) {
      return false;
    }
    top.after = edit.after;
    top.caretAfter = edit.caretAfter;
    top.committedChar = edit.committedChar;
    top.at = edit.at;
    return true;
  }

  void _splice(int index, int removeCount, List<Block> insert) {
    _doc.blocks.replaceRange(index, index + removeCount, insert);
    if (_doc.blocks.isEmpty) {
      _doc.blocks.add(
          Block(kind: BlockKind.paragraph, source: '', blankLinesBefore: 0));
    }
  }

  /// Seals the top undo entry so the next typing edit starts a new group
  /// (called on focus change / programmatic caret moves).
  void sealUndoGroup() {
    if (_undoStack.isNotEmpty) {
      // Forcing the timestamp far in the past defeats the 1s coalesce window.
      _undoStack.last.at =
          _undoStack.last.at.subtract(const Duration(seconds: 10));
    }
  }

  CaretSnapshot? undo() {
    if (_undoStack.isEmpty) return null;
    final edit = _undoStack.removeLast();
    _splice(edit.index, edit.after.length, edit.before);
    final meta = edit.docMetaBefore;
    if (meta != null) {
      _doc
        ..trailingBlankLines = meta.trailingBlankLines
        ..hadFinalNewline = meta.hadFinalNewline;
    }
    _redoStack.add(edit);
    _revision--;
    notifyListeners();
    return edit.caretBefore;
  }

  CaretSnapshot? redo() {
    if (_redoStack.isEmpty) return null;
    final edit = _redoStack.removeLast();
    _splice(edit.index, edit.before.length, edit.after);
    final meta = edit.docMetaAfter;
    if (meta != null) {
      _doc
        ..trailingBlankLines = meta.trailingBlankLines
        ..hadFinalNewline = meta.hadFinalNewline;
    }
    _undoStack.add(edit);
    _revision++;
    notifyListeners();
    return edit.caretAfter;
  }

  // ---- Edit builders (splice construction; semantics live in the editor) ----

  /// In-place source change of one block. The block's kind is re-derived from
  /// the new source (typing `# ` converts to heading, deleting it converts
  /// back). Returns the applied edit, or null if the block vanished.
  DocEdit? changeBlockSource(
    String blockId,
    String newSource, {
    EditKind kind = EditKind.typing,
    CaretSnapshot? caretBefore,
    CaretSnapshot? caretAfter,
    String? committedChar,
  }) {
    final i = _doc.indexOfBlock(blockId);
    if (i < 0) return null;
    final old = _doc.blocks[i];
    if (old.source == newSource) return null;
    // An emptied block is always a paragraph — deriveSingleKind('') is null
    // and keeping e.g. mathBlock would leave a stale kind Backspace can
    // never demote away.
    final newKind = newSource.isEmpty
        ? BlockKind.paragraph
        : deriveSingleKind(newSource) ?? old.kind;
    final edit = DocEdit(
      index: i,
      before: [old],
      after: [old.copyWith(source: newSource, kind: newKind)],
      kind: newKind != old.kind && kind == EditKind.typing
          ? EditKind.autoConvert
          : kind,
      caretBefore: caretBefore,
      caretAfter: caretAfter,
      committedChar: committedChar,
    );
    apply(edit);
    return edit;
  }

  /// Replaces one block with the blocks its (edited) source scans into.
  /// Used after Enter/paste inside fence-like blocks (§2.4). Returns the
  /// resulting blocks (with ids) so the caller can place the caret.
  List<Block>? rescanBlock(String blockId, String newSource,
      {CaretSnapshot? caretBefore, CaretSnapshot? caretAfter}) {
    final i = _doc.indexOfBlock(blockId);
    if (i < 0) return null;
    final old = _doc.blocks[i];
    final parts = splitMarkdown(newSource, isFragment: true).blocks;
    if (parts.isEmpty) {
      parts.add(Block(kind: BlockKind.paragraph, source: ''));
    }
    // First part keeps the old id so focus and list keys stay stable.
    final after = [
      Block(
        id: old.id,
        kind: parts.first.kind,
        source: parts.first.source,
        blankLinesBefore: old.blankLinesBefore,
      ),
      ...parts.skip(1),
    ];
    apply(DocEdit(
      index: i,
      before: [old],
      after: after,
      kind: EditKind.split,
      caretBefore: caretBefore,
      caretAfter: caretAfter,
    ));
    return after;
  }

  /// Generic splice for split/merge/insert/remove built by the editor layer.
  void spliceBlocks({
    required int index,
    required List<Block> before,
    required List<Block> after,
    required EditKind kind,
    CaretSnapshot? caretBefore,
    CaretSnapshot? caretAfter,
    bool record = true,
  }) {
    apply(
      DocEdit(
        index: index,
        before: before,
        after: after,
        kind: kind,
        caretBefore: caretBefore,
        caretAfter: caretAfter,
      ),
      record: record,
    );
  }

  /// Replaces the whole document (source-mode exit, Select-All overwrite).
  void replaceAll(String text, {CaretSnapshot? caretBefore}) {
    final old = List<Block>.of(_doc.blocks);
    final metaBefore = (
      trailingBlankLines: _doc.trailingBlankLines,
      hadFinalNewline: _doc.hadFinalNewline,
    );
    final parsed = Document.parse(text);
    _doc
      ..trailingBlankLines = parsed.trailingBlankLines
      ..hadFinalNewline = parsed.hadFinalNewline;
    apply(DocEdit(
      index: 0,
      before: old,
      after: parsed.blocks,
      kind: EditKind.replaceAll,
      caretBefore: caretBefore,
      caretAfter: parsed.blocks.isEmpty
          ? null
          : CaretSnapshot(parsed.blocks.first.id, 0),
    )
      ..docMetaBefore = metaBefore
      ..docMetaAfter = (
        trailingBlankLines: parsed.trailingBlankLines,
        hadFinalNewline: parsed.hadFinalNewline,
      ));
  }
}
