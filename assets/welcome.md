# Welcome to readme

**readme** is a live markdown editor: no split preview — the document *is* the editor. Click any block to edit its markdown; click away and it renders.

## The hybrid editor

Click this paragraph and you'll see its raw markdown, with `**markers**` dimmed but visible. Try the shortcuts: **Cmd+B** for bold, *Cmd+I* for italic, `Cmd+E` for code, [Cmd+K](https://example.com) for links, and Cmd+1…6 for headings.

> Blockquotes render with a themed border. Press Enter inside one to continue it; press Enter on an empty `>` line to leave it.

### Lists just flow

- Press **Enter** at the end of an item to get the next bullet
- Press Enter on an empty item to exit the list
- Tab / Shift+Tab indent and outdent
  - nested items work too

1. Ordered lists auto-increment
2. like this

- [ ] task lists have clickable checkboxes
- [x] click one without entering edit mode

### Code, with highlighting

```dart
void main() {
  // type ```lang and press Enter to create one of these
  print('hello from readme');
}
```

### Tables

| Feature | Status |
| ------- | ------ |
| Hybrid editing | ✓ |
| Five built-in themes | ✓ |
| Tab between cells | ✓ |

---

## Themes

Open **View → Theme** and switch between the five built-in themes: GitHub, Night, Newsprint, Pixyll and Whitey. Drop your own `.json` theme in the themes folder to add more.

Everything you see is a plain `.md` file — open one with **Cmd+O**, or a whole folder with the sidebar.
