/// Rendered (unfocused) block widgets. Clicking anywhere maps the hit back
/// to a source offset (via the block's OffsetRuns) and focuses the block
/// there — the core hybrid-editing gesture.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart' show Math, MathStyle;

import '../document/block.dart';
import '../theme/readme_theme.dart';
import 'block_padding.dart';
import 'blocks/code_block.dart';
import 'blocks/list_block.dart';
import 'blocks/mermaid_block.dart';
import 'blocks/table_block.dart';
import 'editor_controller.dart';
import 'inline_renderer.dart' show LinkRange;
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
      BlockKind.fencedCode || BlockKind.indentedCode => _code(),
      BlockKind.mathBlock => _mathBlock(theme),
      BlockKind.html => _verbatimBox(theme, label: 'html'),
      BlockKind.frontMatter => _verbatimBox(theme, label: 'front matter'),
    };
    return Padding(padding: blockPadding(block, theme), child: child);
  }

  /// A closed `mermaid` fence with content renders as a diagram; anything
  /// else (other languages, half-typed fences) is a plain code block.
  Widget _code() {
    if (block.kind == BlockKind.fencedCode &&
        block.fenceLanguage?.toLowerCase() == 'mermaid' &&
        block.fenceIsClosed &&
        block.codeBody.trim().isNotEmpty) {
      return MermaidBlockView(block: block, editor: editor);
    }
    return CodeBlockView(block: block, editor: editor);
  }

  Widget _paragraph(ReadmeTheme theme) {
    // `[TOC]` renders as a live table of contents.
    if (block.source.trim() == '[TOC]') return _toc(theme);
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
      links: r.links,
      onOpenLink: editor.openLink,
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
      links: r.links,
      onOpenLink: editor.openLink,
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

  /// `[TOC]` → a clickable outline of the document's headings.
  Widget _toc(ReadmeTheme theme) {
    final entries = editor.docCtrl.doc.outline;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _focusAt(block.source.length),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: theme.fontSize * 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entries.isEmpty)
              Text('[TOC] — no headings yet',
                  style: theme.bodyStyle.copyWith(color: theme.hintColor))
            else
              for (final e in entries)
                Padding(
                  padding: EdgeInsets.only(
                      left: (e.level - 1) * theme.fontSize * 1.1,
                      top: 2,
                      bottom: 2),
                  child: GestureDetector(
                    onTap: () => editor.focusBlock(e.blockId, offset: 0),
                    child: Text(
                      e.text.isEmpty ? '(untitled)' : e.text,
                      style: theme.bodyStyle.copyWith(
                        color: theme.link,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.link.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// GitHub-style alerts: `> [!NOTE]` on the quote's first line.
  static const _alertStyles = {
    'NOTE': (Color(0xFF0969DA), Icons.info_outline, 'Note'),
    'TIP': (Color(0xFF1A7F37), Icons.lightbulb_outline, 'Tip'),
    'IMPORTANT': (Color(0xFF8250DF), Icons.campaign_outlined, 'Important'),
    'WARNING': (Color(0xFF9A6700), Icons.warning_amber_outlined, 'Warning'),
    'CAUTION': (Color(0xFFCF222E), Icons.report_outlined, 'Caution'),
  };

  Widget _blockquote(ReadmeTheme theme) {
    final style = theme.bodyStyle.copyWith(
      color: theme.blockquoteTextColor,
      fontStyle: theme.blockquoteItalic ? FontStyle.italic : null,
    );
    final lines = block.source.split('\n');
    final rows = <Widget>[];
    var lineStart = 0;
    final prefixRe = RegExp(r'^ {0,3}(?:> ?)+');

    // Alert header: consumes the first line, colors the border.
    Color borderColor = theme.blockquoteBorder;
    final firstStripped =
        lines.first.replaceFirst(prefixRe, '').trim().toUpperCase();
    final alertMatch =
        RegExp(r'^\[!(\w+)\]$').firstMatch(firstStripped);
    final alert = alertMatch == null
        ? null
        : _alertStyles[alertMatch.group(1)];
    if (alert != null) {
      final (color, icon, label) = alert;
      borderColor = color;
      rows.add(GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focusAt(lines.first.length),
        child: Padding(
          padding: EdgeInsets.only(bottom: theme.fontSize * 0.25),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: theme.fontSize * 1.1, color: color),
            SizedBox(width: theme.fontSize * 0.4),
            Text(label,
                style: theme.bodyStyle.copyWith(
                    color: color, fontWeight: FontWeight.w600)),
          ]),
        ),
      ));
      lineStart += lines.first.length + 1;
      lines.removeAt(0);
    }

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
      rows.add(TappableInlineText(
        span: r.span,
        runs: runs,
        links: r.links,
        onOpenLink: editor.openLink,
        onCaret: _focusAt,
      ));
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
              color: borderColor, width: theme.blockquoteBorderWidth),
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

  /// `$$ … $$` renders as centered display math. Wide formulas scale down
  /// instead of overflowing; invalid TeX falls back to the source box.
  Widget _mathBlock(ReadmeTheme theme) {
    final tex = block.codeBody;
    if (tex.isEmpty) return _verbatimBox(theme, label: 'math');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusAt(block.source.length),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: theme.fontSize * 0.4),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Math.tex(
            tex,
            mathStyle: MathStyle.display,
            textStyle:
                theme.bodyStyle.copyWith(fontSize: theme.fontSize * 1.15),
            onErrorFallback: (e) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tex, style: theme.monoStyle),
                Text(e.message,
                    style: theme.monoStyle.copyWith(
                        fontSize: theme.fontSize * 0.7,
                        color: theme.hintColor)),
              ],
            ),
          ),
        ),
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
/// Links (via [links]) support Cmd/Ctrl+click to open and a right-click
/// context menu — a plain click still focuses the block for editing.
class TappableInlineText extends StatefulWidget {
  const TappableInlineText({
    super.key,
    required this.span,
    required this.runs,
    required this.onCaret,
    this.links = const [],
    this.onOpenLink,
    this.textAlign = TextAlign.start,
  });

  final InlineSpan span;
  final List<OffsetRun> runs;
  final ValueChanged<int> onCaret;
  final List<LinkRange> links;
  final ValueChanged<String>? onOpenLink;
  final TextAlign textAlign;

  @override
  State<TappableInlineText> createState() => _TappableInlineTextState();
}

class _TappableInlineTextState extends State<TappableInlineText> {
  final _textKey = GlobalKey();

  int? _renderedOffsetAt(Offset globalPosition) {
    final render =
        _textKey.currentContext?.findRenderObject() as RenderParagraph?;
    if (render == null) return null;
    final local = render.globalToLocal(globalPosition);
    return render.getPositionForOffset(local).offset;
  }

  String? _linkAt(Offset globalPosition) {
    final r = _renderedOffsetAt(globalPosition);
    if (r == null) return null;
    for (final link in widget.links) {
      if (link.contains(r)) return link.url;
    }
    return null;
  }

  void _onTapUp(TapUpDetails details) {
    final modified = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (modified && widget.onOpenLink != null) {
      final url = _linkAt(details.globalPosition);
      if (url != null) {
        widget.onOpenLink!(url);
        return;
      }
    }
    final r = _renderedOffsetAt(details.globalPosition);
    if (r == null) return;
    widget.onCaret(renderedToSource(widget.runs, r));
  }

  Future<void> _onSecondaryTapUp(TapUpDetails details) async {
    final url = _linkAt(details.globalPosition);
    if (url == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(value: 'open', child: Text('Open Link')),
        PopupMenuItem(value: 'copy', child: Text('Copy Link Address')),
      ],
    );
    switch (action) {
      case 'open':
        widget.onOpenLink?.call(url);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Register into an enclosing SelectionArea (cross-block selection);
    // RichText, unlike Text, does not opt in by itself.
    final registrar = SelectionContainer.maybeOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: _onTapUp,
      onSecondaryTapUp: widget.links.isEmpty ? null : _onSecondaryTapUp,
      child: RichText(
        key: _textKey,
        text: widget.span,
        textAlign: widget.textAlign,
        selectionRegistrar: registrar,
        selectionColor: registrar == null
            ? null
            : DefaultSelectionStyle.of(context).selectionColor ??
                Theme.of(context).textSelectionTheme.selectionColor,
      ),
    );
  }
}
