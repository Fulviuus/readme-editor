/// Modal (Vim-style) key bindings for the focused block, opt-in from
/// Preferences > Editor. The handler sits on the editing field's own
/// FocusNode, so in normal/visual mode it consumes keys before the field,
/// the structural-key Focus above it, and the platform IME ever see them;
/// in insert mode everything passes through untouched (except Escape).
///
/// Supported: h j k l (and arrows), w b e, 0 ^ $, gg G, i a I A o O,
/// x X s S r, d c y with those motions and doubled (dd cc yy), D C,
/// p P with a linewise/charwise register, u / Ctrl+R, counts, and
/// charwise (v) / linewise (V) visual mode with d x y c.
/// j/k walk across blocks at block edges; gg/G jump to the document ends.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../document/block.dart';
import '../document/document_controller.dart';
import 'editor_controller.dart';

enum VimMode { insert, normal, visual, visualLine }

class VimController extends ChangeNotifier {
  VimController(this.editor);

  final EditorController editor;

  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    _mode = VimMode.normal;
    _clearPending();
    notifyListeners();
  }

  VimMode _mode = VimMode.normal;
  VimMode get mode => _mode;

  String get modeLabel => switch (_mode) {
        VimMode.insert => 'INSERT',
        VimMode.normal => 'NORMAL',
        VimMode.visual => 'VISUAL',
        VimMode.visualLine => 'V-LINE',
      };

  // Pending state: count prefix, operator (d/c/y, g, r), visual anchor.
  int? _count;
  String _op = '';
  int _anchor = 0;

  // Unnamed register.
  String _register = '';
  bool _registerLinewise = false;

  String get _text => editor.editing.text;

  int get _caret {
    final sel = editor.editing.selection;
    if (!sel.isValid) return 0;
    return sel.extentOffset.clamp(0, _text.length);
  }

  void _setMode(VimMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  void _clearPending() {
    _count = null;
    _op = '';
  }

  // ---- Key entry point (FocusOnKeyEventCallback) ----

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (!_enabled || editor.focusedBlockId == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (hw.isMetaPressed || hw.isAltPressed) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_mode == VimMode.insert) {
      if (key == LogicalKeyboardKey.escape) {
        _escapeFromInsert();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Normal and visual modes.
    if (hw.isControlPressed) {
      if (key == LogicalKeyboardKey.keyR) {
        _clearPending();
        editor.redo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      final hadPending =
          _count != null || _op.isNotEmpty || _mode != VimMode.normal;
      _clearPending();
      if (_mode != VimMode.normal) {
        _setMode(VimMode.normal);
        _collapseTo(editor.editing.selection.isValid
            ? editor.editing.selection.start
            : 0);
      }
      // A bare Escape in normal mode falls through, so the editor blurs
      // exactly like it does without modal bindings.
      return hadPending ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return _dispatch('h');
    if (key == LogicalKeyboardKey.arrowRight) return _dispatch('l');
    if (key == LogicalKeyboardKey.arrowUp) return _dispatch('k');
    if (key == LogicalKeyboardKey.arrowDown) return _dispatch('j');
    if (key == LogicalKeyboardKey.backspace) return _dispatch('h');
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return _dispatch('j');
    }
    if (key == LogicalKeyboardKey.tab) return KeyEventResult.handled;

    var ch = event.character;
    if (ch == null || ch.isEmpty) return KeyEventResult.ignored;
    // Test-simulated events report the unshifted character; real platforms
    // already deliver 'G' for shift+g, so uppercasing twice is harmless.
    if (hw.isShiftPressed && ch.length == 1) ch = ch.toUpperCase();
    return _dispatch(ch);
  }

  // ---- Command dispatch ----

  KeyEventResult _dispatch(String ch) {
    // Pending single-char argument (r<char>).
    if (_op == 'r') {
      _op = '';
      _replaceChar(ch);
      return KeyEventResult.handled;
    }
    if (_op == 'g') {
      _op = '';
      if (ch == 'g') _jumpDocument(top: true);
      return KeyEventResult.handled;
    }

    // Count prefix ('0' only counts after another digit).
    if (RegExp(r'^[1-9]$').hasMatch(ch) || (ch == '0' && _count != null)) {
      _count = (_count ?? 0) * 10 + int.parse(ch);
      return KeyEventResult.handled;
    }
    final n = _count ?? 1;
    _count = null;

    // Doubled operators: dd / cc / yy.
    if (_op.isNotEmpty && ch == _op) {
      final op = _op;
      _op = '';
      _lineOperator(op);
      return KeyEventResult.handled;
    }
    if (_op.isEmpty && (ch == 'd' || ch == 'c' || ch == 'y') &&
        _mode == VimMode.normal) {
      _op = ch;
      return KeyEventResult.handled;
    }
    if (ch == 'g' && _op.isEmpty) {
      _op = 'g';
      return KeyEventResult.handled;
    }

    // Operator + motion.
    if (_op.isNotEmpty) {
      final op = _op;
      _op = '';
      final range = _motionRange(ch, n);
      if (range != null) _applyOperator(op, range.$1, range.$2);
      return KeyEventResult.handled;
    }

    // Visual-mode commands.
    if (_mode == VimMode.visual || _mode == VimMode.visualLine) {
      switch (ch) {
        case 'd' || 'x':
          _deleteVisual(insertAfter: false);
          return KeyEventResult.handled;
        case 'c' || 's':
          _deleteVisual(insertAfter: true);
          return KeyEventResult.handled;
        case 'y':
          _yankVisual();
          return KeyEventResult.handled;
        case 'v':
          _setMode(VimMode.normal);
          _collapseTo(_caret);
          return KeyEventResult.handled;
      }
      // Motions fall through and extend the selection.
    }

    switch (ch) {
      // Motions.
      case 'h':
        _moveCaret((c) => _stepLeft(c, n));
      case 'l' || ' ':
        _moveCaret((c) => _stepRight(c, n));
      case 'j':
        _moveVertical(down: true, n: n);
      case 'k':
        _moveVertical(down: false, n: n);
      case 'w':
        _moveCaret((c) => _wordForward(c, n));
      case 'b':
        _moveCaret((c) => _wordBack(c, n));
      case 'e':
        _moveCaret((c) => _wordEnd(c, n));
      case '0':
        _moveCaret(_lineStartOf);
      case '^':
        _moveCaret((c) => _firstNonBlank(c));
      case '\$':
        _moveCaret((c) => _lineEndOf(c));
      case 'G':
        _jumpDocument(top: false);

      // Insert-mode entries.
      case 'i':
        _setMode(VimMode.insert);
      case 'a':
        _collapseTo((_caret + 1).clamp(0, _lineEndOf(_caret)));
        _setMode(VimMode.insert);
      case 'I':
        _collapseTo(_firstNonBlank(_caret));
        _setMode(VimMode.insert);
      case 'A':
        _collapseTo(_lineEndOf(_caret));
        _setMode(VimMode.insert);
      case 'o':
        _openLine(above: false);
      case 'O':
        _openLine(above: true);

      // Edits.
      case 'x':
        _deleteAtCaret(n, before: false);
      case 'X':
        _deleteAtCaret(n, before: true);
      case 'D':
        _applyOperator('d', _caret, _lineEndOf(_caret));
      case 'C':
        _applyOperator('c', _caret, _lineEndOf(_caret));
      case 's':
        _deleteAtCaret(n, before: false);
        _setMode(VimMode.insert);
      case 'S':
        _lineOperator('c');
      case 'r':
        _op = 'r';
      case 'p':
        _paste(after: true);
      case 'P':
        _paste(after: false);
      case 'u':
        editor.undo();
      case 'v':
        _anchor = _caret;
        _setMode(VimMode.visual);
        _syncVisualSelection(_caret);
      case 'V':
        _anchor = _caret;
        _setMode(VimMode.visualLine);
        _syncVisualSelection(_caret);
      default:
        break; // Unbound key in normal mode: swallowed, never typed.
    }
    return KeyEventResult.handled;
  }

  // ---- Line/word geometry ----

  int _lineStartOf(int i) {
    final t = _text;
    final c = i.clamp(0, t.length);
    return t.lastIndexOf('\n', c - 1 < 0 ? 0 : c - 1) + 1;
  }

  int _lineEndOf(int i) {
    final t = _text;
    final e = t.indexOf('\n', i.clamp(0, t.length));
    return e < 0 ? t.length : e;
  }

  int _firstNonBlank(int i) {
    final t = _text;
    var s = _lineStartOf(i);
    final e = _lineEndOf(i);
    while (s < e && (t[s] == ' ' || t[s] == '\t')) {
      s++;
    }
    return s;
  }

  static bool _isWordChar(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);
  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n';

  int _stepLeft(int c, int n) {
    var o = c;
    for (var i = 0; i < n; i++) {
      if (o > _lineStartOf(o)) o--;
    }
    return o;
  }

  int _stepRight(int c, int n) {
    var o = c;
    for (var i = 0; i < n; i++) {
      if (o < _lineEndOf(o)) o++;
    }
    return o;
  }

  int _wordForward(int c, int n) {
    final t = _text;
    var o = c;
    for (var i = 0; i < n; i++) {
      if (o >= t.length) break;
      final startedOnWord = !_isSpace(t[o]);
      if (startedOnWord) {
        final wasWord = _isWordChar(t[o]);
        while (o < t.length &&
            !_isSpace(t[o]) &&
            _isWordChar(t[o]) == wasWord) {
          o++;
        }
      }
      while (o < t.length && _isSpace(t[o])) {
        o++;
      }
    }
    return o;
  }

  int _wordBack(int c, int n) {
    final t = _text;
    var o = c;
    for (var i = 0; i < n; i++) {
      while (o > 0 && _isSpace(t[o - 1])) {
        o--;
      }
      if (o == 0) break;
      final wasWord = _isWordChar(t[o - 1]);
      while (o > 0 &&
          !_isSpace(t[o - 1]) &&
          _isWordChar(t[o - 1]) == wasWord) {
        o--;
      }
    }
    return o;
  }

  int _wordEnd(int c, int n) {
    final t = _text;
    var o = c;
    for (var i = 0; i < n; i++) {
      o++;
      while (o < t.length && _isSpace(t[o])) {
        o++;
      }
      if (o >= t.length) return t.length - (t.isEmpty ? 0 : 1);
      final wasWord = _isWordChar(t[o]);
      while (o + 1 < t.length &&
          !_isSpace(t[o + 1]) &&
          _isWordChar(t[o + 1]) == wasWord) {
        o++;
      }
    }
    return o;
  }

  // ---- Caret / selection updates ----

  void _collapseTo(int offset) {
    editor.editing.selection =
        TextSelection.collapsed(offset: offset.clamp(0, _text.length));
  }

  void _moveCaret(int Function(int) motion) {
    final target = motion(_caret).clamp(0, _text.length);
    if (_mode == VimMode.visual || _mode == VimMode.visualLine) {
      _syncVisualSelection(target);
    } else {
      _collapseTo(target);
    }
  }

  /// Visual selections keep the raw cursor in [extent]-space so motions
  /// stay anchored; charwise is end-inclusive like the modal convention.
  int _visualCursor = 0;

  void _syncVisualSelection(int cursor) {
    _visualCursor = cursor.clamp(0, _text.length);
    final t = _text;
    int start;
    int end;
    if (_mode == VimMode.visualLine) {
      start = _lineStartOf(_anchor < _visualCursor ? _anchor : _visualCursor);
      end = _lineEndOf(_anchor > _visualCursor ? _anchor : _visualCursor);
    } else {
      start = _anchor < _visualCursor ? _anchor : _visualCursor;
      end = (_anchor > _visualCursor ? _anchor : _visualCursor) + 1;
    }
    editor.editing.selection = TextSelection(
      baseOffset: start.clamp(0, t.length),
      extentOffset: end.clamp(0, t.length),
    );
  }

  void _moveVertical({required bool down, required int n}) {
    for (var i = 0; i < n; i++) {
      final t = _text;
      final c = _caret;
      final ls = _lineStartOf(c);
      final column = c - ls;
      if (down) {
        final le = _lineEndOf(c);
        if (le < t.length) {
          final nextEnd = _lineEndOf(le + 1);
          _moveCaret((_) => (le + 1 + column).clamp(le + 1, nextEnd));
          continue;
        }
      } else {
        if (ls > 0) {
          final prevStart = _lineStartOf(ls - 1);
          _moveCaret((_) => (prevStart + column).clamp(prevStart, ls - 1));
          continue;
        }
      }
      // Block edge: cross into the neighbouring block (normal mode only).
      if (_mode != VimMode.normal) return;
      _crossBlock(down: down, column: column);
      return;
    }
  }

  void _crossBlock({required bool down, required int column}) {
    final doc = editor.docCtrl.doc;
    final id = editor.focusedBlockId;
    if (id == null) return;
    final i = doc.indexOfBlock(id);
    final j = down ? i + 1 : i - 1;
    if (i < 0 || j < 0 || j >= doc.blocks.length) return;
    final target = doc.blocks[j];
    final src = target.source;
    int offset;
    if (down) {
      final firstEnd = src.indexOf('\n');
      offset = column.clamp(0, firstEnd < 0 ? src.length : firstEnd);
    } else {
      final lastStart = src.lastIndexOf('\n') + 1;
      offset = (lastStart + column).clamp(lastStart, src.length);
    }
    editor.focusBlock(target.id, offset: offset);
  }

  void _jumpDocument({required bool top}) {
    final blocks = editor.docCtrl.doc.blocks;
    if (blocks.isEmpty) return;
    final target = top ? blocks.first : blocks.last;
    editor.focusBlock(target.id,
        offset: top ? 0 : target.source.length);
    if (_mode != VimMode.normal) _setMode(VimMode.normal);
  }

  // ---- Edits ----

  void _escapeFromInsert() {
    _setMode(VimMode.normal);
    final c = _caret;
    final ls = _lineStartOf(c);
    if (c > ls) _collapseTo(c - 1);
  }

  /// Source range covered by an operator's motion, or null for motions
  /// that don't pair with operators.
  (int, int)? _motionRange(String motion, int n) {
    final c = _caret;
    switch (motion) {
      case 'w':
        return (c, _wordForward(c, n));
      case 'e':
        return (c, (_wordEnd(c, n) + 1).clamp(0, _text.length));
      case 'b':
        return (_wordBack(c, n), c);
      case 'h':
        return (_stepLeft(c, n), c);
      case 'l':
        return (c, _stepRight(c, n));
      case '\$':
        return (c, _lineEndOf(c));
      case '0':
        return (_lineStartOf(c), c);
      case '^':
        return (_firstNonBlank(c), c);
      default:
        return null;
    }
  }

  void _applyOperator(String op, int from, int to) {
    if (to <= from) {
      if (op == 'c') _setMode(VimMode.insert);
      return;
    }
    _register = _text.substring(from, to);
    _registerLinewise = false;
    if (op == 'y') {
      _collapseTo(from);
      return;
    }
    editor.replaceRange(from, to, '',
        kind: op == 'c' ? EditKind.typing : EditKind.deleteFwd);
    if (op == 'c') _setMode(VimMode.insert);
  }

  /// dd / cc / yy — whole current line.
  void _lineOperator(String op) {
    final range = editor.caretLineRange();
    if (range == null) return;
    final t = _text;
    _register = t.substring(range.start, range.end);
    _registerLinewise = true;
    switch (op) {
      case 'y':
        _collapseTo(range.start);
      case 'c':
        editor.replaceRange(range.start, range.end, '',
            caretAt: range.start);
        _setMode(VimMode.insert);
      case 'd':
        if (!t.contains('\n')) {
          _deleteWholeBlock();
        } else {
          editor.removeLine(range.start, range.end);
        }
    }
  }

  /// dd on a single-line block removes the block itself, like deleting
  /// the only line removes it from a buffer.
  void _deleteWholeBlock() {
    final doc = editor.docCtrl.doc;
    final id = editor.focusedBlockId;
    if (id == null) return;
    final i = doc.indexOfBlock(id);
    if (i < 0) return;
    if (doc.blocks.length == 1) {
      editor.replaceRange(0, _text.length, '', caretAt: 0);
      return;
    }
    final block = doc.blocks[i];
    final next = i + 1 < doc.blocks.length ? doc.blocks[i + 1] : null;
    if (next != null) {
      // The follower inherits the removed block's separator, or the
      // deleted line's blank lines would survive it.
      editor.docCtrl.spliceBlocks(
        index: i,
        before: [block, next],
        after: [
          Block(
            id: next.id,
            kind: next.kind,
            source: next.source,
            blankLinesBefore: block.blankLinesBefore,
          ),
        ],
        kind: EditKind.blockOp,
        caretBefore: CaretSnapshot(block.id, 0),
        caretAfter: CaretSnapshot(next.id, 0),
      );
      editor.focusBlock(next.id, offset: 0);
    } else {
      final prev = doc.blocks[i - 1];
      editor.docCtrl.spliceBlocks(
        index: i,
        before: [block],
        after: const [],
        kind: EditKind.blockOp,
        caretBefore: CaretSnapshot(block.id, 0),
        caretAfter: CaretSnapshot(prev.id, 0),
      );
      editor.focusBlock(prev.id, offset: 0);
    }
  }

  void _deleteAtCaret(int n, {required bool before}) {
    final c = _caret;
    final from = before ? _stepLeft(c, n) : c;
    final to = before ? c : _stepRight(c, n);
    if (to <= from) return;
    _register = _text.substring(from, to);
    _registerLinewise = false;
    editor.replaceRange(from, to, '', kind: EditKind.deleteFwd);
  }

  void _replaceChar(String ch) {
    if (ch.length != 1) return;
    final c = _caret;
    if (c >= _lineEndOf(c)) return;
    editor.replaceRange(c, c + 1, ch, caretAt: c);
  }

  void _paste({required bool after}) {
    if (_register.isEmpty) return;
    if (_registerLinewise) {
      if (after) {
        final le = _lineEndOf(_caret);
        editor.replaceRange(le, le, '\n$_register', caretAt: le + 1);
      } else {
        final ls = _lineStartOf(_caret);
        editor.replaceRange(ls, ls, '$_register\n', caretAt: ls);
      }
    } else {
      final at = after ? (_caret + 1).clamp(0, _lineEndOf(_caret)) : _caret;
      editor.replaceRange(at, at, _register);
    }
  }

  void _openLine({required bool above}) {
    final c = _caret;
    if (above) {
      final ls = _lineStartOf(c);
      final blocksBefore = editor.docCtrl.doc.blocks.length;
      final idBefore = editor.focusedBlockId;
      _collapseTo(ls);
      editor.handleEnter();
      if (editor.docCtrl.doc.blocks.length > blocksBefore &&
          idBefore != null) {
        // The block split: the empty half sits above the focused one.
        final i = editor.docCtrl.doc.indexOfBlock(editor.focusedBlockId!);
        if (i > 0) {
          final aboveBlock = editor.docCtrl.doc.blocks[i - 1];
          editor.focusBlock(aboveBlock.id,
              offset: aboveBlock.source.length);
        }
      } else {
        _collapseTo(ls);
      }
    } else {
      _collapseTo(_lineEndOf(c));
      editor.handleEnter();
    }
    _setMode(VimMode.insert);
  }

  void _deleteVisual({required bool insertAfter}) {
    final sel = editor.editing.selection;
    if (!sel.isValid || sel.isCollapsed) {
      _setMode(insertAfter ? VimMode.insert : VimMode.normal);
      return;
    }
    final t = _text;
    var end = sel.end;
    // Linewise delete removes the trailing newline too.
    if (_mode == VimMode.visualLine &&
        !insertAfter &&
        end < t.length &&
        t[end] == '\n') {
      end++;
    }
    _register = t.substring(sel.start, sel.end);
    _registerLinewise = _mode == VimMode.visualLine;
    editor.replaceRange(sel.start, end, '',
        kind: insertAfter ? EditKind.typing : EditKind.deleteFwd);
    _setMode(insertAfter ? VimMode.insert : VimMode.normal);
  }

  void _yankVisual() {
    final sel = editor.editing.selection;
    if (sel.isValid && !sel.isCollapsed) {
      _register = _text.substring(sel.start, sel.end);
      _registerLinewise = _mode == VimMode.visualLine;
      _collapseTo(sel.start);
    }
    _setMode(VimMode.normal);
  }
}
