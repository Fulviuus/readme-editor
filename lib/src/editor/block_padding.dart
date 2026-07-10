/// Vertical spacing per block kind — shared by the rendered and editing
/// widgets so swapping between them on focus does not shift layout.
library;

import 'package:flutter/widgets.dart';

import '../document/block.dart';
import '../theme/readme_theme.dart';

EdgeInsets blockPadding(Block block, ReadmeTheme theme) {
  final u = theme.fontSize;
  return switch (block.kind) {
    BlockKind.heading => EdgeInsets.only(
        top: u * (block.headingLevel <= 2 ? 0.9 : 0.7), bottom: u * 0.35),
    BlockKind.thematicBreak => EdgeInsets.symmetric(vertical: u * 0.9),
    BlockKind.fencedCode ||
    BlockKind.indentedCode ||
    BlockKind.mathBlock ||
    BlockKind.table =>
      EdgeInsets.symmetric(vertical: u * 0.5),
    _ => EdgeInsets.symmetric(vertical: u * 0.35),
  };
}
