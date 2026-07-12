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
import 'blocks/table_block.dart';
import 'editor_controller.dart';
import 'spell/spell_checker.dart';

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
    widget.editor.editing.addListener(_onEditingChangedForTypewriter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealIfOffscreen();
    });
  }

  /// Typewriter mode: keep the caret line vertically centered while typing
  /// or moving the caret (docs/DESIGN-editor-interaction.md §9).
  void _onEditingChangedForTypewriter() {
    if (!widget.editor.typewriterModeEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final render = context.findRenderObject();
      final viewport =
          render == null ? null : RenderAbstractViewport.maybeOf(render);
      final scrollable = Scrollable.maybeOf(context);
      if (render == null || viewport == null || scrollable == null) return;
      final position = scrollable.position;
      final blockTop = viewport.getOffsetToReveal(render, 0.0).offset;
      final caretDy = widget.editor.caretDyInFocusedBlock();
      final lineHalf = widget.editor.theme.fontSize * 0.75;
      final target = (blockTop + caretDy + lineHalf -
              position.viewportDimension / 2)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      // Relaxed centering: only recenter once the caret drifts well away
      // from the middle (Preferences > Editor > Typewriter Mode).
      final threshold = widget.editor.typewriterCenterAlways
          ? 2.0
          : position.viewportDimension * 0.25;
      if ((target - position.pixels).abs() < threshold) return;
      position.animateTo(target,
          duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
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
    widget.editor.editing.removeListener(_onEditingChangedForTypewriter);
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

    // Tables never drop to raw source in the live editor: the focused table
    // stays rendered and the active cell is edited in place.
    if (block.kind == BlockKind.table) {
      return Padding(
        padding: blockPadding(block, theme),
        child: TableBlockView(block: block, editor: editor, editing: true),
      );
    }

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
          contextMenuBuilder: (context, state) =>
              _SpellAwareContextMenu(state: state, editor: editor),
        ),
      ),
    );
  }
}

/// The field's context menu, with spelling suggestions prepended when the
/// click landed on a misspelled word.
class _SpellAwareContextMenu extends StatelessWidget {
  const _SpellAwareContextMenu({required this.state, required this.editor});

  final EditableTextState state;
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final sel = state.textEditingValue.selection;
    final range =
        sel.isValid ? editor.misspellingAt(sel.baseOffset) : null;
    final defaults = AdaptiveTextSelectionToolbar.editableText(
        editableTextState: state);
    if (range == null) return defaults;
    final word = state.textEditingValue.text
        .substring(range.start, range.end);
    return FutureBuilder<List<String>>(
      future: SpellChecker.suggest(word),
      builder: (context, snap) {
        if (!snap.hasData) return defaults;
        final items = <ContextMenuButtonItem>[
          for (final s in snap.data!.take(5))
            ContextMenuButtonItem(
              label: s,
              onPressed: () {
                state.hideToolbar();
                editor.replaceRange(range.start, range.end, s);
              },
            ),
          ContextMenuButtonItem(
            label: 'Learn Spelling',
            onPressed: () {
              state.hideToolbar();
              editor.learnWord(word);
            },
          ),
          ContextMenuButtonItem(
            label: 'Ignore Spelling',
            onPressed: () {
              state.hideToolbar();
              editor.learnWord(word, permanently: false);
            },
          ),
          ...state.contextMenuButtonItems,
        ];
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }
}
