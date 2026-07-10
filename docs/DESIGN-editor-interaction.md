# readme — Hybrid Live-Editing Interaction Spec (Flutter)

## 0. Shared data model (referenced by every section)

```dart
class Block {
  final String id;          // stable UUID, assigned at creation, never reused
  BlockType type;           // paragraph | heading(1..6) | fencedCode(lang) | blockquote
                            // | unorderedList | orderedList | taskList | table
                            // | thematicBreak | image | mathBlock | html
  String source;            // raw markdown lines joined by '\n', NO trailing '\n'
  int blankLinesBefore;     // count of blank lines that preceded this block in the file
}

class Document {
  List<Block> blocks;       // never empty (see §8)
  String lineEnding;        // '\n' or '\r\n', detected at load
  bool hadFinalNewline;     // detected at load
  bool hadBom;              // detected at load
  int trailingBlankLines;   // blank lines after last block in the file
}

class EditorCaret { String blockId; TextSelection selection; } // selection in SOURCE offsets
```

The focused block's `TextField` uses one shared `MarkdownEditingController` + one shared `FocusNode` owned by `EditorController`, retargeted on focus change (never 5k controllers). In focused mode the TextField text **is** `block.source`, so focused-mode offsets are identity (no mapping needed); mapping (§3) exists only for the rendered (unfocused) view.

---

## 1. Block boundaries: parsing and byte-faithful serialization

### 1.1 Parser: single-pass line scanner

```
List<Block> parseDocument(String text):
  strip BOM (record hadBom); detect lineEnding; normalize to '\n' internally
  lines = text.split('\n'); if last line == '' → hadFinalNewline=true, drop it
  i = 0; pendingBlank = 0; blocks = []
  while i < lines.length:
    if isBlank(lines[i]): pendingBlank++; i++; continue
    (type, end) = scanBlock(lines, i)          // end exclusive
    blocks.add(Block(type, join(lines[i..end], '\n'), blankLinesBefore: pendingBlank))
    pendingBlank = 0; i = end
  doc.trailingBlankLines = pendingBlank
```

`isBlank(line)` = only spaces/tabs. `scanBlock` tests the start line against these rules **in this precedence order**:

1. **Fenced code** — `^ {0,3}(```{3,}|~~~{3,})[ \t]*(\S*)[ \t]*$` (backtick fences may not have backticks in info string). Swallow every following line verbatim — blank lines included — until a closing fence: same char, length ≥ opening length, `^ {0,3}fence[ \t]*$`. **Unclosed fence swallows to EOF** and stays unclosed (preserved on save).
2. **Math block** — `^ {0,3}\$\$` : swallow until a line containing closing `$$` (inclusive) or EOF.
3. **ATX heading** — `^ {0,3}#{1,6}( |\t|$)` : exactly one line.
4. **Blockquote** — `^ {0,3}>` : consume while the line starts with optional ≤3 spaces + `>`, **or** is a non-blank lazy-continuation line (previous consumed line was quote content). A fully blank line ends the block; a `>`-only line continues it.
5. **List** (unordered `^ {0,3}[-*+]( +)`, ordered `^ {0,3}\d{1,9}[.)]( +)`) — but a `-`/`*` line that also matches thematic-break wins as thematic break. Record `contentIndent` = indent of text after the first marker. Consume while the next line is: (a) any list-marker line at any indent, (b) a non-blank line indented ≥ `contentIndent` of the innermost open item (nested continuation — includes indented code/quotes inside items), or (c) a blank line whose **next non-blank** line satisfies (a) or (b) with at most one intervening blank. **Two consecutive blank lines always end the list.** If the first item's text matches `\[( |x|X)\] ` → type = `taskList`, else per first marker. Interior blank lines are kept verbatim in `source` (loose lists round-trip).
6. **Table** — current line contains an unescaped `|` AND next line matches delimiter `^ {0,3}\|?[ \t:\-|]+\|?[ \t]*$` with ≥1 `-` per cell and cell count ≥ header cell count. Consume header + delimiter + every following non-blank line containing `|`.
7. **Thematic break** — `^ {0,3}([-_*])( *\1){2,}[ \t]*$` : one line.
8. **HTML block** — `^ {0,3}<[a-zA-Z!/?]` : consume until blank line or EOF.
9. **Paragraph** (fallback) — consume non-blank lines; stop when the next line would start any of rules 1–8 (interruption) or is blank. Two post-passes on the collected lines:
   - **Setext**: if the last collected line matches `^ {0,3}(=+|-+)[ \t]*$` and there is ≥1 line before it in this paragraph → type = heading(1 for `=`, 2 for `-`), underline line stays in `source`. (A lone `---` with no preceding paragraph line already went to rule 7.)
   - **Standalone image**: whole source matches `^!\[[^\]]*\]\([^)\s]*(?:\s+"[^"]*")?\)[ \t]*$` on a single line → type = `image`.

### 1.2 Serialization

```
String serialize(doc):
  buf = hadBom ? BOM : ''
  for (k, block) in doc.blocks:
    if k > 0: buf += '\n' * (1 + block.blankLinesBefore)
    buf += block.source
  buf += '\n' * doc.trailingBlankLines
  if hadFinalNewline: buf += '\n'
  replace '\n' with doc.lineEnding
```

**Round-trip contract:** for any input the scanner accepts, `serialize(parseDocument(text)) == text` byte-for-byte — blank-line counts, trailing whitespace, tabs, unclosed fences, CRLF, BOM, and final-newline presence are all captured in the model and re-emitted. Normalization happens **only on edited content**: blocks created/split by the editor get `blankLinesBefore = 1`; blocks whose `source` the user edits keep whatever bytes the TextField holds. No re-wrapping, no marker canonicalization (`*` is never rewritten to `-`), ever.

**DECISION:** Parse with the precedence-ordered line scanner above; blank lines separate blocks except inside fences/math (verbatim) and lists (one interior blank allowed, two terminate).
**DECISION:** Store `blankLinesBefore` per block plus doc-level `lineEnding`/`hadFinalNewline`/`hadBom`/`trailingBlankLines`; round-trip is byte-identical for unedited documents.
**DECISION:** The only permitted normalization is on user-edited regions: new block separators are exactly one blank line; nothing else is ever rewritten.
**DECISION:** Full-document reparse runs only at file load and on source-mode exit (§4); ordinary edits never trigger it.

---

## 2. Focused-block editing semantics

All key handling happens in a `Shortcuts`/`Actions` layer wrapping the focused TextField, intercepting **before** EditableText's defaults. `caret` below is a source offset in `block.source`.

### 2.1 Enter (no modifiers)

```
onEnter(block, caret):
  switch block.type:
    fencedCode | mathBlock | html:
      insert '\n' + leadingWhitespaceOf(currentLine)          // auto-indent
      then rescanStructural(block)                            // §2.4: closing fence may split
    unorderedList | orderedList | taskList:
      item = itemLineAt(caret)
      if itemContentEmpty(item):                              // marker-only line
        if item.indent > 0: outdent(item)                     // pop one nesting level
        else: removeItemLine(item); splitAfter(item) → new empty paragraph block below, focus it
      else:
        tail = source[caret ... endOfItem]                    // may be ''
        marker = nextMarker(item)   // same bullet; ordered: item.number+1 renumber NOT applied to later items (v1);
                                    // taskList: '- [ ] '
        insert '\n' + item.indentString + marker; caret after marker; tail becomes the new item's content
    blockquote:
      if currentLineIsEmptyQuote(caret):  // '>' or '> '
        deleteCurrentLine(); split → new empty paragraph block below, focus it
      else if caret at end of block: insert '\n> '
      else: insert '\n> ' (splits the line inside the quote block)
    table:  handled in §7 (row navigation, never newline)
    heading:
      if caret == source.length: insert new EMPTY PARAGRAPH block below, focus it, caret 0
      else: split — heading keeps text[0..caret]; text[caret..] becomes a new PARAGRAPH block (remainder loses heading)
    paragraph | image | thematicBreak:
      split at caret into two blocks: paragraph(text[0..caret]) + paragraph(text[caret..]); focus second, caret 0
      (caret==end ⇒ second is empty paragraph; caret==0 ⇒ empty paragraph pushed above, focus stays on content)
```

**Shift+Enter**: inserts `'\n'` into the block's raw source (soft line break inside the block — legal because paragraphs only end at blank lines). In tables it inserts `<br>` at the caret.

### 2.2 Backspace at source offset 0 — demote-then-merge

Stage 1 (**demote**, if the block carries its own leading markers): the first Backspace at 0 strips markers instead of merging.

| current block | Backspace at 0 does |
|---|---|
| heading | strip `^#{1,6} +` (and setext underline line) → paragraph, caret 0 |
| blockquote | strip `^ {0,3}> ?` from every line → paragraph, caret 0 |
| list (caret at start of first item's content) | strip first item's marker: if single item → paragraph; else split → `[paragraph(item1 text), list(items 2..n)]`; nested item outdents one level first |
| fencedCode / mathBlock with empty body | replace block with empty paragraph |
| all other cases | fall through to stage 2 |

Stage 2 (**merge**, current block is a plain paragraph at offset 0, or an image/thematicBreak):

| previous block ↓ | action |
|---|---|
| paragraph, heading | append current source to prev source (no separator); focus prev; caret = old prev length; type stays prev's |
| list, blockquote | append current text to prev's **last line**; caret at junction |
| fencedCode, mathBlock, table, html, image, thematicBreak (opaque) | if current paragraph is empty → delete it, focus prev, caret at end of prev source; if non-empty → **no merge**, just focus prev with caret at end |
| — special: prev is thematicBreak or image and current is non-empty | delete the prev block itself (the HR/image is what Backspace visually targets), current block untouched, caret stays at 0 |
| no previous block | no-op |

**Forward-Delete at end of block** mirrors stage 2 with roles swapped (next block merges into current under the same table).

### 2.3 Live auto-conversion triggers (paragraph blocks only)

Two mechanisms, both deterministic:

**(A) Prefix triggers — fire the instant the trailing space is typed.** Checked in `onChanged` when the edit is a single-char insertion of `' '`, block.type == paragraph, and the text from line-start to caret matches:

| pattern (line start → caret) | converts to |
|---|---|
| `#{1,6} ` on the block's **first** line | heading(n) — `#`s stay in source, type flips, rest of text preserved |
| `[-*+] ` | unorderedList |
| `\d{1,9}[.)] ` | orderedList |
| `[-*+] \[( |x)\] ` | taskList |
| `> ` | blockquote |

**(B) Newline-committed triggers — fire when Enter is pressed** (checked before the Enter handling of §2.1) and the current line (about to be terminated) is:

| line | effect |
|---|---|
| `` ```lang `` (whole paragraph is just this line) | convert to fencedCode(lang), empty body, closing fence auto-appended, caret on the empty body line |
| `$$` | convert to mathBlock, empty body, closing `$$` appended, caret inside |
| `---` / `***` / `___` (thematic pattern) | convert to thematicBreak + insert empty paragraph below, focus it |
| table delimiter row, and the previous line (same block or the block above) contains `|` | merge header + delimiter into one table block, append one empty data row, focus first cell (§7) |
| `=+` / `-+` under ≥1 paragraph line in this block | setext heading(1/2) |

Every conversion is **one non-coalescing DocEdit** (§5), so a single Cmd+Z restores the literal typed characters as a paragraph.

### 2.4 Structural re-scan of the focused block (closing fence, etc.)

```
rescanStructural(block):        // called after Enter/paste inside fencedCode|mathBlock|html,
                                // and after any paste into any block
  parts = scanBlockLocal(block.source)   // §1 scanner run on this block's lines ONLY
  if parts == [block as-is]: return
  replace block with parts (one DocEdit); focus the part containing the caret,
  caret mapped by absolute source offset (offsets are preserved across the split)
```

So typing the closing fence line inside a code block + Enter splits `[fencedCode, paragraph(...)]` and the caret lands in the trailing paragraph. Deleting a closing fence does **not** swallow following blocks — block boundaries only ever change via explicit ops (Enter/Backspace/paste/rescan); an unclosed fence stays confined to its block.

**DECISION:** Enter behavior exactly per the §2.1 switch; empty list item exits via outdent-then-escape; heading split demotes the tail to paragraph.
**DECISION:** Backspace at 0 is two-stage: demote own markers first, then merge per the §2.2 tables; opaque blocks never receive merged text.
**DECISION:** Auto-convert uses prefix-triggers-on-space (heading/list/task/quote) and newline-committed triggers (fence/math/HR/table/setext); paragraph blocks only; each conversion is one atomic undo step.
**DECISION:** Closing a fence is detected by `rescanStructural` on Enter/paste within fence-like blocks; re-scan is always confined to the focused block's own lines.

---

## 3. Caret transfer: offset mapping and vertical navigation

### 3.1 OffsetRun table (built once per rendered block, cached)

The AST→widget renderer emits, alongside each `RichText` region, an ordered run list:

```dart
enum RunKind { text, hidden, atomic }
class OffsetRun {
  int rStart, rEnd;   // offsets in the region's RENDERED plain text
  int sStart, sEnd;   // offsets in block.source (region-global via sourceBase)
  RunKind kind;
  // text:   rEnd-rStart == sEnd-sStart, 1:1 copy
  // hidden: rStart == rEnd (markers **, `, [, ](url), #, > … hidden in rendered mode)
  // atomic: lengths differ (synthesized glyphs: '• ' for '- ', checkbox for '[ ] ',
  //          link label standing for [label](url) if URL fully hidden)
}
```

Invariants: runs sorted, non-overlapping, contiguous in both coordinate spaces, covering the whole region. Blocks that render as multiple text regions (each list item line, each blockquote line, each table cell) get one run list per region plus `region.sourceBase` (offset of the region's first source char in `block.source`).

### 3.2 Mapping algorithms

```
int renderedToSource(runs, r):
  run = binarySearch(runs, r)                 // rStart <= r <= rEnd; tie at boundary → prefer 'text' run
  switch run.kind:
    text:   return run.sStart + (r - run.rStart)
    hidden: return run.sEnd                   // caret goes AFTER hidden opening markers
    atomic: return (r - run.rStart) <= (run.rEnd - r) ? run.sStart : run.sEnd  // snap to nearer edge

int sourceToRendered(runs, s):
  run = binarySearch on (sStart, sEnd)
  switch run.kind:
    text:   return run.rStart + (s - run.sStart)
    hidden: return run.rStart                 // collapsed point
    atomic: return (s - run.sStart) <= (run.sEnd - s) ? run.rStart : run.rEnd
```

### 3.3 Click → focus + caret

```
onTapDown(block, globalPos):
  region = hitTest which RichText / cell / glyph region contains globalPos
  if region is text:
    r = region.textPainter.getPositionForOffset(globalPos - region.origin).offset
    s = region.sourceBase + renderedToSource(region.runs, r)
  else if block.type == table: s = cellContentStart(row, col)          // §7
  else: s = block.source.length            // image, thematicBreak, decoration chrome
  editorController.focusBlock(block.id, TextSelection.collapsed(offset: s))
```

Focusing swaps the item widget to the TextField (same `source` text ⇒ source offsets stay valid), attaches shared controller/FocusNode, sets selection, requests focus — all in one frame; a `postFrameCallback` verifies the selection stuck (EditableText can clamp during attach).

### 3.4 ArrowUp on first visual line / ArrowDown on last — preserve x

`EditorController` keeps `double? goalX` (global px), cleared by any horizontal caret move, typing, or click; set on the first vertical move.

```
onArrowUp(block, sel):
  lineIdx = textPainter(focusedField).getLineForOffset(sel.extentOffset)
  if lineIdx > 0: return defaultBehavior
  goalX ??= caretRect(sel).left in global coords
  prev = blockAbove(block); if prev == null: return consumed(no-op)
  caret = caretForXOnEdgeLine(prev, edge: LAST_LINE, x: goalX)
  focusBlock(prev.id, collapsed(caret))

int caretForXOnEdgeLine(target, edge, x):
  // Build the FOCUSED-mode TextSpan of target.source (same buildTextSpan the TextField
  // will use), lay out with TextPainter at the field's content width.
  tp = layoutFocusedSpan(target)                                // cached per (source,width,theme)
  line = (edge == LAST_LINE) ? tp.lineCount - 1 : 0
  y = tp.lineMetrics[line].baseline midpoint
  return tp.getPositionForOffset(Offset(xLocalToField(x), y)).offset
```

ArrowDown mirrors with `lineIdx == lastLine` and `edge: FIRST_LINE`. Consecutive vertical moves reuse `goalX`, so the caret tracks a straight column through blocks of different fonts. For non-text targets in the TextField sense there are none — every focused block is a TextField over raw source, so this works uniformly (tables included: caret lands on the raw pipe row).

**DECISION:** Build the `OffsetRun` list (text/hidden/atomic kinds) during rendered-mode span construction, cached per block; map with the two binary-search functions above; hidden-run caret resolves to `sEnd` (after opening markers).
**DECISION:** Click focuses the block and places the caret via `renderedToSource`; clicks on non-text chrome place the caret at source end (tables: at the clicked cell).
**DECISION:** Vertical transfer intercepts ArrowUp/Down only on edge visual lines, keeps a sticky `goalX`, and computes the target caret by laying out the target's focused-mode span offline.

---

## 4. Selection contract (v1)

- **In-block selection only.** Selection lives inside the focused block's TextField over raw source (markers visible, so no mapping needed). Drag gestures clamp at block edges; a drag leaving the block does NOT extend cross-block.
- **Copy (Cmd+C)** with an in-block selection puts the selected **raw markdown substring** on the clipboard as plain text. Copying a *rendered* block (via doc-selection below or context menu "Copy as Markdown") copies its full `block.source`. v1 writes plain text only — no rich-text/HTML clipboard flavor.
- **Select All (Cmd+A)**: first press selects the entire focused block's source. Second consecutive press (or Cmd+A with no focused block) enters **doc-selected** pseudo-state: boolean flag, rendered as a highlight overlay over all blocks; Cmd+C then copies `serialize(document)`; any typed character or Backspace replaces the whole document (one DocEdit) with a fresh paragraph; Escape or any click clears the flag.
- **Cross-block selection** is served by **Source Mode** (Cmd+/): the whole document becomes one plain TextField showing `serialize(document)`, with native selection/copy/cut across everything. On exit (Cmd+/ again), the buffer is re-parsed via §1; the entire source-mode session commits as **one** `ReplaceAll` DocEdit (single undo step); caret maps back to (block, offset) by absolute character offset.

**DECISION:** v1 selection is strictly within the focused block; cross-block selection = Source Mode; Cmd+A escalates block → whole-doc pseudo-selection; all copy paths emit raw markdown plain text.

---

## 5. Undo/redo — single document-level stack

### 5.1 The op

```dart
class DocEdit {
  int index;                      // first affected block index
  List<BlockSnapshot> before;     // blocks removed  (id, type, source, blankLinesBefore)
  List<BlockSnapshot> after;      // blocks inserted (same ids where the block survives)
  EditorCaret caretBefore, caretAfter;
  EditKind kind;                  // typing | deleteBack | deleteFwd | split | merge
                                  // | typeChange | autoConvert | paste | blockOp | replaceAll
  DateTime at;
}
```

One universal shape covers every variant: in-place text change (`before=[b], after=[b']`), split (`1→2`), merge (`2→1`), type change (`1→1` with type diff), auto-convert (`kind: autoConvert`), source-mode commit (`replaceAll`). Undo applies `before` over `after`'s range, restores `caretBefore`, and refocuses; redo mirrors.

### 5.2 Coalescing

`history.record(edit)` merges `edit` into the stack top iff ALL of:
- both `kind == typing` (or both are the same delete kind with contiguous ranges),
- same single block id,
- `edit.at - top.at < 1000 ms`,
- the previous edit's caret == this edit's `caretBefore` (no intervening caret move),
- the char committed by the **previous** edit was not whitespace or `.,;:!?` (word-boundary flush — the burst breaks *after* a boundary char so the boundary char belongs to the earlier group),
- coalesced group ≤ 100 chars.

Never coalesced: `autoConvert`, `split`, `merge`, `typeChange`, `paste`, `blockOp`, `replaceAll`, any edit replacing a non-collapsed selection. Any focus change or programmatic caret set seals the top entry. Stack depth cap: 1000 entries; redo stack cleared on new record.

### 5.3 Suppressing / bridging TextField-internal undo

- The focused TextField gets a dedicated `UndoHistoryController` that is thrown away on every focus change and never consulted — plus a `Shortcuts`/`Actions` layer **above** `EditableText` maps `UndoTextIntent`/`RedoTextIntent` (Cmd+Z / Shift+Cmd+Z / Ctrl+Z / Ctrl+Y) to `DocumentUndoIntent`/`DocumentRedoIntent`, so the platform shortcuts never reach the field's internal history.
- The controller's change listener is the single recording point: it diffs `lastText → value.text`, builds a `typing`/`delete` DocEdit, and calls `history.record`. A guard flag `applyingHistory` is set while undo/redo (or any programmatic mutation) writes `controller.value`, so those writes are never re-recorded.
- Applying an entry: mutate `document.blocks`, retarget focus to `caretBefore.blockId` (scroll it into view first, §9), set `controller.value = TextEditingValue(text: block.source, selection: caretBefore.selection)` under the guard.

**DECISION:** One document-level undo stack of the universal `DocEdit` op; TextField internal undo is bypassed by intercepting the undo intents and recording exclusively from the controller diff listener under an `applyingHistory` guard.
**DECISION:** Coalesce typing bursts by the 6-condition rule above (1 s gap OR word boundary OR caret discontinuity OR 100 chars flushes); structural and auto-convert edits are always atomic single steps.

---

## 6. Formatting shortcuts inside the focused block

### 6.1 Inline wrap/unwrap — Cmd+B (`**`), Cmd+I (`*`), Cmd+E / backtick (`` ` ``)

```
toggleInline(marker m, sel):                 // m: '**' | '*' | '`'
  if sel.collapsed:
    w = wordRangeAt(sel.base)                // run of Unicode letters/digits/_
    if w == null:
      if surroundedByEmptyPair(sel.base, m): delete pair; return          // toggle-off '**|**'
      insert m+m at caret; caret = base + m.length; return               // empty pair, caret inside
    sel = w
  (a, b) = shrink sel to exclude leading/trailing whitespace
  L = m.length
  if src[a-L..a] == m && src[b..b+L] == m && contextOk(m, a-L, b+L):
     delete both markers → selection (a-L, b-L)                          // unwrap, markers outside sel
  else if src[a..a+L] == m && src[b-L..b] == m && b-a >= 2L:
     strip from inside  → selection (a, b-2L)                            // unwrap, markers inside sel
  else:
     insert m at b, then m at a → selection (a+L, b+L)                   // wrap; sel stays on inner text
```

`contextOk` for `m == '*'`: reject if `src[a-L-1] == '*'` or `src[b+L] == '*'` (would steal a star from `**`). For `` ` ``: no smart double-backtick escaping in v1 — wrapping text that contains a backtick is a plain wrap (user-visible, acceptable). Selection always ends on the inner text so repeated presses toggle cleanly. Additionally, **typing** `` ` `` or `*` while a non-collapsed selection exists wraps the selection (wrap-on-type) instead of replacing it.

### 6.2 Cmd+K — link

```
if selection collapsed:            insert '[]()'; caret between the brackets
else if isUrl(selText):            replace with '[](' + selText + ')'; caret inside []
else if selection is exactly a link's label (inline AST check): strip '[label](url)' → 'label'  // unlink
else:                              replace with '[' + selText + ']()'; caret inside ()
```

### 6.3 Cmd+1..6 / Cmd+0 — whole-block heading toggle

Applies only when `block.type` is paragraph or heading (no-op otherwise, v1):

```
setHeading(block, n):              // n = 0 means paragraph
  old = match(block.source, '^#{1,6} +')            // '' if none
  new = (n == 0 || currentLevel == n) ? '' : '#'*n + ' '   // same level ⇒ toggle to paragraph
  if block is setext heading: also delete the underline line
  source = new + source.withoutPrefix(old)
  type = new.isEmpty ? paragraph : heading(n)
  caret += new.length - old.length (clamped ≥ new.length)
```

One `typeChange` DocEdit (atomic undo). Selection, if any, shifts by the same delta.

**DECISION:** Cmd+B/I/E toggle via the `toggleInline` algorithm — collapsed caret expands to the word under it, else inserts an empty pair with caret inside; unwrap detects markers just outside or just inside the selection; italic guards against `**` adjacency; final selection always covers inner text.
**DECISION:** Cmd+K per §6.2 including URL-selection and unlink cases; Cmd+1..6 sets/toggles the block heading level by rewriting the line prefix, Cmd+0 forces paragraph; heading toggles apply to paragraph/heading blocks only.

---

## 7. Table editing (v1)

**Choice: raw-source TextField with pipe-aware Tab/Enter navigation** — it reuses the entire focused-block machinery (controller, undo, offset math) with zero new stateful widget infrastructure while still making cell hopping fast. (Rendered/unfocused tables still display as a real `Table` widget.)

Spec (focused table block; pipes and delimiter row visible, dimmed by `buildTextSpan`):

- `cellAt(caret)` → `(row, col)`: row = line index; col = count of **unescaped** `|` (not `\|`) on the line left of the caret, minus 1 if the line starts with `|`.
- `cellRange(row, col)` → source range of the cell's trimmed content between its bounding pipes.
- **Tab**: select `cellRange(next cell)` — whole content selected so typing replaces it. Last cell of a row → first cell of next row, **skipping the delimiter row**. Last cell of last row → append `'\n' + '|' + '   |' * nCols` (one DocEdit) and select its first cell.
- **Shift+Tab**: previous cell, same skipping; at the very first cell → no-op.
- **Enter**: move to the same column in the next row (append a row if on the last one); never inserts `\n`. **Shift+Enter** inserts `<br>` at the caret.
- **ArrowDown on the last row / ArrowUp on the first row**: leave the table via §3.4 (goalX preserved).
- **Typing `|`** inserts a literal pipe (no auto-column magic in v1); the block re-renders columns on blur.
- **Click on a rendered cell** (`row`, `col` from the Table widget hit test): focus block, caret at `cellRange(row, col).start`.
- **Deleting the delimiter row** leaves the block a table until blur; on blur, if the source no longer matches the table shape (§1 rule 6), the block is re-typed via `scanBlockLocal` (may become paragraph) — one `typeChange` DocEdit.

**DECISION (revised 2026-07-11):** tables are edited IN PLACE in the rendered table — the focused table stays a rendered grid and the active cell hosts a single-line TextField over the CELL text only; raw pipe source never appears in the live editor. Tab/Shift-Tab move cells (selecting the target cell's content, auto-appending rows at the tail), Enter moves down a row, Shift+Enter inserts `<br>` in the cell, ArrowUp/Down move rows (leaving the table at the edges), ArrowLeft/Right at cell-text boundaries move cells, Escape blurs. Cell edits splice into the block source, which is auto-prettified (aligned pipes, padded cells, `----` delimiters — see prettifyTable in blocks/table_model.dart) on every cell commit and on blur, so source mode and saved files always show clean aligned tables.

---

## 8. Empty document and the trailing paragraph

- **Invariant:** `document.blocks` is never empty. A new/empty file loads as `[paragraph('')]`, focused, caret 0, rendering a dimmed placeholder ("Type here…") via the TextField's hint.
- **Ephemeral trailing paragraph:** clicking the empty canvas area below the last block:
  - if the last block is already an empty paragraph → focus it;
  - otherwise append `paragraph('', blankLinesBefore: 1, ephemeral: true)` and focus it. This append is **not** recorded on the undo stack.
  - The ephemeral flag clears on the first recorded edit to the block (it becomes a normal block from then on).
  - If focus leaves it while still empty and ephemeral, it is silently removed (no undo entry).
  - `serialize` skips a trailing empty ephemeral paragraph, so files never gain phantom trailing blank lines.
- Consequence: a document ending in a code block/table is always escapable by clicking below it (or ArrowDown past it, which performs the same append-and-focus).

**DECISION:** Documents always contain ≥1 block; empty doc = one empty focused paragraph with hint text; clicking (or arrowing) below an opaque last block appends an ephemeral empty paragraph that is undo-invisible, auto-removed if abandoned empty, and skipped by the serializer.

---

## 9. Performance at ~5k blocks

- **List:** `ListView.builder(itemCount: blocks.length)` with `BlockView(key: ValueKey(block.id))` and `findChildIndexCallback` backed by an id→index map, so splits/merges reuse element state. No `itemExtent` (heights vary).
- **Shared editing state:** exactly one `MarkdownEditingController` + one `FocusNode`, owned by `EditorController` and retargeted on focus change — never per-block. The focused block's item widget mixes in `AutomaticKeepAliveClientMixin` with `wantKeepAlive = isFocused`, so scrolling the caret off-screen does not dispose the TextField and drop focus; all other items dispose freely.
- **Per-block caches:** memoize `(source, contentWidth, themeHash) → (inline AST, rendered TextSpan, OffsetRun list, focused-mode TextSpan layout)` in an LRU (cap ~1024). Invalidate a block's entry on its own edit only. Inline parsing is lazy — first build in viewport, so a 5k-block load costs one O(lines) block scan plus viewport-only inline work.
- **Scroll-to-caret:** on every caret change in the focused block, compute `caretGlobalY = blockRenderBox.localToGlobal(caretRectInField.topLeft).dy` (the focused block is by definition built/attached) and, if outside the viewport's safe band (10% margins), `scrollController.animateTo` to bring it inside. Focus-jump to an off-screen block (undo, source-mode exit, doc navigation) first estimates the target offset from the id→index map × running average item height, jumps, then corrects with `Scrollable.ensureVisible` on the built item next frame.
- **Typewriter mode (hook):** replace the safe-band rule with `animateTo(caretGlobalYInList − viewportHeight/2)` on every caret move (80 ms curve), and pad the list with `viewportHeight/2` top and bottom padding so first/last lines can center. It's a pure scroll-policy strategy object — no layout changes.
- **Focus mode (hook):** each `BlockView` wraps its content in `AnimatedOpacity(opacity: focusModeOn && !isFocused ? 0.4 : 1.0)`. To avoid rebuilding 5k items on focus change, each item subscribes to `EditorController.focusedBlockId` through a per-item `ValueNotifier<bool> isFocused` that the controller flips for exactly the old and new focused ids — so a focus move rebuilds 2 items, not 5000. Toggling focus mode itself rebuilds all visible items once (acceptable).
- **Height churn:** a focused block growing/shrinking relayouts only the sliver list locally; typewriter compensation re-runs after layout via the caret listener, so no double-scroll jitter.

**DECISION:** ListView.builder + stable ValueKey(block.id) + findChildIndexCallback; single shared controller/FocusNode; keepAlive only the focused item.
**DECISION:** Cache AST/TextSpan/OffsetRuns per block keyed by (source,width,theme), lazily built, invalidated per-block on edit.
**DECISION:** Scroll-to-caret via safe-band animateTo from the focused item's RenderBox; typewriter mode = center-caret scroll policy with half-viewport list padding; focus mode = per-item isFocused ValueNotifier flipping exactly two items per focus move.