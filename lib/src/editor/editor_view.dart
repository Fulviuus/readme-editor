/// The editor surface: a lazy block list; exactly one block renders as an
/// editable TextField, the rest render fully. A focus move rebuilds two
/// items, not the whole list (per-item focus flags).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../document/block.dart';
import 'block_padding.dart';
import 'editing_block.dart';
import 'editor_controller.dart';
import 'rendered_block.dart';

class EditorView extends StatefulWidget {
  const EditorView({super.key, required this.editor});

  final EditorController editor;

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final _scrollController = ScrollController();

  EditorController get editor => widget.editor;

  @override
  void initState() {
    super.initState();
    editor.docCtrl.addListener(_onModelChanged);
    editor.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    editor.docCtrl.removeListener(_onModelChanged);
    editor.removeListener(_onModelChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  /// Formatting/undo shortcuts. On native macOS the PlatformMenuBar owns
  /// these accelerators (the engine routes key equivalents to the menu), so
  /// binding them here would double-fire.
  Map<ShortcutActivator, VoidCallback> get _bindings {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) return {};
    final meta = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator cmd(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: meta, control: !meta, shift: shift);
    return {
      cmd(LogicalKeyboardKey.keyB): editor.toggleBold,
      cmd(LogicalKeyboardKey.keyI): editor.toggleItalic,
      cmd(LogicalKeyboardKey.keyE): editor.toggleCode,
      cmd(LogicalKeyboardKey.keyD, shift: true): editor.toggleStrikethrough,
      cmd(LogicalKeyboardKey.keyK): editor.insertLink,
      cmd(LogicalKeyboardKey.keyZ): editor.undo,
      cmd(LogicalKeyboardKey.keyZ, shift: true): editor.redo,
      for (var n = 0; n <= 6; n++)
        cmd(LogicalKeyboardKey(0x30 + n)): () => editor.setHeadingLevel(n),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = editor.theme;
    final blocks = editor.docCtrl.doc.blocks;
    final idToIndex = <String, int>{
      for (var i = 0; i < blocks.length; i++) blocks[i].id: i,
    };

    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent ||
            !editor.wheelZoom ||
            !HardwareKeyboard.instance.isMetaPressed) {
          return;
        }
        editor.onWheelZoom?.call(event.scrollDelta.dy < 0);
      },
      child: ColoredBox(
      color: theme.background,
      child: CallbackShortcuts(
        bindings: _bindings,
        child: Theme(
          data: Theme.of(context).copyWith(
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: theme.caret,
              selectionColor: theme.selectionBackground,
            ),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final contentWidth =
                (constraints.maxWidth - 96).clamp(200.0, theme.contentMaxWidth);
            editor.contentWidth = contentWidth;
            return ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: true),
              // Cross-block selection: rendered blocks register into this
              // area, so a mouse drag selects across blocks and Cmd+C
              // copies the rendered text. The focused block's TextField
              // keeps its own selection; plain clicks still focus blocks.
              child: SelectionArea(
                child: ListView.builder(
                controller: _scrollController,
                // Typewriter mode pads by half a viewport so the first and
                // last lines can still be centered.
                padding: EdgeInsets.symmetric(
                    vertical: editor.typewriterModeEnabled
                        ? constraints.maxHeight / 2
                        : 48),
                itemCount: blocks.length + 1,
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> ? idToIndex[key.value] : null,
                itemBuilder: (context, i) {
                  if (i == blocks.length) {
                    // Click-below-the-end area (§8).
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: editor.focusTail,
                      child: const SizedBox(height: 280),
                    );
                  }
                  final block = blocks[i];
                  return KeyedSubtree(
                    key: ValueKey<String>(block.id),
                    // Tight width: blocks that shrink-wrap (a short
                    // paragraph) must still fill the column, not center.
                    child: Center(
                      child: SizedBox(
                        width: contentWidth,
                        child: _BlockItem(block: block, editor: editor),
                      ),
                    ),
                  );
                },
                ),
              ),
            );
          }),
        ),
      ),
      ),
    );
  }
}

class _BlockItem extends StatelessWidget {
  const _BlockItem({required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  /// Clicks landing on the block's own vertical padding — the visual gap
  /// between blocks — open a new line there. Content clicks never reach
  /// this handler (the block's inner detectors win the gesture arena).
  void _onGapTap(BuildContext context, TapUpDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final dy = box.globalToLocal(details.globalPosition).dy;
    final pad = blockPadding(block, editor.theme);
    final index = editor.docCtrl.doc.indexOfBlock(block.id);
    if (index < 0) return;
    if (dy <= pad.top) {
      editor.focusGap(index);
    } else if (dy >= box.size.height - pad.bottom) {
      editor.focusGap(index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: editor.focusFlag(block.id),
      builder: (context, focused, _) {
        Widget child = focused
            ? EditingBlock(block: block, editor: editor)
            : RenderedBlock(block: block, editor: editor);
        child = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) => _onGapTap(context, d),
          child: child,
        );
        if (!editor.focusModeEnabled) return child;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: focused || editor.focusedBlockId == null ? 1.0 : 0.4,
          child: child,
        );
      },
    );
  }
}
