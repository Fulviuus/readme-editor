# readme

A **live markdown editor** built with Flutter. One surface, no split preview:
the block you're editing shows its raw markdown (markers dimmed, live-styled);
everything else renders fully.

## Features

- **Hybrid editing** — click any block to edit its source; click away and it
  renders. Caret lands where you clicked, mapped through hidden markers.
- **Full block support** — headings (ATX + setext), lists (nested, ordered,
  task lists with clickable checkboxes), fenced/indented code with syntax
  highlighting (highlight.js grammars), tables (Tab between cells), quotes,
  thematic breaks, HTML/math/front-matter blocks (rendered as source for now).
- **Themes** — five built-ins (GitHub, Night, Newsprint, Pixyll, Whitey) with
  carefully tuned colors and typography. Drop custom `.json` themes into the
  app's themes folder (see `docs/DESIGN-themes.md` for the schema).
- **Live auto-conversion** — type `# `, `- `, `> `, `1. `, ` ```lang `, `$$`,
  `---`, or a table delimiter row and the block converts as you type.
- **Round-trip fidelity** — files re-serialize byte-identically (CRLF, BOM,
  blank-line counts, unclosed fences all preserved); only blocks you edit
  change.
- Document-level **undo/redo** with typing coalescing, **find & replace**,
  **source mode** (Cmd+/), **focus mode**, word count, file tree + outline
  sidebar, HTML export.

## Shortcuts

| | |
|---|---|
| Bold / Italic / Code | Cmd+B / Cmd+I / Cmd+E |
| Link | Cmd+K |
| Heading 1–6 / Paragraph | Cmd+1…6 / Cmd+0 |
| Find | Cmd+F |
| Source mode | Cmd+/ |
| Save / Open / New | Cmd+S / Cmd+O / Cmd+N |

(Ctrl on Windows/Linux.)

## Running

```sh
flutter pub get
flutter run -d macos    # needs Xcode
flutter run -d chrome   # web preview, no Xcode needed
```

Desktop targets: macOS, Windows, Linux. The web build is used for previews;
file-system features (folder sidebar, watching) are desktop-only.

## Development

- `docs/ARCHITECTURE.md` — module map.
- `docs/DESIGN-editor-interaction.md` — the full editing-semantics spec
  (Enter/Backspace tables, offset mapping, undo coalescing rules).
- `docs/DESIGN-themes.md` — theme JSON schema + the built-in theme values.
- `flutter test` — document round-trip + editor semantics suites.

## Roadmap

LaTeX math rendering, mermaid diagrams, PDF export, image paste, cross-block
selection, typewriter mode.
