/// The focused block: a borderless TextField over the block's raw source,
/// live-styled by [MarkdownEditingController], with the structural keys
/// (Enter, Backspace-at-0, Tab, edge arrows, Escape) intercepted before the
/// field's defaults.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';

import '../document/block.dart';
import 'block_padding.dart';
import 'editor_controller.dart';

class EditingBlock extends StatefulWidget {
  const EditingBlock({super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  @override
  State<EditingBlock> createState() => _EditingBlockState();
}

class _EditingBlockState extends State<EditingBlock> {
  // Thrown away on every focus change; never consulted (document-level undo).
  final _fieldUndo = UndoHistoryController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealIfOffscreen();
    });
  }

  /// Scroll only when the block is not already fully visible — clicking a
  /// block in the middle of the viewport must not move the page.
  void _revealIfOffscreen() {
    final render = context.findRenderObject();
    if (render == null) return;
    final viewport = RenderAbstractViewport.maybeOf(render);
    final scrollable = Scrollable.maybeOf(context);
    if (viewport == null || scrollable == null) {
      return;
    }
    final position = scrollable.position;
    // Fully visible iff offsetToReveal(1.0) <= pixels <= offsetToReveal(0.0).
    final top = viewport.getOffsetToReveal(render, 0.0).offset;
    final bottom = viewport.getOffsetToReveal(render, 1.0).offset;
    if (bottom > top) {
      // Taller than the viewport — it was clicked, so it is on screen.
      return;
    }
    if (position.pixels >= bottom - 0.5 && position.pixels <= top + 0.5) {
      return;
    }
    Scrollable.ensureVisible(context,
        alignment: 0.4, duration: const Duration(milliseconds: 120));
  }

  @override
  void dispose() {
    _fieldUndo.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final editor = widget.editor;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final modified = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed;
    if (modified) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return editor.handleEnter(shift: shift)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.backspace && !shift) {
      return editor.handleBackspaceAtStart()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.delete && !shift) {
      return editor.handleDeleteAtEnd()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.tab) {
      return editor.handleTab(shift: shift)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp && !shift) {
      if (editor.caretOnEdgeLine(first: true) &&
          editor.moveVertical(up: true)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown && !shift) {
      if (editor.caretOnEdgeLine(first: false) &&
          editor.moveVertical(up: false)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      editor.blur();
      // Keep keyboard focus on the editor surface.
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final theme = editor.theme;
    final block = widget.block;
    final style = editor.renderer.editingBaseStyle(block);
    final isOnlyEmptyBlock = block.source.isEmpty &&
        editor.docCtrl.doc.blocks.length == 1;
    final align = block.kind == BlockKind.heading
        ? theme.headingAligns[(block.headingLevel - 1).clamp(0, 5)]
        : TextAlign.start;

    return Padding(
      padding: blockPadding(block, theme),
      child: Focus(
        onKeyEvent: _onKey,
        child: TextField(
          controller: editor.editing,
          focusNode: editor.focusNode,
          undoController: _fieldUndo,
          maxLines: null,
          style: style,
          textAlign: align,
          cursorColor: theme.caret,
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: isOnlyEmptyBlock ? 'Type here…' : null,
            hintStyle: theme.bodyStyle.copyWith(color: theme.hintColor),
          ),
        ),
      ),
    );
  }
}
