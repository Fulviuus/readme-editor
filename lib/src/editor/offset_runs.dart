/// Offset mapping between a block's RENDERED plain text (markers hidden) and
/// its raw SOURCE (docs/DESIGN-editor-interaction.md §3). Built during span
/// construction; used to place the caret when a click on rendered content
/// focuses the block.
library;

enum RunKind {
  /// 1:1 copy — rendered length == source length.
  text,

  /// Markers hidden in rendered mode (`**`, `` ` ``, `[`, `](url)`, `#`, `>`)
  /// — zero rendered width.
  hidden,

  /// Synthesized glyphs (`• ` for `- `, checkbox for `[ ]`, inline image) —
  /// lengths differ; caret snaps to the nearer edge.
  atomic,
}

class OffsetRun {
  const OffsetRun(this.kind, this.rStart, this.rEnd, this.sStart, this.sEnd);
  final RunKind kind;
  final int rStart, rEnd; // rendered-text offsets
  final int sStart, sEnd; // source offsets

  @override
  String toString() => '$kind r[$rStart,$rEnd) s[$sStart,$sEnd)';
}

/// Accumulates runs while a span builder walks the inline nodes.
class RunBuilder {
  final List<OffsetRun> runs = [];
  int _r = 0;

  int get renderedLength => _r;

  void text(int sStart, int sEnd) {
    if (sEnd <= sStart) return;
    runs.add(OffsetRun(RunKind.text, _r, _r + (sEnd - sStart), sStart, sEnd));
    _r += sEnd - sStart;
  }

  void hidden(int sStart, int sEnd) {
    if (sEnd <= sStart) return;
    runs.add(OffsetRun(RunKind.hidden, _r, _r, sStart, sEnd));
  }

  void atomic(int sStart, int sEnd, int renderedLen) {
    runs.add(OffsetRun(RunKind.atomic, _r, _r + renderedLen, sStart, sEnd));
    _r += renderedLen;
  }
}

/// Maps a rendered-text offset to a source offset. Ties at run boundaries
/// prefer text runs; a caret inside hidden markers resolves to just after
/// them.
int renderedToSource(List<OffsetRun> runs, int r) {
  if (runs.isEmpty) return 0;
  OffsetRun? best;
  for (final run in runs) {
    if (r < run.rStart || r > run.rEnd) continue;
    if (best == null || (best.kind != RunKind.text && run.kind == RunKind.text)) {
      best = run;
    }
  }
  best ??= r < runs.first.rStart ? runs.first : runs.last;
  switch (best.kind) {
    case RunKind.text:
      return best.sStart + (r - best.rStart).clamp(0, best.sEnd - best.sStart);
    case RunKind.hidden:
      return best.sEnd;
    case RunKind.atomic:
      return (r - best.rStart) <= (best.rEnd - r) ? best.sStart : best.sEnd;
  }
}

/// Maps a source offset to a rendered-text offset (for restoring a selection
/// highlight or scroll position in rendered mode).
int sourceToRendered(List<OffsetRun> runs, int s) {
  if (runs.isEmpty) return 0;
  OffsetRun? best;
  for (final run in runs) {
    if (s < run.sStart || s > run.sEnd) continue;
    if (best == null || (best.kind != RunKind.text && run.kind == RunKind.text)) {
      best = run;
    }
  }
  best ??= s < runs.first.sStart ? runs.first : runs.last;
  switch (best.kind) {
    case RunKind.text:
      return best.rStart + (s - best.sStart).clamp(0, best.rEnd - best.rStart);
    case RunKind.hidden:
      return best.rStart;
    case RunKind.atomic:
      return (s - best.sStart) <= (best.sEnd - s) ? best.rStart : best.rEnd;
  }
}
