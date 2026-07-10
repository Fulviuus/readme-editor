# Built-in theme extraction for "readme"

Source: the upstream theme CSS files (fetched 2026-07-09) archived locally during extraction (not committed) together with `night-codeblock.dark.css` (imported by night.css and the only source of its code token colors). All hex values below are verbatim from the CSS unless listed in a theme's `_derived` array (caveats at the end).

## 1. The "readme" theme JSON schema

Theme files are plain JSON dropped into `themes/<id>.json`. Comments below are documentation only (real files must be comment-free JSON). Conventions: colors are `#RRGGBB` or `#RRGGBBAA`; sizes are px numbers; font stacks are arrays tried in order; `null` means "inherit / none" as noted per key; the 6-element arrays always map to h1..h6.

```jsonc
{
  "$schema": "readme-theme-v1",        // format version tag
  "name": "GitHub",                    // display name in the theme picker
  "dark": false,                       // drives editor chrome + hljs preset fallback

  // ---- canvas -------------------------------------------------------------
  "background": "#ffffff",             // page/editor background
  "foreground": "#333333",             // default text color
  "accent": "#4183C4",                 // primary/brand color (buttons, focus, highlights)
  "caret": "#333333",                  // text cursor color
  "selectionBackground": "#B5D6FC",    // selected-text background
  "selectionForeground": null,         // null = keep text color

  // ---- typography ---------------------------------------------------------
  "fontFamily": ["Open Sans", "Helvetica", "sans-serif"], // body stack
  "monoFontFamily": ["Consolas", "monospace"],            // code stack
  "headingFontFamily": null,           // null = same as fontFamily
  "fontSize": 16,                      // base body size, px
  "fontWeight": 400,                   // base body weight
  "lineHeight": 1.6,                   // unitless multiplier
  "contentMaxWidth": 860,              // px width of the writing column

  // ---- headings (arrays are h1..h6) ---------------------------------------
  "headingSizes":   [36, 28, 24, 20, 16, 16],   // px
  "headingWeights": [700, 700, 700, 700, 700, 700],
  "headingColors":  [null, null, null, null, null, "#777777"], // null = foreground
  "headingItalics": [false, false, false, false, false, false],
  "headingAligns":  ["left","left","left","left","left","left"],
  "h1BorderBottom": "#eeeeee",         // null = no rule under h1
  "h1BorderWidth": 1,
  "h2BorderBottom": "#eeeeee",         // null = no rule under h2
  "h2BorderWidth": 1,

  // ---- inline code ----------------------------------------------------------
  "codeInlineForeground": null,        // null = foreground
  "codeInlineBackground": "#f3f4f4",   // null = transparent
  "codeInlineBorder": "#e7eaed",       // null = no border
  "codeInlineRadius": 3,               // px corner radius
  "codeInlineFontScale": 0.9,          // multiplier of body size

  // ---- fenced code block ----------------------------------------------------
  "codeBlockBackground": "#f8f8f8",
  "codeBlockForeground": null,         // default token color; null = foreground
  "codeBlockBorder": "#e7eaed",
  "codeBlockRadius": 3,
  "codeBlockFontScale": 0.9,

  // ---- syntax highlighting ----------------------------------------------------
  // Either name a bundled preset, or set it null and give explicit tokens.
  // Recognized presets: "highlightjs-github", "highlightjs-atom-one-dark".
  "syntaxPreset": "highlightjs-github",
  "syntaxComment": null,               // token overrides; used when preset is null
  "syntaxKeyword": null,
  "syntaxString": null,
  "syntaxNumber": null,
  "syntaxFunction": null,              // titles / defs / function names
  // optional extra tokens (all nullable): syntaxVariable, syntaxTag,
  // syntaxAttribute, syntaxAtom, syntaxBuiltin, syntaxMeta, syntaxBracket,
  // syntaxLink, syntaxQuote

  // ---- blockquote ------------------------------------------------------------
  "blockquoteForeground": "#777777",   // null = foreground
  "blockquoteBorder": "#dfe2e5",       // left bar color
  "blockquoteBorderWidth": 4,          // px
  "blockquoteBackground": null,
  "blockquoteItalic": false,

  // ---- links & rules -----------------------------------------------------------
  "link": "#4183C4",
  "linkHover": "#4183C4",
  "linkUnderline": "hover",            // "none" | "hover" | "always"
  "hr": "#e7e7e7",
  "hrHeight": 2,                       // px

  // ---- tables --------------------------------------------------------------
  "tableBorder": "#dfe2e5",            // null = borderless table
  "tableHeaderBackground": "#f8f8f8",  // null = none
  "tableStripeBackground": "#f8f8f8",  // even-row zebra; null = none

  // ---- task lists ------------------------------------------------------------
  "checkboxAccent": "#4183C4",         // checked fill / check color
  "checkboxBorder": null,              // unchecked outline; null = platform default

  // ---- app chrome (sidebar etc.) ----------------------------------------------
  "sidebarBackground": "#fafafa",
  "sidebarForeground": "#777777",
  "sidebarActiveBackground": "#eeeeee",
  "sidebarActiveForeground": null,     // null = sidebarForeground

  // keys whose values were derived, not read from the source theme
  "_derived": ["background", "selectionBackground"]
}
```

## 2. The five themes

### github.json

```json
{
  "$schema": "readme-theme-v1",
  "name": "GitHub",
  "dark": false,
  "background": "#ffffff",
  "foreground": "#333333",
  "accent": "#4183C4",
  "caret": "#333333",
  "selectionBackground": "#B5D6FC",
  "selectionForeground": null,
  "fontFamily": ["Open Sans", "Clear Sans", "Helvetica Neue", "Helvetica", "Arial", "Segoe UI Emoji", "sans-serif"],
  "monoFontFamily": ["Menlo", "Consolas", "Courier New", "monospace"],
  "headingFontFamily": null,
  "fontSize": 16,
  "fontWeight": 400,
  "lineHeight": 1.6,
  "contentMaxWidth": 860,
  "headingSizes": [36, 28, 24, 20, 16, 16],
  "headingWeights": [700, 700, 700, 700, 700, 700],
  "headingColors": [null, null, null, null, null, "#777777"],
  "headingItalics": [false, false, false, false, false, false],
  "headingAligns": ["left", "left", "left", "left", "left", "left"],
  "h1BorderBottom": "#eeeeee",
  "h1BorderWidth": 1,
  "h2BorderBottom": "#eeeeee",
  "h2BorderWidth": 1,
  "codeInlineForeground": null,
  "codeInlineBackground": "#f3f4f4",
  "codeInlineBorder": "#e7eaed",
  "codeInlineRadius": 3,
  "codeInlineFontScale": 0.9,
  "codeBlockBackground": "#f8f8f8",
  "codeBlockForeground": null,
  "codeBlockBorder": "#e7eaed",
  "codeBlockRadius": 3,
  "codeBlockFontScale": 0.9,
  "syntaxPreset": "highlightjs-github",
  "syntaxComment": null,
  "syntaxKeyword": null,
  "syntaxString": null,
  "syntaxNumber": null,
  "syntaxFunction": null,
  "blockquoteForeground": "#777777",
  "blockquoteBorder": "#dfe2e5",
  "blockquoteBorderWidth": 4,
  "blockquoteBackground": null,
  "blockquoteItalic": false,
  "link": "#4183C4",
  "linkHover": "#4183C4",
  "linkUnderline": "hover",
  "hr": "#e7e7e7",
  "hrHeight": 2,
  "tableBorder": "#dfe2e5",
  "tableHeaderBackground": "#f8f8f8",
  "tableStripeBackground": "#f8f8f8",
  "checkboxAccent": "#4183C4",
  "checkboxBorder": null,
  "sidebarBackground": "#fafafa",
  "sidebarForeground": "#777777",
  "sidebarActiveBackground": "#eeeeee",
  "sidebarActiveForeground": null,
  "_derived": ["background", "caret", "selectionBackground", "monoFontFamily", "linkHover", "linkUnderline", "checkboxAccent", "sidebarActiveBackground", "syntaxPreset"]
}
```

### night.json

```json
{
  "$schema": "readme-theme-v1",
  "name": "Night",
  "dark": true,
  "background": "#363B40",
  "foreground": "#b8bfc6",
  "accent": "#6dc1e7",
  "caret": "#b8bfc6",
  "selectionBackground": "#4a89dc",
  "selectionForeground": "#ffffff",
  "fontFamily": ["Helvetica Neue", "Helvetica", "Arial", "Segoe UI Emoji", "sans-serif"],
  "monoFontFamily": ["Monaco", "Consolas", "Andale Mono", "DejaVu Sans Mono", "monospace"],
  "headingFontFamily": ["Lucida Grande", "Corbel", "sans-serif"],
  "fontSize": 16,
  "fontWeight": 400,
  "lineHeight": 1.625,
  "contentMaxWidth": 914,
  "headingSizes": [40, 26.08, 18.72, 17.92, 15.52, 14.88],
  "headingWeights": [400, 700, 700, 400, 700, 400],
  "headingColors": ["#DEDEDE", "#DEDEDE", "#DEDEDE", "#ffffff", "#DEDEDE", "#ffffff"],
  "headingItalics": [false, false, false, false, false, false],
  "headingAligns": ["left", "left", "left", "left", "left", "left"],
  "h1BorderBottom": null,
  "h1BorderWidth": 0,
  "h2BorderBottom": null,
  "h2BorderWidth": 0,
  "codeInlineForeground": null,
  "codeInlineBackground": "#0000000D",
  "codeInlineBorder": null,
  "codeInlineRadius": 0,
  "codeInlineFontScale": 0.875,
  "codeBlockBackground": "#333333",
  "codeBlockForeground": "#b8bfc6",
  "codeBlockBorder": null,
  "codeBlockRadius": 0,
  "codeBlockFontScale": 0.875,
  "syntaxPreset": null,
  "syntaxComment": "#DA924A",
  "syntaxKeyword": "#C88FD0",
  "syntaxString": "#D26B6B",
  "syntaxNumber": "#64AB8F",
  "syntaxFunction": "#8d8df0",
  "syntaxVariable": "#b8bfc6",
  "syntaxTag": "#7DF46A",
  "syntaxAttribute": "#7575E4",
  "syntaxAtom": "#84B6CB",
  "syntaxBuiltin": "#f3b3f8",
  "syntaxMeta": "#b7b3b3",
  "syntaxBracket": "#999977",
  "syntaxLink": "#d3d3ef",
  "syntaxQuote": "#57ac57",
  "blockquoteForeground": "#9DA2A6",
  "blockquoteBorder": "#474d54",
  "blockquoteBorderWidth": 2,
  "blockquoteBackground": null,
  "blockquoteItalic": false,
  "link": "#e0e0e0",
  "linkHover": "#ffffff",
  "linkUnderline": "always",
  "hr": "#474d54",
  "hrHeight": 2,
  "tableBorder": "#474d54",
  "tableHeaderBackground": null,
  "tableStripeBackground": null,
  "checkboxAccent": "#DEDEDE",
  "checkboxBorder": "#b8bfc6",
  "sidebarBackground": "#2E3033",
  "sidebarForeground": "#b7b7b7",
  "sidebarActiveBackground": "#222222",
  "sidebarActiveForeground": "#ffffff",
  "_derived": []
}
```

### newsprint.json

```json
{
  "$schema": "readme-theme-v1",
  "name": "Newsprint",
  "dark": false,
  "background": "#f3f2ee",
  "foreground": "#1f0909",
  "accent": "#065588",
  "caret": "#1f0909",
  "selectionBackground": "#202B33A1",
  "selectionForeground": "#ffffff",
  "fontFamily": ["PT Serif", "Times New Roman", "Times", "serif"],
  "monoFontFamily": ["Menlo", "Consolas", "Courier New", "monospace"],
  "headingFontFamily": null,
  "fontSize": 16,
  "fontWeight": 400,
  "lineHeight": 1.5,
  "contentMaxWidth": 640,
  "headingSizes": [30, 21, 21, 18, 16, 16],
  "headingWeights": [400, 700, 400, 700, 700, 700],
  "headingColors": [null, null, null, null, null, null],
  "headingItalics": [false, false, false, false, false, false],
  "headingAligns": ["left", "left", "left", "left", "left", "left"],
  "h1BorderBottom": "#c5c5c5",
  "h1BorderWidth": 1,
  "h2BorderBottom": null,
  "h2BorderWidth": 0,
  "codeInlineForeground": null,
  "codeInlineBackground": "#dadada",
  "codeInlineBorder": null,
  "codeInlineRadius": 0,
  "codeInlineFontScale": 0.875,
  "codeBlockBackground": "#dadada",
  "codeBlockForeground": null,
  "codeBlockBorder": null,
  "codeBlockRadius": 0,
  "codeBlockFontScale": 0.875,
  "syntaxPreset": "highlightjs-github",
  "syntaxComment": null,
  "syntaxKeyword": null,
  "syntaxString": null,
  "syntaxNumber": null,
  "syntaxFunction": null,
  "blockquoteForeground": "#656565",
  "blockquoteBorder": "#bababa",
  "blockquoteBorderWidth": 5,
  "blockquoteBackground": null,
  "blockquoteItalic": true,
  "link": "#065588",
  "linkHover": "#065588",
  "linkUnderline": "hover",
  "hr": "#c5c5c5",
  "hrHeight": 1,
  "tableBorder": null,
  "tableHeaderBackground": "#dadada",
  "tableStripeBackground": "#e8e7e7",
  "checkboxAccent": "#1f0909",
  "checkboxBorder": null,
  "sidebarBackground": "#f3f2ee",
  "sidebarForeground": "#444444",
  "sidebarActiveBackground": "#202B33A1",
  "sidebarActiveForeground": "#ffffff",
  "_derived": ["caret", "monoFontFamily", "syntaxPreset"]
}
```

### pixyll.json

```json
{
  "$schema": "readme-theme-v1",
  "name": "Pixyll",
  "dark": false,
  "background": "#ffffff",
  "foreground": "#333333",
  "accent": "#463F5C",
  "caret": "#428bca",
  "selectionBackground": "#B5D6FC",
  "selectionForeground": null,
  "fontFamily": ["Merriweather", "PT Serif", "Georgia", "Times New Roman", "STSong", "Segoe UI Emoji", "serif"],
  "monoFontFamily": ["Menlo", "Monaco", "Courier New", "monospace"],
  "headingFontFamily": ["Lato", "Helvetica Neue", "Helvetica", "sans-serif"],
  "fontSize": 20,
  "fontWeight": 300,
  "lineHeight": 1.8,
  "contentMaxWidth": 914,
  "headingSizes": [52, 36.77, 26, 20.8, 18, 18],
  "headingWeights": [700, 700, 700, 700, 700, 700],
  "headingColors": [null, null, null, null, null, null],
  "headingItalics": [false, false, false, false, false, false],
  "headingAligns": ["left", "left", "left", "left", "left", "left"],
  "h1BorderBottom": null,
  "h1BorderWidth": 0,
  "h2BorderBottom": null,
  "h2BorderWidth": 0,
  "codeInlineForeground": "#7a7a7a",
  "codeInlineBackground": null,
  "codeInlineBorder": null,
  "codeInlineRadius": 0,
  "codeInlineFontScale": 1.0,
  "codeBlockBackground": null,
  "codeBlockForeground": "#7a7a7a",
  "codeBlockBorder": "#7a7a7a",
  "codeBlockRadius": 0,
  "codeBlockFontScale": 0.8,
  "syntaxPreset": "highlightjs-github",
  "syntaxComment": null,
  "syntaxKeyword": null,
  "syntaxString": null,
  "syntaxNumber": null,
  "syntaxFunction": null,
  "blockquoteForeground": "#555555",
  "blockquoteBorder": "#7a7a7a",
  "blockquoteBorderWidth": 5,
  "blockquoteBackground": null,
  "blockquoteItalic": true,
  "link": "#463F5C",
  "linkHover": "#463F5C",
  "linkUnderline": "always",
  "hr": "#dddddd",
  "hrHeight": 1,
  "tableBorder": "#333333",
  "tableHeaderBackground": null,
  "tableStripeBackground": null,
  "checkboxAccent": "#333333",
  "checkboxBorder": "#555555",
  "sidebarBackground": "#ffffff",
  "sidebarForeground": "#777777",
  "sidebarActiveBackground": "#eeeeee",
  "sidebarActiveForeground": null,
  "_derived": ["background", "selectionBackground", "hr", "linkHover", "sidebarActiveBackground", "syntaxPreset"]
}
```

### whitey.json

```json
{
  "$schema": "readme-theme-v1",
  "name": "Whitey",
  "dark": false,
  "background": "#fefefe",
  "foreground": "#333333",
  "accent": "#2484c1",
  "caret": "#428bca",
  "selectionBackground": "#B5D6FC",
  "selectionForeground": null,
  "fontFamily": ["Vollkorn", "Palatino", "Times", "serif"],
  "monoFontFamily": ["Consolas", "Menlo", "Monaco", "monospace"],
  "headingFontFamily": null,
  "fontSize": 19,
  "fontWeight": 400,
  "lineHeight": 1.53,
  "contentMaxWidth": 960,
  "headingSizes": [57, 28.5, 22.23, 19, 15.77, 12.73],
  "headingWeights": [400, 400, 400, 700, 700, 700],
  "headingColors": [null, null, null, null, null, null],
  "headingItalics": [false, false, true, false, false, false],
  "headingAligns": ["center", "center", "center", "left", "left", "left"],
  "h1BorderBottom": null,
  "h1BorderWidth": 0,
  "h2BorderBottom": "#2f2f2f",
  "h2BorderWidth": 1,
  "codeInlineForeground": null,
  "codeInlineBackground": "#ffffff",
  "codeInlineBorder": null,
  "codeInlineRadius": 0,
  "codeInlineFontScale": 0.9,
  "codeBlockBackground": "#ffffff",
  "codeBlockForeground": null,
  "codeBlockBorder": "#dddddd",
  "codeBlockRadius": 0,
  "codeBlockFontScale": 0.9,
  "syntaxPreset": "highlightjs-github",
  "syntaxComment": null,
  "syntaxKeyword": null,
  "syntaxString": null,
  "syntaxNumber": null,
  "syntaxFunction": null,
  "blockquoteForeground": null,
  "blockquoteBorder": "#dddddd",
  "blockquoteBorderWidth": 1,
  "blockquoteBackground": null,
  "blockquoteItalic": false,
  "link": "#2484c1",
  "linkHover": "#2484c1",
  "linkUnderline": "hover",
  "hr": "#dddddd",
  "hrHeight": 1,
  "tableBorder": "#dddddd",
  "tableHeaderBackground": null,
  "tableStripeBackground": null,
  "checkboxAccent": "#333333",
  "checkboxBorder": null,
  "sidebarBackground": "#fefefe",
  "sidebarForeground": "#777777",
  "sidebarActiveBackground": "#eeeeee",
  "sidebarActiveForeground": null,
  "_derived": ["selectionBackground", "sidebarBackground", "sidebarForeground", "sidebarActiveBackground", "syntaxPreset", "fontFamily(serif fallback)", "headingSizes[2..6]", "headingWeights[4..6]"]
}
```

## 3. Extraction caveats (derived vs. read)

**Values inherited from the upstream base stylesheet (not present in any theme file).** The upstream editor layers each theme over an app-internal `base.user.css`. Per the official docs the base defines `--bg-color: #ffffff`, `--text-color: #333333`, `--primary-color: #428bca`, `--side-bar-bg-color: var(--bg-color)`, `--active-file-bg-color: #eee`, `--monospace: monospace`. Consequences:

- **github / pixyll**: `background` #ffffff is the base default (the theme files never set a page background).
- **Selection**: only night (`#4a89dc` + white) and newsprint (`rgba(32,43,51,0.63)` + white) set selection colors. For github, pixyll, whitey I used the upstream base default `#B5D6FC`; the docs page doesn't list this variable, so treat it as derived (it is visually correct in the shipping app, but I could not confirm it from the fetched sources).
- **Monospace stacks**: github and newsprint define *no* mono font (base default is literally `monospace`); their `monoFontFamily` arrays are sensible derived stacks. Night, pixyll, whitey stacks are verbatim. Whitey's CSS stack literally ends `..., monospace, serif` — I dropped the trailing `serif` as a CSS quirk.
- **`sidebarActiveBackground` #eeeeee** for github/pixyll/whitey is the base `--active-file-bg-color` default. Whitey styles no sidebar colors at all, so its whole sidebar block is derived via `--side-bar-bg-color: var(--bg-color)` → #fefefe.

**Caret.** No theme sets a content `caret-color`. Night's `#b8bfc6` is real but comes from its CodeMirror cursor rule (`border-left: 1px solid #b8bfc6` in `night/codeblock.dark.css`); night also ships a custom white `cursor.png`. Whitey and pixyll both color the source-mode/CodeMirror cursor `#428bca` (the source-mode CodeMirror cursor rule), which I promoted to the theme caret. github/newsprint carets are derived = text color.

**Accent.** Night's `#6dc1e7` is explicit (`--primary-color`; the file sets it twice — `#a3d5fe` then `#6dc1e7`; last wins). For the other four I used the link color as the accent; their button primary falls back upstream to base `#428bca`.

**Syntax tokens.** Only night defines code-block token colors (all verbatim from `codeblock.dark.css`; `#997` expanded to `#999977`, `#f50` would be `#ff5500` — night has no `string-2` in my object; add `"syntaxString2": "#ff5500"` if you support it). The four light themes define none → "use highlight.js github defaults" (marked derived as `syntaxPreset`). Whitey/pixyll do color *source-mode* markdown tokens (`cm-header`/`cm-property` #428bca, `cm-atom`/`cm-number` #777777) — that's the shared upstream source-mode theme, not fenced-code highlighting.

**Alpha colors flattened.** If your renderer wants opaque colors: night inline-code bg `rgba(0,0,0,0.05)` (`#0000000D`) over `#363B40` ≈ `#33383D`; newsprint selection `rgba(32,43,51,0.63)` (`#202B33A1`) over `#f3f2ee` ≈ `#6E7578`. Newsprint additionally sets a distinct selection inside code blocks: `#36284e`.

**em/rem → px conversions.** All heading sizes were converted with the theme's own base: github 16px (h1 2.25em, h2 1.75em, h3 1.5em, h4 1.25em); night 16px rem (2.5/1.63/1.17/1.12/0.97/0.93rem — decimals kept exact); newsprint 16px (1.875/1.3125/1.3125/1.125/1/1em); whitey 19px; pixyll rem root 16px.

**Pixyll is responsive** — I froze the ≥48em (desktop) breakpoint as canonical: p/li 1.25rem→20px `fontSize`, line-height 1.8, h1..h4 = 3.25/2.298/1.625/1.3rem → 52/36.77/26/20.8px. Below 48em: body 18px, h1 45.23, h2 31.98, h3 22.61, h4 20.8. At ≥64em the upstream CSS goes bigger still (h1 4.498rem→71.97px, h2 36.64, h3 30.4, h4 25.46). h5/h6 are 1.125rem→18px from the paragraph group. `body {font-size: 1.5rem}` (24px) exists but is overridden for all real content. `codeBlockFontScale` 0.8 = fence 1rem (16px) ÷ body 20px. Body weight 300 (`p {font-weight: 300}`, Merriweather Light); headings use Lato mapped to the Black (900) file under `font-weight: bold`.

**Whitey browser-default sizes.** Whitey only sets h1's size (3em→57px) and h2/h3 weights/styles; h2..h6 sizes are UA defaults scaled by the 19px base (1.5em→28.5, 1.17em→22.23, 1em→19, 0.83em→15.77, 0.67em→12.73) and h4..h6 bold is the UA default — all marked derived. Its h2 "border" is actually an `h2:after` centered 100px-wide 1px `#2f2f2f` rule, not a full-width border — reproduce as a short centered divider for authenticity. Body `line-height` is 1.4 on `body` but 1.53 on the writing area (`#write`); I used 1.53. Whitey's CSS font stack has no generic fallback (`"Vollkorn", Palatino, Times`); I appended `serif`.

**Night headings** use a separate face (`"Lucida Grande", "Corbel", sans-serif`) with negative letter-spacing (h1 −1.5px, h2/h3 −1px) and fixed rem line-heights (h1 2.75rem, h2 1.875rem, h3 1.5rem, h4 1.375rem, h5 1.25rem, h6 1rem) — worth reproducing if you add `headingLetterSpacings`/`headingLineHeights` fields later. `lineHeight` 1.625 comes from `line-height: 1.625rem` on a 16px base (it's an absolute 26px in CSS, not a multiplier — identical result at base size).

**Tables.** github is the only fully-bordered table (all borders `#dfe2e5`). night borders every cell `#474d54` with no header bg. whitey (`#dddddd`) and pixyll (`#333333`, header underline 2px) only draw horizontal row rules — no vertical borders. newsprint draws no cell borders at all (header bg `#dadada`, zebra `#e8e7e7`). `tableStripeBackground` for github applies to even rows AND thead (same `#f8f8f8` rule).

**Checkboxes.** github uses the native checkbox (accent derived from link color). night: custom 14px square, 1px `#b8bfc6` border, `#363B40` fill, `#DEDEDE` check glyph. newsprint/whitey render a `√` glyph — `#ddd` when unchecked, inheriting text color when checked (so accent = foreground). pixyll: custom 24px circle, 1px `#555` border, white fill; checked = `#333` fill with white checkmark.

**Misc.** `contentMaxWidth` is each theme's base `#write` max-width (github 860, night 914, newsprint 40em→640, pixyll 914, whitey 960); all grow at ≥1400px viewports. `linkUnderline: "hover"` for github is derived (the theme sets no link decoration; the upstream base underlines on hover). Night links are always underlined `#e0e0e0` → `#ffffff` on hover; pixyll always underlined; newsprint/whitey underline on hover only (explicit `a:hover` rules). github's h6 color `#777` and night's kbd styling (`#333` bg, white text, 3px radius) are extra authentic touches if you style `kbd`.

Sources: the five upstream theme CSS files plus their base stylesheet documentation (links removed by request; values above are the verbatim record).
