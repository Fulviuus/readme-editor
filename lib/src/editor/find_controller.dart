/// Find/replace state: scans block sources for a query, tracks the current
/// match, and applies replacements through the editor/document contracts
/// (EditorController.replaceRange, DocumentController.changeBlockSource).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../document/document_controller.dart';
import 'editor_controller.dart';

/// One occurrence of the query inside a block's source ([start], [end) are
/// source offsets within that block).
class FindMatch {
  const FindMatch({
    required this.blockId,
    required this.start,
    required this.end,
  });

  final String blockId;
  final int start;
  final int end;

  @override
  String toString() => 'FindMatch($blockId, $start..$end)';
}

class FindController extends ChangeNotifier {
  FindController(this.editor) {
    editor.docCtrl.addListener(_onDocumentChanged);
  }

  final EditorController editor;

  String _query = '';
  String get query => _query;

  /// Replacement text used by [replaceCurrent] and [replaceAll].
  String replacement = '';

  bool _caseSensitive = false;
  bool get caseSensitive => _caseSensitive;
  set caseSensitive(bool value) {
    if (value == _caseSensitive) return;
    _caseSensitive = value;
    search(_query);
  }

  List<FindMatch> _matches = const [];
  List<FindMatch> get matches => _matches;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  Timer? _debounce;

  // ---- Searching ----

  void search(String query) {
    _debounce?.cancel();
    _query = query;
    _matches = _scan();
    _currentIndex = -1;
    notifyListeners();
  }

  /// Document edits while the bar is open invalidate match offsets: re-scan,
  /// debounced (typing emits one notification per keystroke).
  void _onDocumentChanged() {
    if (_query.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      _matches = _scan();
      if (_currentIndex >= _matches.length) {
        _currentIndex = _matches.length - 1;
      }
      notifyListeners();
    });
  }

  List<FindMatch> _scan() {
    if (_query.isEmpty) return const [];
    final needle = _caseSensitive ? _query : _query.toLowerCase();
    final found = <FindMatch>[];
    for (final block in editor.docCtrl.doc.blocks) {
      final haystack =
          _caseSensitive ? block.source : block.source.toLowerCase();
      var from = 0;
      while (true) {
        final i = haystack.indexOf(needle, from);
        if (i < 0) break;
        found.add(FindMatch(blockId: block.id, start: i, end: i + needle.length));
        from = i + needle.length;
      }
    }
    return found;
  }

  // ---- Navigation ----

  void next() {
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _matches.length;
    _focusCurrent();
    notifyListeners();
  }

  void previous() {
    if (_matches.isEmpty) return;
    _currentIndex =
        _currentIndex <= 0 ? _matches.length - 1 : _currentIndex - 1;
    _focusCurrent();
    notifyListeners();
  }

  /// Focuses the current match's block with the match selected.
  void _focusCurrent() {
    if (_currentIndex < 0 || _currentIndex >= _matches.length) return;
    final m = _matches[_currentIndex];
    editor.focusBlock(m.blockId,
        selection: TextSelection(baseOffset: m.start, extentOffset: m.end));
  }

  // ---- Replacing ----

  void replaceCurrent() {
    if (_matches.isEmpty) return;
    if (_currentIndex < 0) _currentIndex = 0;
    final m = _matches[_currentIndex];
    if (editor.focusedBlockId != m.blockId) {
      editor.focusBlock(m.blockId,
          selection: TextSelection(baseOffset: m.start, extentOffset: m.end));
    }
    if (editor.focusedBlockId != m.blockId) return; // block vanished
    editor.replaceRange(m.start, m.end, replacement, kind: EditKind.blockOp);
    _debounce?.cancel();
    final at = _currentIndex;
    _matches = _scan();
    _currentIndex = _matches.isEmpty ? -1 : (at < _matches.length ? at : 0);
    _focusCurrent();
    notifyListeners();
  }

  /// Replaces every match, one [DocumentController.changeBlockSource] per
  /// affected block (undo may take several steps — acceptable).
  void replaceAll() {
    if (_query.isEmpty) return;
    // The focused block's TextField holds a copy of its source; blur first
    // so a stale editing value cannot overwrite the replacement afterwards.
    editor.blur();
    final blocks = editor.docCtrl.doc.blocks.toList();
    for (final block in blocks) {
      final replaced = _replaceAllIn(block.source);
      if (replaced != block.source) {
        editor.docCtrl
            .changeBlockSource(block.id, replaced, kind: EditKind.blockOp);
      }
    }
    _debounce?.cancel();
    _matches = _scan();
    _currentIndex = -1;
    notifyListeners();
  }

  String _replaceAllIn(String source) {
    final needle = _caseSensitive ? _query : _query.toLowerCase();
    final haystack = _caseSensitive ? source : source.toLowerCase();
    final buf = StringBuffer();
    var from = 0;
    while (true) {
      final i = haystack.indexOf(needle, from);
      if (i < 0) break;
      buf
        ..write(source.substring(from, i))
        ..write(replacement);
      from = i + needle.length;
    }
    if (from == 0) return source;
    buf.write(source.substring(from));
    return buf.toString();
  }

  // ---- Lifecycle ----

  /// Clears state and hides the bar.
  void close() {
    _debounce?.cancel();
    _query = '';
    _matches = const [];
    _currentIndex = -1;
    editor.findVisible.value = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    editor.docCtrl.removeListener(_onDocumentChanged);
    super.dispose();
  }
}
