/// TextEditingController for the focused block: the text IS the block's raw
/// markdown source, and [buildTextSpan] live-styles it (bold shown bold with
/// its `**` markers visible but dimmed, heading sized with `#` dimmed, …).
library;

import 'package:flutter/widgets.dart';

import '../document/block.dart';
import '../document/block_splitter.dart';
import 'inline_renderer.dart';

class MarkdownEditingController extends TextEditingController {
  /// Swapped by the editor when the theme changes.
  InlineRenderer? renderer;

  /// Kind of the focused block; used as a fallback when the current text no
  /// longer scans as a single block (mid-edit states).
  BlockKind fallbackKind = BlockKind.paragraph;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final r = renderer;
    if (r == null || text.isEmpty) {
      return TextSpan(style: style, text: text);
    }
    // Re-derive the kind from the live text so styling tracks the keystroke,
    // not the (async-updated) document state.
    final kind = deriveSingleKind(text) ?? fallbackKind;
    final level = kind == BlockKind.heading
        ? Block(kind: kind, source: text).headingLevel
        : 1;
    // Composing-region underline (IME) is intentionally not rendered; the
    // span must still cover the full text exactly, which buildEditingSpan
    // guarantees.
    return r.buildEditingSpan(text, kind, headingLevel: level);
  }
}
