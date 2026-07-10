# readme — Feature gap analysis & roadmap

Compiled 2026-07-10 by walking the reference editor's complete menu tree
(via the macOS Accessibility API) and auditing readme's code for each item.
Status: ✓ done · ◐ partial · ✗ missing · — not planned / not applicable.

## File

| Feature | Status | Notes |
|---|---|---|
| New | ✓ | |
| New Tab / New Window | ✗ | readme is single-window, single-document |
| Open… | ✓ | |
| Open Recent (+ Clear items) | ◐ | submenu exists; **no "Clear" item** |
| Open Quickly (fuzzy open) | ✗ | |
| Get Info / Reveal in File Tree / Open File Location | ✗ | reveal-in-Finder is a cheap add |
| Delete (move file to trash) | ✗ | |
| Save / Save As | ✓ | |
| Duplicate / Rename / Move To | ✗ | |
| Revert To (macOS versions) | ✗ | needs NSDocument-style integration; defer |
| Share sheet | ✗ | `share_plus` 13.x supports macOS (verified) |
| Import (docx/odt via Pandoc) | ✗ | defer; Pandoc-shell-out design needed |
| Export → HTML | ✓ | themed standalone HTML |
| Export → PDF / Image / Word / Epub / LaTeX / RTF… | ✗ | PDF feasible via `printing` 5.15 + `pdf` (verified healthy); others via Pandoc |
| Page Setup / Print | ✗ | `printing` covers this too |

## Edit

| Feature | Status | Notes |
|---|---|---|
| Undo / Redo | ✓ | document-level stack with coalescing |
| Cut / Copy / Paste / Select All **menu items** | ✗ | shortcuts work inside the TextField, but the macOS Edit menu lacks the items |
| Copy as Markdown / HTML / Plain Text; Copy without styling | ✗ | copy always yields raw markdown today |
| Paste as Plain Text / Match Style | ✗ | |
| Selection commands (paragraph/line/word/scope, jump to top/bottom) | ✗ | native TextField basics only |
| Move Row (paragraph) Up / Down | ✗ | easy structural op on the block list |
| Delete Range (paragraph/line/word/scope) | ✗ | |
| Line endings (CRLF/LF switch, final-newline toggle) | ◐ | preserved on round-trip; no UI to change |
| Whitespace/line-break prefs (visible `<br/>`, preserve single break) | ✗ | |
| Substitutions (smart quotes/dashes) | ✗ | |
| Spelling & grammar | ✗ | **hard**: Flutter desktop has no built-in spell check (verified — needs a custom SpellCheckService over NSSpellChecker) |
| Find / Find Next / Previous / Replace | ✓ | bar with buttons, Enter/Shift+Enter, case toggle |
| Emoji & symbols palette | ◐ | system palette works in focused fields; no menu item |
| Speech / Dictation / AutoFill | — | AppKit text-service items; low value for v1.x |

## Paragraph

| Feature | Status | Notes |
|---|---|---|
| Heading 1–6 / Paragraph (menu + Cmd+0–6) | ✓ | |
| Increase / Decrease heading level | ✗ | trivial on top of setHeadingLevel |
| Table → Insert Table (rows×cols dialog) | ✗ | today tables only appear by typing a delimiter row |
| Table → add/delete/move row/column | ✗ | menu-driven table ops (Tab/Enter nav exists) |
| Table → Prettify source (align pipes) | ✗ | |
| Code fences / Math block / Quote / Lists / Task list / HR **as menu items** | ◐ | all exist as typing auto-conversions only; menus have none |
| Code Tools (copy code content, auto-indent) | ✗ | |
| Alert blocks (`> [!NOTE]` …) | ✗ | `AlertBlockSyntax` ships in our markdown dep (verified) — parser+renderer wiring only |
| Task Status (toggle/mark complete) | ◐ | checkbox click works; no menu/shortcut |
| List indent / outdent | ◐ | Tab/Shift+Tab work; no menu items |
| Insert Paragraph Before / After | ✗ | easy |
| Link Reference (`[x][ref]`) | ✗ | tokenizer doesn't support reference links at all |
| Footnotes | ✗ | `FootnoteDefSyntax` ships in our markdown dep (verified) |
| Table of Contents (`[TOC]`) | ✗ | |
| YAML Front Matter | ◐ | parsed/preserved/edited; no insert menu item |

## Format

| Feature | Status | Notes |
|---|---|---|
| Strong / Emphasis / Code / Strike / Hyperlink | ✓ | Cmd+B/I/E/Shift+D/K |
| Underline (`<u>`) | ✗ | inline HTML renders as dimmed source today |
| Comment (`<!-- -->`) | ✗ | |
| **Open Link / Copy Link Address** | ✗ | **no way to open a hyperlink in the app at all** (needs url_launcher + Cmd+click or context menu) |
| Image → Insert / Insert Local… | ✗ | rendering exists; no insertion UI |
| Image management (copy/move/upload images, root path, zoom, syntax switch) | ✗ | large surface; phase it |
| Insert from iPhone (Continuity Camera) | — | AppKit-native; defer indefinitely |
| Clear Format | ✗ | strip inline markers from selection — easy |

## View

| Feature | Status | Notes |
|---|---|---|
| Source Code Mode | ✓ | Cmd+/ |
| Focus Mode | ✓ | F8 |
| Typewriter Mode | ✗ | flag exists in EditorController but is dead (verified) — spec §9 has the design |
| Sidebar: Files / Outline | ◐ | two fixed tabs only |
| **Sidebar content modes** (View-menu selectable: Outline / Articles / File Tree / Search) | ✗ | the reference sidebar switches between four panes from the View menu; readme has no Articles (flat file list) pane, no Search pane, and no menu items to select the pane |
| Search (across all files in folder) | ✗ | sidebar global search pane — meaningful feature |
| Word count | ◐ | words+chars in status bar; readingMinutes computed but unused; no popover with per-selection counts |
| Zoom In / Out / Actual Size (UI scale) | ✗ | |
| Always on Top | ✗ | window_manager.setAlwaysOnTop exists (verified) — trivial |
| Full Screen / Window menu (Minimize, Zoom) | ✗ | no Window menu at all; PlatformProvidedMenuItem covers these |
| Tabs (Show Tab Bar…) | ✗ | with New Tab above; big architectural item |

## Themes

| Feature | Status | Notes |
|---|---|---|
| Github / Night / Newsprint / Pixyll / Whitey | ✓ | |
| **Gothic** | ✗ | the one built-in theme we did not port |
| Custom themes folder | ✓ | JSON schema (docs/DESIGN-themes.md) |

## App / other

| Feature | Status | Notes |
|---|---|---|
| Settings / Preferences window | ✗ | font size, autosave, image handling, editor width… nothing yet |
| Autosave | ✗ | |
| LaTeX math rendering | ✗ | deliberate v1 exclusion; flutter_math_fork compatibility with Flutter 3.44 unverified — needs a spike |
| Mermaid / diagrams | ✗ | v1 exclusion |
| Cross-block selection | ✗ | v1 contract: single-block + source mode |

## Suggested order of attack

**Tier 1 — quick wins (each ≤ a day, mostly wiring):**
Window menu + Fullscreen/Minimize + Always on Top; Cut/Copy/Paste/Select All
menu items; block-conversion menu items (quote/lists/fence/math/HR/front
matter); Increase/Decrease heading; Insert Paragraph Before/After; Insert
Table dialog + row/column menu ops; Clear Format; Clear Recent; open-link
via Cmd+click + context menu (url_launcher); reading time in status bar;
typewriter mode (design already in spec §9); alert blocks + footnotes
(syntaxes already in the markdown package); Gothic theme port.

**Tier 2 — real features (days each):**
PDF export + Print (`printing`); image insertion + basic local-image
management; global folder search in sidebar; copy-as HTML/plain; table
prettify; TOC; reference links in the tokenizer; UI zoom; file ops
(rename/duplicate/move/reveal/delete); Share sheet; preferences window +
autosave; Open Quickly.

**Tier 3 — hard / needs a spike first:**
LaTeX math (flutter_math_fork compat spike); tabs & multi-window; spell
check (custom NSSpellChecker bridge); Pandoc import/export (docx, epub…);
macOS Versions/Revert To.
