# Markdown Reference

A quick reference for the markdown readme understands.

## Headings

```
# Heading 1
## Heading 2
### Heading 3
```

Or type `#` followed by a space and the block converts live. Cmd+1…6 set the
level; Cmd+0 makes it a paragraph.

## Emphasis

| Syntax | Result | Shortcut |
| ------ | ------ | -------- |
| `**bold**` | **bold** | Cmd+B |
| `*italic*` | *italic* | Cmd+I |
| `` `code` `` | `code` | Cmd+E |
| `~~strike~~` | ~~strike~~ | Shift+Cmd+D |
| `<u>underline</u>` | underline | Cmd+U |

## Links and images

```
[link text](https://example.com)
![alt text](images/pic.png)
```

Cmd+click a rendered link to open it. Insert images from **Format → Image**.

## Lists

```
- unordered item
1. ordered item
- [ ] task to do
- [x] task done
```

Press Enter to continue a list, Enter on an empty item to leave it, and
Tab / Shift+Tab to indent and outdent.

## Blockquotes and alerts

```
> A quote.

> [!NOTE]
> A GitHub-style alert. Also TIP, IMPORTANT, WARNING, CAUTION.
```

## Code

Type ` ```lang ` and press Enter for a fenced code block with syntax
highlighting. Inline code uses backticks.

## Tables

```
| Feature | Status |
| ------- | ------ |
| Tables  | ✓      |
```

Click a cell to edit it in place; Tab moves between cells; Enter adds a row.
The source stays aligned automatically.

## Other blocks

- `---` on its own line is a horizontal rule.
- `$$ … $$` is a math block, rendered as centered display math.
- `$tex$` renders inline math, like $e^{i\pi} + 1 = 0$. Delimiters must hug
  the TeX (no space just inside), so prices like $5 stay plain text.
- `[TOC]` renders a live table of contents.
- A fenced code block with language `mermaid` renders as a diagram
  (flowcharts, sequence diagrams, and every other mermaid type).
- A `---` fenced block at the very top is YAML front matter.
