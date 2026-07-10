<p align="center">
  <img src="assets/brand/logo.png" alt="readme" width="420">
</p>

<p align="center">
  A <strong>live markdown editor</strong> built with Flutter.<br>
  One surface, no split preview — <em>the document is the editor</em>.
</p>

---

The block you're editing shows its raw markdown (markers dimmed, live-styled);
everything else renders fully. Click anywhere in rendered text and the caret
lands exactly where you clicked, mapped through the hidden syntax.

## Features

- **Hybrid editing** — click any block to edit its source; click away and it
  renders. Structural editing follows your fingers: Enter continues lists,
  splits paragraphs, and completes code fences; Backspace demotes markers
  before it merges blocks.
- **Full block support** — headings (ATX + setext), nested/ordered/task lists
  (checkboxes clickable without entering edit mode), fenced and indented code
  with syntax highlighting, tables with Tab/Enter cell navigation, quotes,
  thematic breaks, YAML front matter.
- **Live auto-conversion** — type `# `, `- `, `> `, `1. `, ` ```lang `, `$$`,
  `---`, or a table delimiter row and the block converts as you type.
- **Themes** — five built-ins (GitHub, Night, Newsprint, Pixyll, Whitey) with
  carefully tuned colors and typography. Drop custom `.json` themes into the
  app's themes folder (schema in `docs/DESIGN-themes.md`).
- **Round-trip fidelity** — files re-serialize byte-identically (CRLF, BOM,
  blank-line counts, unclosed fences all preserved); only blocks you edit
  change.
- Document-level **undo/redo** with typing coalescing, **find & replace**,
  **source mode**, **focus mode**, word count, file tree + outline sidebar,
  drag-and-drop, HTML export.

## Shortcuts

| | |
|---|---|
| Bold / Italic / Code / Strikethrough | Cmd+B / Cmd+I / Cmd+E / Shift+Cmd+D |
| Link | Cmd+K |
| Heading 1–6 / Paragraph | Cmd+1…6 / Cmd+0 |
| Find | Cmd+F |
| Source mode | Cmd+/ |
| Save / Open / New | Cmd+S / Cmd+O / Cmd+N |

(Ctrl on Windows/Linux.)

## Building

```sh
flutter pub get
flutter run -d macos      # native macOS app
```

Desktop targets: macOS, Windows, Linux. A web build (`flutter build web`)
exists as a development preview; file-system features are desktop-only.

## Development

- `docs/ARCHITECTURE.md` — module map.
- `docs/DESIGN-editor-interaction.md` — the full editing-semantics spec
  (Enter/Backspace tables, offset mapping, undo coalescing rules).
- `docs/DESIGN-themes.md` — theme JSON schema + built-in theme values.
- `docs/ROADMAP.md` — feature parity tracker (see the issue tracker for
  individual items).
- `flutter test` — document round-trip + editor semantics suites
  (182 tests). `flutter analyze` must stay at zero issues.
