/// Web build: no inline webview — mermaid fences render as plain code.
library;

import 'package:flutter/widgets.dart';

import '../../document/block.dart';
import '../editor_controller.dart';
import 'code_block.dart';

/// Whether this platform renders mermaid diagrams.
const bool mermaidSupported = false;

class MermaidBlockView extends StatelessWidget {
  const MermaidBlockView(
      {super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  @override
  Widget build(BuildContext context) =>
      CodeBlockView(block: block, editor: editor);
}
