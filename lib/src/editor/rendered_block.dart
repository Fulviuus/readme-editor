/// Rendered (unfocused) block widgets. Clicking anywhere maps the hit back
/// to a source offset (via the block's OffsetRuns) and focuses the block
/// there — the core hybrid-editing gesture.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import '../document/block.dart';
import '../theme/readme_theme.dart';
import 'block_padding.dart';
import 'blocks/code_block.dart';
import 'blocks/list_block.dart';
import 'blocks/table_block.dart';
import 'editor_controller.dart';
import 'inline_tokenizer.dart';
import 'offset_runs.dart';

class RenderedBlock extends StatelessWidget {
  const RenderedBlock({super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  void _focusAt(int sourceOffset) =>
      editor.focusBlock(block.id, offset: sourceOffset);

  @override
  Widget build(BuildContext context) {
    final theme = editor.theme;
    final child = switch (block.kind) {
      BlockKind.paragraph => _paragraph(theme),
      BlockKind.heading => _heading(theme),
      BlockKind.blockquote => _blockquote(theme),
      BlockKind.thematicBreak => _thematicBreak(theme),
      BlockKind.list => ListBlockView(block: block, editor: editor),
      BlockKind.table => TableBlockView(block: block, editor: editor),
      BlockKind.fencedCode ||
      BlockKind.indentedCode =>
        CodeBlockView(block: block, editor: editor),
      BlockKind.mathBlock => _verbatimBox(theme, label: 'math'),
      BlockKind.html => _verbatimBox(theme, label: 'html'),
      BlockKind.frontMatter => _verbatimBox(theme, label: 'front matter'),
    };
    return Padding(padding: blockPadding(block, theme), child: child);
  }

  Widget _paragraph(ReadmeTheme theme) {
    // A paragraph that is exactly one image renders as an image block.
    final nodes = tokenizeInline(block.source);
    if (nodes.length == 1 && nodes.first is ImageNode) {
      final img = nodes.first as ImageNode;
      final w = editor.renderer.imageBuilder?.call(img.url, img.alt);
      if (w != null) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusAt(block.source.length),
          child: Center(child: w),
        );
      }
    }
    final r = editor.renderer
        .renderInline(block.source, baseStyle: theme.bodyStyle);
    return TappableInlineText(
      span: r.span,
      runs: r.runs,
      onCaret: _focusAt,
    );
  }

  Widget _heading(ReadmeTheme theme) {
    final level = block.headingLevel;
    final style = theme.headingStyle(level);
    final align = theme.headingAligns[(level - 1).clamp(0, 5)];

    final String content;
    final int contentStart;
    final int contentEnd;
    if (block.isSetextHeading) {
      final lines = block.source.split('\n');
      content = lines.sublist(0, lines.length - 1).join('\n');
      contentStart = 0;
      contentEnd = content.length;
    } else {
      final m = RegExp(r'^ {0,3}#{1,6}[ \t]*').firstMatch(block.source);
      contentStart = m?.end ?? 0;
      final trailing =
          RegExp(r'[ \t]+#+[ \t]*$').firstMatch(block.source)?.start ??
              block.source.length;
      contentEnd = trailing < contentStart ? block.source.length : trailing;
      content = block.source.substring(contentStart, contentEnd);
    }

    final r = editor.renderer.renderInline(content, baseStyle: style);
    final runs = <OffsetRun>[
      if (contentStart > 0) OffsetRun(RunKind.hidden, 0, 0, 0, contentStart),
      for (final run in r.runs)
        OffsetRun(run.kind, run.rStart, run.rEnd, run.sStart + contentStart,
            run.sEnd + contentStart),
      if (contentEnd < block.source.length)
        OffsetRun(RunKind.hidden, r.renderedText.length, r.renderedText.length,
            contentEnd, block.source.length),
    ];

    Widget text = TappableInlineText(
      span: r.span,
      runs: runs,
      onCaret: _focusAt,
      textAlign: align,
    );
    final border = level == 1
        ? (theme.h1BorderBottom, theme.h1BorderWidth)
        : level == 2
            ? (theme.h2BorderBottom, theme.h2BorderWidth)
            : (null, 0.0);
    if (border.$1 != null && border.$2 > 0) {
      text = Container(
        width: double.infinity,
        padding: EdgeInsets.only(bottom: theme.fontSize * 0.3),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: border.$1!, width: border.$2)),
        ),
        child: text,
      );
    } else {
      text = SizedBox(width: double.infinity, child: text);
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _focusAt(block.source.length),
      child: text,
    );
  }

  Widget _blockquote(ReadmeTheme theme) {
    final style = theme.bodyStyle.copyWith(
      color: theme.blockquoteTextColor,
      fontStyle: theme.blockquoteItalic ? FontStyle.italic : null,
    );
    final lines = block.source.split('\n');
    final rows = <Widget>[];
    var lineStart = 0;
    final prefixRe = RegExp(r'^ {0,3}(?:> ?)+');
    for (final line in lines) {
      final m = prefixRe.firstMatch(line);
      final prefixLen = m?.end ?? 0;
      final content = line.substring(prefixLen);
      final r = editor.renderer.renderInline(content, baseStyle: style);
      final base = lineStart + prefixLen;
      final runs = <OffsetRun>[
        if (prefixLen > 0)
          OffsetRun(RunKind.hidden, 0, 0, lineStart, base),
        for (final run in r.runs)
          OffsetRun(run.kind, run.rStart, run.rEnd, run.sStart + base,
              run.sEnd + base),
      ];
      rows.add(TappableInlineText(span: r.span, runs: runs, onCaret: _focusAt));
      lineStart += line.length + 1;
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
          left: theme.fontSize * 0.9,
          top: theme.fontSize * 0.15,
          bottom: theme.fontSize * 0.15),
      decoration: BoxDecoration(
        color: theme.blockquoteBackground,
        border: Border(
          left: BorderSide(
              color: theme.blockquoteBorder,
              width: theme.blockquoteBorderWidth),
        ),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _thematicBreak(ReadmeTheme theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusAt(block.source.length),
      child: Container(
        height: theme.hrHeight,
        margin: EdgeInsets.symmetric(vertical: theme.fontSize * 0.3),
        color: theme.hr,
      ),
    );
  }

  Widget _verbatimBox(ReadmeTheme theme, {required String label}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusAt(block.source.length),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(theme.fontSize * 0.75),
        decoration: BoxDecoration(
          color: theme.codeBlockBackground ??
              theme.foreground.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(theme.codeBlockRadius),
          border: theme.codeBlockBorder != null
              ? Border.all(color: theme.codeBlockBorder!)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.monoStyle.copyWith(
                    fontSize: theme.fontSize * 0.65,
                    color: theme.hintColor)),
            Text(block.source, style: theme.monoStyle),
          ],
        ),
      ),
    );
  }
}

/// RichText that maps a tap to a source offset through its [OffsetRun]s.
class TappableInlineText extends StatefulWidget {
  const TappableInlineText({
    super.key,
    required this.span,
    required this.runs,
    required this.onCaret,
    this.textAlign = TextAlign.start,
  });

  final InlineSpan span;
  final List<OffsetRun> runs;
  final ValueChanged<int> onCaret;
  final TextAlign textAlign;

  @override
  State<TappableInlineText> createState() => _TappableInlineTextState();
}

class _TappableInlineTextState extends State<TappableInlineText> {
  final _textKey = GlobalKey();

  void _onTapUp(TapUpDetails details) {
    final render =
        _textKey.currentContext?.findRenderObject() as RenderParagraph?;
    if (render == null) return;
    final local = render.globalToLocal(details.globalPosition);
    final position = render.getPositionForOffset(local);
    widget.onCaret(renderedToSource(widget.runs, position.offset));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: _onTapUp,
      child: RichText(
        key: _textKey,
        text: widget.span,
        textAlign: widget.textAlign,
      ),
    );
  }
}
