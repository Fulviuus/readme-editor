# Flutter Package Picks for "readme" (live markdown editor) — verified on pub.dev, July 9 2026

**Toolchain baseline:** Flutter stable **3.44** (latest hotfix **3.44.3**, 2026-06-22) with **Dart 3.12.2**. All picks below resolve on this SDK.

## Final picks

| # | Area | Pick | Version | Publisher | Web-safe? |
|---|------|------|---------|-----------|-----------|
| 1 | Markdown → AST | `markdown` | 7.3.1 (2026-03-18) | tools.dart.dev | Yes (pure Dart) |
| 1b | Renderer | **Write our own** over the AST | — | — | Yes |
| 2 | Syntax highlighting | `re_highlight` | 0.0.3 (2024-02-05) | reqable.com | Yes (pure Dart) |
| 3 | LaTeX math | **Skip for v1** (`flutter_math_fork` 0.7.4 if forced) | — | simpleclub.com | Risky on web |
| 4 | File open/save dialogs | `file_selector` | 1.1.0 (2025-11-21) | flutter.dev | Partial — open only |
| 5 | Folder watching | `watcher` | 1.2.1 (2026-01-08) | tools.dart.dev | **No (dart:io)** |
| 6 | Settings persistence | `shared_preferences` | 2.5.5 (2026-03-25) | flutter.dev | Yes (localStorage) |
| 7 | State management | `provider` | 6.1.5+1 (2025-08-19) | dash-overflow.net | Yes |
| 8 | Menus / window | `PlatformMenuBar` (built-in) + `window_manager` | 0.5.2 (2026-07-04) | flutter / leanflutter.dev | No-op guard on web |
| 9 | Drag-and-drop | `desktop_drop` | 0.7.1 (2026-04-19) | mixin.dev | Yes |

## Rationales

### 1. Markdown parsing: `markdown` 7.3.1
Current major is **7.x**; healthy (364 likes, published 3 months ago, verified `tools.dart.dev`, requires Dart ^3.9.0 — fine on 3.12). Verified from source (`dart-lang/tools/pkgs/markdown/lib/src/extension_set.dart`): **`ExtensionSet.gitHubFlavored` includes ALL four required features** — `TableSyntax`, `UnorderedListWithCheckboxSyntax` + `OrderedListWithCheckboxSyntax` (task lists), `StrikethroughSyntax`, and `FootnoteDefSyntax` (plus fenced code, inline HTML, autolinks). `ExtensionSet.gitHubWeb` additionally adds `AlertBlockSyntax` (GitHub `> [!NOTE]` admonitions), emoji, and header IDs — consider gitHubFlavored + `AlertBlockSyntax` à la carte.

**flutter_markdown is confirmed discontinued** (0.7.7+1, flutter.dev, last publish 14 months ago; pub.dev shows the discontinued banner with `flutter_markdown_plus` as the suggested replacement). Writing our own renderer over the AST is the right call for theme control. Fallback/reference alternatives if we stall: `flutter_markdown_plus` 1.0.11 (published **2 days ago**, active drop-in fork), `gpt_markdown` 1.1.7 (May 2026, streaming/LLM-oriented), `markdown_widget` 2.3.2+8 (Apr 2025, uses its own parser pipeline — less useful to us).

### 2. Syntax highlighting: `re_highlight` 0.0.3
The field is weak, and this is the least-bad by a clear margin:
- `flutter_highlight` 0.7.0 — **5 years dead** (2021, unverified uploader). Rule out.
- `highlighting` 0.9.0+11.8.0 — 3 years old (2023), 7 likes. Rule out.
- `syntax_highlight` 0.5.0 (serverpod.dev, Aug 2025) — nice TextMate/VSCode-grammar quality but only **15 bundled languages**; fails the "many languages" requirement.
- `re_highlight` 0.0.3 — pure-Dart port of highlight.js **v11.9.0** (passes upstream test suite), dozens of languages, all highlight.js themes ported, renders to `TextSpan` via a `Map<String, TextStyle>` theme — exactly the theme-control hook we need. Yes, last publish is Feb 2024, but grammars don't rot, it has zero Flutter-render coupling (spans only, deps: `collection`, `path`), and **`re_editor` 0.10.0 — published 2026-07-01 — depends on `re_highlight ^0.0.3`**, proving it works on current stable Flutter. Web-safe.

### 3. LaTeX math: skip for v1
`flutter_math_fork` 0.7.4 (simpleclub.com verified, 171 likes) is alive-ish — 0.7.4 (May 2025) fixed the Flutter 3.29 `RenderObjectWithLayoutCallbackMixin` build break — but there's been **no release in 13+ months** across the 3.35/3.38/3.44 cycles, open layout bugs (#120 infinite constraints with `\frac`/`\sqrt`, #131 KaTeX parse errors, Jul 2026), and its README warns web support "is expected to break with CanvasKit" — which collides directly with our flutter-web smoke-test workflow. **Ship v1 without math; render ` ```math ` / `$$` blocks as styled code blocks so documents round-trip losslessly.** Revisit for v1.1.

### 4. File dialogs: `file_selector` 1.1.0
First-party (flutter.dev, 434 likes, Nov 2025, Dart ^3.9). Save-file dialogs and directory picking confirmed on **macOS, Windows, and Linux** — exactly what an editor needs (open, save-as, open-folder). `file_picker` 11.0.2 (miguelruivo.com, Apr 2026, 4.92k likes) is also healthy but is a heavier all-platform kitchen sink mid-transition to a 12.0 beta; first-party wins for a desktop-first app. Web caveat below.

### 5. Folder watching: `watcher` 1.2.1
Healthy: tools.dart.dev, 247 likes, ~10M downloads, published Jan 2026. Native `FSEvents`-backed on macOS, `ReadDirectoryChangesW` on Windows, polling fallback on Linux. **dart:io-based — no web support at all.** The entire file-tree sidebar + watch feature must be behind `!kIsWeb`.

### 6. Settings: `shared_preferences` 2.5.5
Confirmed supported on **macOS (NSUserDefaults), Windows and Linux (file-backed)** plus web (localStorage). flutter.dev, 10.5k likes, Mar 2026. Use the new **`SharedPreferencesAsync`** API — the legacy `SharedPreferences` API is flagged for future deprecation.

### 7. State: `provider` 6.1.5+1
Confirmed healthy: dash-overflow.net (Remi Rousselet), 10.9k likes, 150 pub points, ~1.13M weekly downloads, Flutter Favorite, no deprecation. Feature-complete/stable rather than fast-moving — ideal for plain `ChangeNotifier` + `provider`.

### 8. Menus/window: built-in `PlatformMenuBar` + `window_manager` 0.5.2
Confirmed: `PlatformMenuBar` is in the Flutter framework and drives the **native macOS menu bar; macOS only out of the box** (other platforms need a plugin/delegate). On Windows/Linux use Flutter's in-app `MenuBar` widget instead. `window_manager` (leanflutter.dev, 1.1k likes, published **5 days ago**) is worth including — it covers three things Flutter can't do natively: runtime window title (`setTitle` showing current filename + dirty dot), minimum window size, and `setPreventClose`/`onWindowClose` for the "unsaved changes" prompt. Essential for editor UX, though the app boots without it. (Note: leanflutter is migrating it to a shared C++ core `nativeapi` — current version stable.)

### 9. Drag-and-drop: `desktop_drop` 0.7.1
Healthy: mixin.dev verified, 463 likes, Apr 2026. Windows/macOS/Linux **and web** supported via a simple `DropTarget` widget. Include it.

### 10. SDK compatibility
Flutter 3.44.3 / Dart 3.12.2: `markdown` needs `^3.9.0` ✓; `re_highlight` needs `>=2.17.0 <4.0.0` ✓ (independently evidenced by re_editor's July 2026 release on it). Everything else in the table is on `^3.4`–`^3.9` constraints ✓.

## Web smoke-test guard list (we test via `flutter run -d chrome`)

| Concern | Status | Guard |
|---|---|---|
| `dart:io` File read/write (our own code) | Not on web | Abstract behind a `FileSystem` interface; in-memory impl for web |
| `watcher` | **dart:io only — will not compile into web build if imported unconditionally** | Conditional import / `!kIsWeb`-gated module for the sidebar |
| `file_selector` | `openFile` works on web (bytes); `getSavePath` / `getDirectoryPath` unsupported | `kIsWeb` → download-bytes fallback or hide Save As / Open Folder |
| `window_manager` | Desktop only | Only call after `!kIsWeb && (Platform.isMacOS/.isWindows/.isLinux)` |
| `PlatformMenuBar` | macOS only (no-op elsewhere; use `MenuBar` widget on Win/Linux/web) | `defaultTargetPlatform == TargetPlatform.macOS && !kIsWeb` |
| `desktop_drop` | Web supported | None |
| `markdown`, `re_highlight`, `provider`, `shared_preferences` | Pure Dart / web impls | None |
| `flutter_math_fork` (if ever added) | README warns CanvasKit web rendering may break | Another reason it's deferred |

Sources: [pub.dev/packages/markdown](https://pub.dev/packages/markdown), [pub.dev/packages/flutter_markdown](https://pub.dev/packages/flutter_markdown), [pub.dev/packages/flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus), [markdown ExtensionSet source](https://raw.githubusercontent.com/dart-lang/tools/main/pkgs/markdown/lib/src/extension_set.dart), [pub.dev/packages/re_highlight](https://pub.dev/packages/re_highlight), [re-highlight README](https://github.com/reqable/re-highlight), [pub.dev/packages/syntax_highlight](https://pub.dev/packages/syntax_highlight), [pub.dev/packages/highlighting](https://pub.dev/packages/highlighting), [pub.dev/packages/flutter_highlight](https://pub.dev/packages/flutter_highlight), [pub.dev/packages/flutter_math_fork](https://pub.dev/packages/flutter_math_fork), [simpleclub/flutter_math issues](https://github.com/simpleclub/flutter_math/issues), [pub.dev/packages/file_selector](https://pub.dev/packages/file_selector), [pub.dev/packages/file_picker](https://pub.dev/packages/file_picker), [pub.dev/packages/watcher](https://pub.dev/packages/watcher), [pub.dev/packages/shared_preferences](https://pub.dev/packages/shared_preferences), [pub.dev/packages/provider](https://pub.dev/packages/provider), [PlatformMenuBar API docs](https://api.flutter.dev/flutter/widgets/PlatformMenuBar-class.html), [pub.dev/packages/window_manager](https://pub.dev/packages/window_manager), [pub.dev/packages/desktop_drop](https://pub.dev/packages/desktop_drop), [Flutter SDK archive](https://docs.flutter.dev/install/archive), [Flutter 3.44.3 / Dart 3.12.2](https://flutterreleases.com/release/3.44.3/), and pub.dev API (`pub.dev/api/packages/*`) for exact versions/dates.