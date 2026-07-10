/// Table block, two modes:
///
/// - RENDERED (unfocused): a [Table] widget; each cell keeps its source
///   range so a click focuses the block with the caret inside that cell.
/// - EDITING (focused): the table STAYS rendered and the active cell hosts a
///   TextField — cells are edited in place; the raw pipe source
///   never appears in the live editor (only in source mode, where it is
///   kept prettified by the controller).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../document/block.dart';
import '../editor_controller.dart';
import '../offset_runs.dart';
import '../rendered_block.dart';
import 'table_model.dart';

class TableBlockView extends StatelessWidget {
  const TableBlockView({
    super.key,
    required this.block,
    required this.editor,
    this.editing = false,
  });

  final Block block;
  final EditorController editor;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final theme = editor.theme;
    final shape = TableShape(block.source);
    if (shape.lineCount < 2) {
      return Text(block.source, style: theme.bodyStyle);
    }
    final active = editing ? editor.activeTableCell() : null;

    final tableRows = <TableRow>[];
    var dataRowIndex = 0;
    for (var li = 0; li < shape.lineCount; li++) {
      if (li == 1) continue; // delimiter row
      final isHeader = li == 0;
      final stripe = !isHeader && dataRowIndex.isOdd;
      if (!isHeader) dataRowIndex++;
      tableRows.add(TableRow(
        decoration: BoxDecoration(
          color: isHeader
              ? theme.tableHeaderBackground
              : stripe
                  ? theme.tableStripeBackground
                  : null,
        ),
        children: [
          for (var c = 0; c < shape.columnCount; c++)
            _cell(shape, li, c,
                isHeader: isHeader,
                isActive: active != null &&
                    active.$1 == li &&
                    active.$2 == c),
        ],
      ));
    }

    Widget table = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: theme.tableBorder != null
          ? TableBorder.all(color: theme.tableBorder!, width: 1)
          : null,
      children: tableRows,
    );
    if (editing) {
      // Subtle focus ring so the active table is recognizable.
      table = Container(
        decoration: BoxDecoration(
          border: Border.all(
              color: theme.accent.withValues(alpha: 0.35), width: 1),
        ),
        child: table,
      );
    }
    return table;
  }

  Widget _cell(TableShape shape, int row, int col,
      {required bool isHeader, required bool isActive}) {
    final theme = editor.theme;
    final style = isHeader
        ? theme.bodyStyle.copyWith(fontWeight: FontWeight.w700)
        : theme.bodyStyle;
    final align =
        col < shape.alignments.length ? shape.alignments[col] : TextAlign.left;
    final padding =
        EdgeInsets.symmetric(horizontal: 10, vertical: theme.fontSize * 0.35);

    if (isActive) {
      return Padding(
        padding: padding,
        child: TableCellEditor(
          key: ValueKey('cell-$row-$col'),
          editor: editor,
          shape: shape,
          row: row,
          col: col,
          style: style,
          textAlign: align,
        ),
      );
    }

    final hasContent = col < shape.cellsOnLine(row).length;
    final text = hasContent ? shape.textOf(row, col) : '';
    final (start, _) = shape.rangeOf(row, col);
    final r = editor.renderer.renderInline(text, baseStyle: style);
    final runs = [
      for (final run in r.runs)
        OffsetRun(run.kind, run.rStart, run.rEnd, run.sStart + start,
            run.sEnd + start),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => editing
          ? editor.focusTableCell(block.id, row, col)
          : editor.focusBlock(block.id, offset: start),
      child: Padding(
        padding: padding,
        child: TappableInlineText(
          span: r.span,
          runs: runs,
          links: r.links,
          onOpenLink: editor.openLink,
          textAlign: align,
          onCaret: (offset) => editor.focusBlock(block.id, offset: offset),
        ),
      ),
    );
  }
}

/// The active cell: a bare TextField over the CELL text only. Edits are
/// pushed to the controller, which splices them into the table source and
/// re-prettifies it; navigation keys move between cells.
class TableCellEditor extends StatefulWidget {
  const TableCellEditor({
    super.key,
    required this.editor,
    required this.shape,
    required this.row,
    required this.col,
    required this.style,
    required this.textAlign,
  });

  final EditorController editor;
  final TableShape shape;
  final int row;
  final int col;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  State<TableCellEditor> createState() => _TableCellEditorState();
}

class _TableCellEditorState extends State<TableCellEditor> {
  late final TextEditingController _cell;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    final (a, b) = widget.shape.rangeOf(widget.row, widget.col);
    final text = widget.editor.editing.text.substring(a, b);
    final sel = widget.editor.editing.selection;
    TextSelection local;
    if (sel.isValid && sel.start >= a && sel.end <= b) {
      local = TextSelection(
          baseOffset: sel.baseOffset - a, extentOffset: sel.extentOffset - a);
    } else {
      local = TextSelection(baseOffset: 0, extentOffset: text.length);
    }
    _cell = TextEditingController.fromValue(
        TextEditingValue(text: text, selection: local));
    _cell.addListener(_onCellChanged);
  }

  @override
  void didUpdateWidget(TableCellEditor old) {
    super.didUpdateWidget(old);
    // External change (undo/redo) rewrote the cell under us.
    final (a, b) = widget.shape.rangeOf(widget.row, widget.col);
    final text = widget.editor.editing.text.substring(a, b);
    if (!_pushing && text != _cell.text) {
      _cell.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
            offset: text.length.clamp(0, text.length)),
      );
    }
  }

  @override
  void dispose() {
    _cell.removeListener(_onCellChanged);
    _cell.dispose();
    super.dispose();
  }

  void _onCellChanged() {
    if (_pushing) return;
    final (a, b) = widget.shape.rangeOf(widget.row, widget.col);
    final current = widget.editor.editing.text.substring(a, b);
    if (_cell.text == current) return;
    _pushing = true;
    widget.editor
        .updateActiveTableCell(_cell.text, _cell.selection.baseOffset);
    _pushing = false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final editor = widget.editor;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.tab) {
      return editor.handleTab(shift: shift)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (shift) {
        final at = _cell.selection.baseOffset.clamp(0, _cell.text.length);
        _cell.value = TextEditingValue(
          text: _cell.text.replaceRange(at, at, '<br>'),
          selection: TextSelection.collapsed(offset: at + 4),
        );
        return KeyEventResult.handled;
      }
      return editor.handleEnter()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      editor.blur();
      node.unfocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && !shift) {
      editor.moveTableCellVertically(up: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && !shift) {
      editor.moveTableCellVertically(up: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft &&
        !shift &&
        _cell.selection.isCollapsed &&
        _cell.selection.baseOffset == 0) {
      return editor.handleTab(shift: true)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        !shift &&
        _cell.selection.isCollapsed &&
        _cell.selection.baseOffset == _cell.text.length) {
      return editor.handleTab()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.editor.theme;
    return Focus(
      onKeyEvent: _onKey,
      child: TextField(
        controller: _cell,
        focusNode: widget.editor.focusNode,
        autofocus: true,
        maxLines: 1,
        style: widget.style,
        textAlign: widget.textAlign,
        cursorColor: theme.caret,
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
        ),
      ),
    );
  }
}
