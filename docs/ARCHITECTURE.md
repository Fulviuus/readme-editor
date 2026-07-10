# readme — Architecture

A live markdown editor built with Flutter. Desktop-first (macOS/Windows/Linux), web used as a dev/preview target.

## Product principles

1. **One surface.** No split source/preview panes. The document *is* the editor.
2. **Hybrid rendering.** The block you are editing shows its raw markdown, live-styled
   (bold shows bold, `**` markers visible but dimmed). Every other block renders fully.
3. **Themes are first-class.** Visuals come from a theme definition, never hard-coded.
   Five built-in themes ship (GitHub, Night, Newsprint, Pixyll, Whitey); users can
   drop custom JSON themes in a themes folder.
4. **Files are plain markdown.** Round-trip fidelity: open → edit → save produces minimal
   diffs (only blocks you touched change).

## Layer map

```
lib/
  main.dart                    app entry, window/app setup
  src/
    document/                  pure Dart, no Flutter imports (unit-testable)
      block.dart               Block model (sealed), BlockType
      block_splitter.dart      markdown text -> List<Block>  (block boundaries only)
      serializer.dart          List<Block> -> markdown text
      document.dart            Document: blocks + metadata (path, dirty)
      document_controller.dart edit ops, undo/redo, ChangeNotifier
    editor/
      editor_view.dart         scrollable block list, focus orchestration
      editing_block.dart       focused block: TextField + controller
      markdown_editing_controller.dart  buildTextSpan live styling of raw source
      inline_renderer.dart     inline AST -> InlineSpan + offset map (caret transfer)
      rendered_block.dart      dispatch Block -> per-type widget
      blocks/                  per-type rendered widgets (code, table, list, quote, ...)
      shortcuts.dart           formatting intents (Cmd+B/I/K, headings)
      find_controller.dart     find/replace state
      source_view.dart         whole-document source mode
    theme/
      readme_theme.dart        theme data model (pure Dart + Flutter TextStyles)
      theme_json.dart          JSON schema encode/decode
      theme_manager.dart       built-ins + user themes dir + persistence
      builtin_themes.dart      5 built-in themes (values pinned to upstream CSS)
    workspace/
      workspace_controller.dart open file/folder, save, recent files, watcher
      html_export.dart         AST -> themed standalone HTML
    app/
      app.dart                 MaterialApp + providers wiring
      home_shell.dart          sidebar | editor | status bar layout
      app_menu.dart            PlatformMenuBar (macOS) + fallback menu, shortcuts
      sidebar/file_tree.dart   folder tree
      sidebar/outline_pane.dart heading outline
      status_bar.dart          word count, cursor context, theme name
    util/
      word_count.dart
```

**Dependency rule:** `document/` imports nothing from Flutter. `editor/` and `theme/`
depend on `document/`. `app/` depends on everything. No cycles.

## Core model

```dart
enum BlockKind { paragraph, heading, fencedCode, blockquote, list, table,
                 thematicBreak, html, mathBlock }

class Block {
  final String id;          // stable identity for focus/undo across rebuilds
  final BlockKind kind;
  final String source;      // raw markdown, no trailing blank line
  // kind-specific derived fields (heading level, fence language, list type)
  // are computed lazily from source and cached.
}
```

- The **document is the single source of truth as markdown text**, held as
  `List<Block>`. Rendering parses per-block source on demand (package:markdown AST);
  a per-block parse cache keyed on `source` keeps re-render cheap.
- **DocumentController** owns all mutations: `updateBlock`, `splitBlock`, `mergeWithPrevious`,
  `insertBlock`, `removeBlock`, `replaceAll`. Every mutation pushes a `DocumentEdit` onto a
  single undo stack (typing edits coalesce). Notifies listeners; EditorView rebuilds.
- **Focus model:** `EditorFocus` (ChangeNotifier) holds `focusedBlockId + caret offset`.
  Exactly one block is in edit mode. Blur commits, focus converts click position → source
  offset via the inline renderer's offset map.

## Theme model

`ReadmeTheme` captures what a full editor stylesheet captures: page colors, body/mono font
stacks, base size/line-height, per-element styles (h1–h6, code, blockquote, links, tables,
hr, selection, caret), code-token colors, plus chrome (sidebar/status bar). Serialized as
flat human-editable JSON. `ThemeManager` loads built-ins + `~/Library/Application
Support/readme/themes/*.json` (platform equivalent), persists the selection.

## What v1 includes / excludes

**In:** hybrid editing for all CommonMark+GFM block types, syntax-highlighted code blocks,
task lists, tables (raw-source editing with styled preview), inline styling while editing,
auto block conversion (`# `, `- `, `> `, ``` triggers), file tree + outline sidebar, themes,
find/replace, source mode, HTML export, word count, undo/redo.

**Out (roadmap):** LaTeX math (pending package health check), mermaid diagrams, PDF export,
image paste-from-clipboard, cross-block selection (v1: single-block selection + source mode
fallback; Select All → source mode).
