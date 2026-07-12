/// Rendered fenced/indented code block: themed container with re_highlight
/// syntax coloring. The highlighted spans preserve the body text 1:1, so
/// click→caret mapping is identity within the body.
library;

import 'package:flutter/material.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../document/block.dart';
import '../../theme/syntax_presets.dart';
import '../editor_controller.dart';
import '../offset_runs.dart';
import '../rendered_block.dart';

/// One engine for the app; language registration is not cheap, so do it once
/// and lazily.
Highlight? _engine;

Highlight _highlightEngine() {
  if (_engine == null) {
    _engine = Highlight();
    _engine!.registerLanguages(builtinAllLanguages);
  }
  return _engine!;
}

class CodeBlockView extends StatelessWidget {
  const CodeBlockView({super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  Widget _codeText(TextSpan span, List<OffsetRun> runs, TextStyle mono,
      {required bool wrap}) {
    return TappableInlineText(
      span: block.kind == BlockKind.indentedCode
          ? TextSpan(text: block.source, style: mono)
          : span,
      runs: runs,
      softWrap: wrap,
      onCaret: (offset) => editor.focusBlock(block.id, offset: offset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = editor.theme;
    final mono = theme.monoStyle;
    final body = block.codeBody;
    final language = block.fenceLanguage;

    TextSpan span;
    try {
      final engine = _highlightEngine();
      final result = language != null &&
              builtinAllLanguages.containsKey(language.toLowerCase())
          ? engine.highlight(
              code: body,
              language: language.toLowerCase(),
              ignoreIllegals: true)
          : engine.justTextHighlightResult(body);
      final renderer = TextSpanRenderer(mono, syntaxThemeFor(theme, mono));
      result.render(renderer);
      span = renderer.span ?? TextSpan(text: body, style: mono);
    } catch (_) {
      span = TextSpan(text: body, style: mono);
    }

    // Source offsets of the body inside the block (after the opening fence).
    final int bodyStart;
    final int bodyEnd;
    if (block.kind == BlockKind.fencedCode) {
      final firstNl = block.source.indexOf('\n');
      bodyStart = firstNl < 0 ? block.source.length : firstNl + 1;
      bodyEnd = bodyStart + body.length;
    } else {
      bodyStart = 0;
      bodyEnd = block.source.length;
    }
    final displayBody =
        block.kind == BlockKind.indentedCode ? block.source : body;
    final runs = <OffsetRun>[
      if (bodyStart > 0) OffsetRun(RunKind.hidden, 0, 0, 0, bodyStart),
      OffsetRun(RunKind.text, 0, displayBody.length, bodyStart, bodyEnd),
      if (bodyEnd < block.source.length)
        OffsetRun(RunKind.hidden, displayBody.length, displayBody.length,
            bodyEnd, block.source.length),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => editor.focusBlock(block.id, offset: bodyStart),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
            horizontal: theme.fontSize * 0.9, vertical: theme.fontSize * 0.7),
        decoration: BoxDecoration(
          color: theme.codeBlockBackground,
          borderRadius: BorderRadius.circular(theme.codeBlockRadius),
          border: theme.codeBlockBorder != null
              ? Border.all(color: theme.codeBlockBorder!)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (language != null)
              Padding(
                padding: EdgeInsets.only(bottom: theme.fontSize * 0.3),
                child: Text(
                  language,
                  style: mono.copyWith(
                      fontSize: theme.fontSize * 0.65,
                      color: theme.hintColor),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (editor.codeLineNumbers)
                  Padding(
                    padding: EdgeInsets.only(right: theme.fontSize * 0.75),
                    child: Text(
                      [
                        for (var i = 1;
                            i <= displayBody.split('\n').length;
                            i++)
                          '$i'
                      ].join('\n'),
                      textAlign: TextAlign.right,
                      style: mono.copyWith(color: theme.hintColor),
                    ),
                  ),
                Expanded(
                  child: editor.autoWrapCode
                      ? _codeText(span, runs, mono, wrap: true)
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _codeText(span, runs, mono, wrap: false),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
