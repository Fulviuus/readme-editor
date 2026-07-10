import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/block.dart';
import 'package:readme/src/document/document_controller.dart';
import 'package:readme/src/editor/blocks/table_model.dart';
import 'package:readme/src/editor/editor_controller.dart';
import 'package:readme/src/theme/readme_theme.dart';

ReadmeTheme testTheme() => ReadmeTheme.fromJson('test', {
      'name': 'Test',
      'foreground': '#333333',
      'background': '#ffffff',
      'accent': '#4183C4',
      'blockquoteBorder': '#dfe2e5',
      'link': '#4183C4',
      'linkHover': '#4183C4',
      'hr': '#e7e7e7',
      'checkboxAccent': '#4183C4',
      'sidebarBackground': '#fafafa',
      'sidebarForeground': '#777777',
      'sidebarActiveBackground': '#eeeeee',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DocumentController doc;
  late EditorController editor;

  setUp(() {
    doc = DocumentController();
    editor = EditorController(doc, testTheme());
  });

  tearDown(() => editor.dispose());

  /// Simulates the TextField reporting a new value (typing/paste).
  void type(String text, int caret) {
    editor.editing.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: caret));
  }

  group('typing pipeline', () {
    test('typing updates the focused block source', () {
      doc.loadText('hello');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 5);
      type('hello!', 6);
      expect(doc.doc.blocks.first.source, 'hello!');
      expect(doc.dirty, isTrue);
    });

    test('typing "# " converts paragraph to heading live', () {
      doc.loadText('title');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 0);
      type('# title', 2);
      expect(doc.doc.blocks.first.kind, BlockKind.heading);
      expect(doc.doc.blocks.first.headingLevel, 1);
    });

    test('deleting the marker converts heading back to paragraph', () {
      doc.loadText('# title');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 2);
      type('title', 0);
      expect(doc.doc.blocks.first.kind, BlockKind.paragraph);
    });

    test('pasting multi-block content splits the block', () {
      doc.loadText('start');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 5);
      type('start\n\n# Next', 13);
      expect(doc.doc.blocks, hasLength(2));
      expect(doc.doc.blocks[0].source, 'start');
      expect(doc.doc.blocks[1].kind, BlockKind.heading);
      // First part keeps the id.
      expect(doc.doc.blocks[0].id, id);
    });
  });

  group('Enter', () {
    test('splits a paragraph at the caret', () {
      doc.loadText('abcdef');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 3);
      editor.handleEnter();
      expect(doc.doc.blocks.map((b) => b.source), ['abc', 'def']);
      expect(editor.focusedBlockId, doc.doc.blocks[1].id);
      expect(editor.editing.selection.baseOffset, 0);
    });

    test('at end of heading creates a paragraph below', () {
      doc.loadText('# Title');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 7);
      editor.handleEnter();
      expect(doc.doc.blocks, hasLength(2));
      expect(doc.doc.blocks[1].kind, BlockKind.paragraph);
      expect(doc.doc.blocks[1].source, '');
    });

    test('mid-heading split demotes the tail to paragraph', () {
      doc.loadText('# Title');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 4);
      editor.handleEnter();
      expect(doc.doc.blocks[0].source, '# Ti');
      expect(doc.doc.blocks[0].kind, BlockKind.heading);
      expect(doc.doc.blocks[1].source, 'tle');
      expect(doc.doc.blocks[1].kind, BlockKind.paragraph);
    });

    test('continues a list with the next marker', () {
      doc.loadText('- one');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 5);
      editor.handleEnter();
      expect(doc.doc.blocks.single.source, '- one\n- ');
      expect(editor.editing.selection.baseOffset, 8);
    });

    test('ordered list increments the number', () {
      doc.loadText('3. three');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 8);
      editor.handleEnter();
      expect(doc.doc.blocks.single.source, '3. three\n4. ');
    });

    test('task list continues with an unchecked box', () {
      doc.loadText('- [x] done');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 10);
      editor.handleEnter();
      expect(doc.doc.blocks.single.source, '- [x] done\n- [ ] ');
    });

    test('empty item exits the list into a paragraph', () {
      doc.loadText('- one\n- ');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 8);
      editor.handleEnter();
      expect(doc.doc.blocks, hasLength(2));
      expect(doc.doc.blocks[0].source, '- one');
      expect(doc.doc.blocks[1].source, '');
      expect(editor.focusedBlockId, doc.doc.blocks[1].id);
    });

    test('``` line converts to a fenced code block', () {
      doc.loadText('```dart');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 7);
      editor.handleEnter();
      final b = doc.doc.blocks.single;
      expect(b.kind, BlockKind.fencedCode);
      expect(b.source, '```dart\n\n```');
      expect(editor.editing.selection.baseOffset, 8);
    });

    test('--- line converts to a thematic break plus fresh paragraph', () {
      doc.loadText('---x');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 4);
      type('---', 3); // fix the source to be exactly ---
      editor.handleEnter();
      expect(doc.doc.blocks[0].kind, BlockKind.thematicBreak);
      expect(doc.doc.blocks[1].kind, BlockKind.paragraph);
      expect(editor.focusedBlockId, doc.doc.blocks[1].id);
    });

    test('Enter after a closed fence exits the block', () {
      doc.loadText('```\ncode\n```');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 12);
      editor.handleEnter();
      expect(doc.doc.blocks, hasLength(2));
      expect(doc.doc.blocks[1].kind, BlockKind.paragraph);
    });

    test('Enter inside a fence inserts a newline, not a split', () {
      doc.loadText('```\ncode\n```');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 8); // after 'code'
      editor.handleEnter();
      expect(doc.doc.blocks, hasLength(1));
      expect(doc.doc.blocks.single.source, '```\ncode\n\n```');
    });

    test('Shift+Enter inserts a soft break', () {
      doc.loadText('ab');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 1);
      editor.handleEnter(shift: true);
      expect(doc.doc.blocks.single.source, 'a\nb');
    });
  });

  group('Backspace at start', () {
    test('demotes a heading to paragraph first', () {
      doc.loadText('# Title');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 0);
      expect(editor.handleBackspaceAtStart(), isTrue);
      expect(doc.doc.blocks.single.source, 'Title');
      expect(doc.doc.blocks.single.kind, BlockKind.paragraph);
    });

    test('strips quote markers', () {
      doc.loadText('> a\n> b');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 0);
      editor.handleBackspaceAtStart();
      expect(doc.doc.blocks.single.source, 'a\nb');
    });

    test('merges paragraph into previous paragraph', () {
      doc.loadText('one\n\ntwo');
      editor.focusBlock(doc.doc.blocks[1].id, offset: 0);
      editor.handleBackspaceAtStart();
      expect(doc.doc.blocks.single.source, 'onetwo');
      expect(editor.editing.selection.baseOffset, 3);
    });

    test('backspace into an HR deletes the HR', () {
      doc.loadText('a\n\n---\n\nb');
      editor.focusBlock(doc.doc.blocks[2].id, offset: 0);
      editor.handleBackspaceAtStart();
      expect(doc.doc.blocks.map((b) => b.source), ['a', 'b']);
    });

    test('empty paragraph after code block is deleted, focus moves up', () {
      doc.loadText('```\nx\n```\n\n');
      doc.spliceBlocks(
          index: 1,
          before: [],
          after: [Block(kind: BlockKind.paragraph, source: '')],
          kind: EditKind.blockOp);
      editor.focusBlock(doc.doc.blocks[1].id, offset: 0);
      editor.handleBackspaceAtStart();
      expect(doc.doc.blocks, hasLength(1));
      expect(editor.focusedBlockId, doc.doc.blocks.single.id);
    });
  });

  group('formatting', () {
    test('toggleBold wraps the word at a collapsed caret', () {
      doc.loadText('hello world');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 2);
      editor.toggleBold();
      expect(doc.doc.blocks.single.source, '**hello** world');
    });

    test('toggleBold unwraps existing markers', () {
      doc.loadText('**hello** world');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.editing.selection =
          const TextSelection(baseOffset: 2, extentOffset: 7);
      editor.toggleBold();
      expect(doc.doc.blocks.single.source, 'hello world');
    });

    test('toggleBold with empty caret inserts a pair and stays inside', () {
      doc.loadText('a ');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 2);
      editor.toggleBold();
      expect(doc.doc.blocks.single.source, 'a ****');
      expect(editor.editing.selection.baseOffset, 4);
    });

    test('setHeadingLevel toggles and switches levels', () {
      doc.loadText('text');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 0);
      editor.setHeadingLevel(2);
      expect(doc.doc.blocks.single.source, '## text');
      editor.setHeadingLevel(3);
      expect(doc.doc.blocks.single.source, '### text');
      editor.setHeadingLevel(3);
      expect(doc.doc.blocks.single.source, 'text');
    });

    test('insertLink wraps selected text', () {
      doc.loadText('visit here now');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.editing.selection =
          const TextSelection(baseOffset: 6, extentOffset: 10);
      editor.insertLink();
      expect(doc.doc.blocks.single.source, 'visit [here]() now');
    });
  });

  group('undo/redo through the editor', () {
    test('undo restores text and caret; redo reapplies', () {
      doc.loadText('abc');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 3);
      type('abcd', 4);
      editor.undo();
      expect(doc.doc.blocks.single.source, 'abc');
      expect(editor.editing.text, 'abc');
      editor.redo();
      expect(doc.doc.blocks.single.source, 'abcd');
      expect(editor.editing.text, 'abcd');
    });

    test('undo of a split restores one block', () {
      doc.loadText('abcdef');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 3);
      editor.handleEnter();
      expect(doc.doc.blocks, hasLength(2));
      editor.undo();
      expect(doc.doc.blocks, hasLength(1));
      expect(doc.doc.blocks.single.source, 'abcdef');
    });
  });

  group('task toggling on rendered blocks', () {
    test('toggleTask flips the checkbox', () {
      doc.loadText('- [ ] a\n- [x] b');
      final id = doc.doc.blocks.first.id;
      editor.toggleTask(id, 0);
      expect(doc.doc.blocks.single.source, '- [x] a\n- [x] b');
      editor.toggleTask(id, 1);
      expect(doc.doc.blocks.single.source, '- [x] a\n- [ ] b');
    });
  });

  group('review regressions', () {
    test('backspace at 0 of a NON-empty math block does not erase it', () {
      doc.loadText('\$\$\nE = mc^2\n\$\$');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 0);
      editor.handleBackspaceAtStart();
      // Content preserved; focus just stays/moves — never a wipe.
      expect(doc.doc.blocks.first.source, contains('E = mc^2'));
    });

    test('backspace at 0 of an EMPTY math block demotes it to paragraph', () {
      doc.loadText('\$\$\n\n\$\$');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 0);
      editor.handleBackspaceAtStart();
      expect(doc.doc.blocks.single.kind, BlockKind.paragraph);
      expect(doc.doc.blocks.single.source, '');
    });

    test('Enter in a table with a selected cell moves rows, not deletes', () {
      doc.loadText('| a | b |\n|---|---|\n| x | y |');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 2);
      editor.handleTab(); // selects 'b'
      editor.handleEnter(); // move down — 'b' must survive
      expect(doc.doc.blocks.single.source, contains('b'));
      expect(doc.doc.blocks.single.source, contains('| a | b |'));
    });

    test('backspace at 0 of a table never merges into the previous block',
        () {
      doc.loadText('hello\n\n| a | b |\n|---|---|\n| 1 | 2 |');
      final table = doc.doc.blocks[1];
      editor.focusBlock(table.id, offset: 0);
      editor.handleBackspaceAtStart();
      expect(doc.doc.blocks, hasLength(2));
      expect(doc.doc.blocks[1].kind, BlockKind.table);
      // Focus moved up instead.
      expect(editor.focusedBlockId, doc.doc.blocks[0].id);
    });

    test('backspace at 0 of a non-empty code block never merges', () {
      doc.loadText('hello\n\n```dart\nbody\n```');
      editor.focusBlock(doc.doc.blocks[1].id, offset: 0);
      editor.handleBackspaceAtStart();
      expect(doc.doc.blocks, hasLength(2));
      expect(doc.doc.blocks[1].kind, BlockKind.fencedCode);
    });

    test('forward-delete before a code block does not glue it into prose',
        () {
      doc.loadText('abc\n\n```dart\nbody\n```');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 3);
      editor.handleDeleteAtEnd();
      expect(doc.doc.blocks, hasLength(2));
      expect(doc.doc.blocks[1].kind, BlockKind.fencedCode);
      expect(doc.doc.blocks[0].source, 'abc');
    });

    test('forward-delete before an HR removes the HR', () {
      doc.loadText('abc\n\n---\n\ndef');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 3);
      editor.handleDeleteAtEnd();
      expect(doc.doc.blocks.map((b) => b.source), ['abc', 'def']);
    });

    test('forward-delete pulls a list first item text up, keeps the rest',
        () {
      doc.loadText('abc\n\n- one\n- two');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 3);
      editor.handleDeleteAtEnd();
      expect(doc.doc.blocks[0].source, 'abcone');
      expect(doc.doc.blocks[1].source, '- two');
    });

    test('emptying a block always resets its kind to paragraph', () {
      doc.loadText('\$\$\nx\n\$\$');
      final id = doc.doc.blocks.first.id;
      doc.changeBlockSource(id, '');
      expect(doc.doc.blocks.single.kind, BlockKind.paragraph);
    });

    test('undo after Enter on the ephemeral tail does not corrupt the list',
        () {
      doc.loadText('```\nx\n```');
      editor.focusTail(); // appends the ephemeral empty paragraph
      expect(doc.doc.blocks, hasLength(2));
      editor.handleEnter(); // records a splice involving the (ex-)ephemeral
      final countAfterEnter = doc.doc.blocks.length;
      editor.focusBlock(doc.doc.blocks.first.id); // focus away
      editor.undo(); // must not throw or corrupt
      expect(doc.doc.blocks.length, lessThanOrEqualTo(countAfterEnter));
      editor.undo();
      expect(doc.doc.blocks.first.kind, BlockKind.fencedCode);
    });

    test('deletion that creates a blank line splits the block', () {
      doc.loadText('a\n x\nb');
      final id = doc.doc.blocks.single.id;
      editor.focusBlock(id, offset: 0);
      editor.editing.value = const TextEditingValue(
          text: 'a\n\nb', selection: TextSelection.collapsed(offset: 2));
      expect(doc.doc.blocks, hasLength(2));
    });

    test('undo of replaceAll restores trailing-newline facts', () {
      doc.loadText('one');
      doc.doc.hadFinalNewline = false;
      doc.replaceAll('two\n');
      expect(doc.doc.hadFinalNewline, isTrue);
      doc.undo();
      expect(doc.doc.hadFinalNewline, isFalse);
      expect(doc.serialize(), 'one');
    });

    test('tokenizer survives a bare scheme with no host', () {
      doc.loadText('see http://');
      final id = doc.doc.blocks.single.id;
      editor.focusBlock(id, offset: 0);
      // Building the editing span exercises the tokenizer.
      expect(
          () => editor.renderer
              .buildEditingSpan('see http:// and https://', BlockKind.paragraph),
          returnsNormally);
    });
  });

  group('paragraph commands', () {
    test('increase/decrease heading level walks the ladder', () {
      doc.loadText('text');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 0);
      editor.increaseHeadingLevel(); // paragraph -> H6
      expect(doc.doc.blocks.single.source, '###### text');
      editor.increaseHeadingLevel();
      expect(doc.doc.blocks.single.source, '##### text');
      editor.decreaseHeadingLevel();
      expect(doc.doc.blocks.single.source, '###### text');
      editor.decreaseHeadingLevel(); // H6 -> paragraph
      expect(doc.doc.blocks.single.source, 'text');
    });

    test('quote conversion toggles', () {
      doc.loadText('a\nb');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.convertToQuote();
      expect(doc.doc.blocks.single.source, '> a\n> b');
      expect(doc.doc.blocks.single.kind, BlockKind.blockquote);
      editor.convertToQuote();
      expect(doc.doc.blocks.single.source, 'a\nb');
    });

    test('list conversions strip and re-mark lines', () {
      doc.loadText('a\nb');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id);
      editor.convertToUnorderedList();
      expect(doc.doc.blocks.single.source, '- a\n- b');
      editor.focusBlock(id);
      editor.convertToOrderedList();
      expect(doc.doc.blocks.single.source, '1. a\n2. b');
      editor.focusBlock(id);
      editor.convertToTaskList();
      expect(doc.doc.blocks.single.source, '- [ ] a\n- [ ] b');
      editor.focusBlock(id);
      editor.convertToTaskList(); // toggle off
      expect(doc.doc.blocks.single.source, 'a\nb');
    });

    test('code fence toggles around the block', () {
      doc.loadText('print(1)');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id);
      editor.convertToCodeFence();
      expect(doc.doc.blocks.single.source, '```\nprint(1)\n```');
      expect(doc.doc.blocks.single.kind, BlockKind.fencedCode);
      editor.focusBlock(id);
      editor.convertToCodeFence();
      expect(doc.doc.blocks.single.source, 'print(1)');
    });

    test('insert paragraph before/after an opaque block', () {
      doc.loadText('```\nx\n```');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id);
      editor.insertParagraphAfter();
      expect(doc.doc.blocks, hasLength(2));
      expect(editor.focusedBlockId, doc.doc.blocks[1].id);
      editor.focusBlock(id);
      editor.insertParagraphBefore();
      expect(doc.doc.blocks, hasLength(3));
      expect(doc.doc.blocks[0].kind, BlockKind.paragraph);
      expect(doc.doc.blocks[1].id, id);
    });

    test('insertTable converts an empty paragraph', () {
      doc.loadText('');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.insertTable(2, 3);
      final b = doc.doc.blocks.single;
      expect(b.kind, BlockKind.table);
      expect(b.source.split('\n'), hasLength(4)); // header + delim + 2 rows
    });

    test('front matter inserts once at the top', () {
      doc.loadText('# Title');
      editor.insertFrontMatter();
      expect(doc.doc.blocks.first.kind, BlockKind.frontMatter);
      final count = doc.doc.blocks.length;
      editor.insertFrontMatter(); // second call focuses, no duplicate
      expect(doc.doc.blocks.length, count);
    });

    test('task status set/toggle at caret line', () {
      doc.loadText('- [ ] a\n- [x] b');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 3);
      editor.setTaskStatusAtCaret(checked: true);
      expect(doc.doc.blocks.single.source, '- [x] a\n- [x] b');
      editor.setTaskStatusAtCaret();
      expect(doc.doc.blocks.single.source, '- [ ] a\n- [x] b');
    });

    test('moveRow swaps list lines and whole blocks', () {
      doc.loadText('- one\n- two');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 2); // in 'one'
      editor.moveRow(up: false);
      expect(doc.doc.blocks.single.source, '- two\n- one');

      doc.loadText('first\n\nsecond');
      editor.focusBlock(doc.doc.blocks[1].id, offset: 0);
      editor.moveRow(up: true);
      expect(doc.doc.blocks.map((b) => b.source), ['second', 'first']);
    });

    test('moveRow in a table never crosses the delimiter', () {
      doc.loadText('| h |\n|---|\n| a |\n| b |');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 16); // row 'a'
      editor.moveRow(up: true); // would hit delimiter — must be a no-op
      expect(doc.doc.blocks.single.source, '| h |\n|---|\n| a |\n| b |');
      editor.moveRow(up: false);
      expect(doc.doc.blocks.single.source, '| h |\n|---|\n| b |\n| a |');
    });
  });

  group('format commands', () {
    test('clearFormat strips inline syntax from the selection', () {
      doc.loadText(r'keep **bold** `code` [label](https://x.dev) end');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.editing.selection = TextSelection(
          baseOffset: 0, extentOffset: editor.editing.text.length);
      editor.clearFormat();
      expect(doc.doc.blocks.single.source, 'keep bold code label end');
    });

    test('clearFormat with collapsed caret cleans the whole block', () {
      doc.loadText('a *b* c');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 0);
      editor.clearFormat();
      expect(doc.doc.blocks.single.source, 'a b c');
    });

    test('toggleUnderline wraps and unwraps', () {
      doc.loadText('hello world');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.editing.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);
      editor.toggleUnderline();
      expect(doc.doc.blocks.single.source, '<u>hello</u> world');
      // Selection now covers 'hello' inside the tags; toggle removes them.
      editor.toggleUnderline();
      expect(doc.doc.blocks.single.source, 'hello world');
    });

    test('underline renders content between hidden tags', () {
      final r = editor.renderer.renderInline('<u>under</u> plain',
          baseStyle: editor.theme.bodyStyle);
      expect(r.renderedText, 'under plain');
      final underlined = <String>[];
      r.span.visitChildren((s) {
        if (s is TextSpan &&
            s.style?.decoration == TextDecoration.underline) {
          underlined.add(s.text ?? '');
        }
        return true;
      });
      expect(underlined.join(), 'under');
    });

    test('convertToAlert wraps the block and replaces existing tags', () {
      doc.loadText('watch out');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id);
      editor.convertToAlert('WARNING');
      expect(doc.doc.blocks.single.source, '> [!WARNING]\n> watch out');
      editor.focusBlock(id);
      editor.convertToAlert('TIP');
      expect(doc.doc.blocks.single.source, '> [!TIP]\n> watch out');
    });
  });

  group('selection and delete-range commands', () {
    test('selectLine and selectBlock', () {
      doc.loadText('one two\nthree');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 4);
      editor.selectLine();
      var sel = editor.editing.selection;
      expect(editor.editing.text.substring(sel.start, sel.end), 'one two');
      editor.selectBlock();
      sel = editor.editing.selection;
      expect(editor.editing.text.substring(sel.start, sel.end), 'one two\nthree');
    });

    test('selectStyledScope grabs the emphasis under the caret', () {
      doc.loadText('a **strong** b');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 5); // inside strong
      editor.selectStyledScope();
      final sel = editor.editing.selection;
      expect(editor.editing.text.substring(sel.start, sel.end), '**strong**');
    });

    test('deleteWord and deleteLine', () {
      doc.loadText('alpha beta gamma');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 7); // in 'beta'
      editor.deleteWord();
      expect(doc.doc.blocks.single.source, 'alpha  gamma');

      doc.loadText('l1\nl2\nl3');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 4); // in 'l2'
      editor.deleteLine();
      expect(doc.doc.blocks.single.source, 'l1\nl3');
    });

    test('deleteBlock removes the whole block', () {
      doc.loadText('a\n\nb\n\nc');
      editor.focusBlock(doc.doc.blocks[1].id, offset: 0);
      editor.deleteBlock();
      expect(doc.doc.blocks.map((b) => b.source), ['a', 'c']);
    });

    test('jumpToTop / jumpToBottom move focus across blocks', () {
      doc.loadText('first\n\nmid\n\nlast');
      editor.focusBlock(doc.doc.blocks[1].id);
      editor.jumpToTop();
      expect(editor.focusedBlockId, doc.doc.blocks.first.id);
      editor.jumpToBottom();
      expect(editor.focusedBlockId, doc.doc.blocks.last.id);
    });
  });

  group('comment and code tools', () {
    test('toggleComment wraps and unwraps a selection', () {
      doc.loadText('secret note');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.editing.selection =
          const TextSelection(baseOffset: 0, extentOffset: 6);
      editor.toggleComment();
      expect(doc.doc.blocks.single.source, '<!-- secret --> note');
      editor.editing.selection = TextSelection(
          baseOffset: 0, extentOffset: '<!-- secret -->'.length);
      editor.toggleComment();
      expect(doc.doc.blocks.single.source, 'secret note');
    });

    test('comment content is hidden in rendered output', () {
      final r = editor.renderer.renderInline('a <!-- hidden --> b',
          baseStyle: editor.theme.bodyStyle);
      expect(r.renderedText, 'a  b');
    });

    test('copyCodeContent needs a code block; autoIndent reindents braces',
        () {
      doc.loadText('```js\nfunction f() {\nreturn 1;\n}\n```');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 6);
      editor.autoIndentCode();
      expect(doc.doc.blocks.single.source,
          '```js\nfunction f() {\n  return 1;\n}\n```');
    });
  });

  group('link actions (issue #38)', () {
    test('linkUrlAtCaret finds the link under the caret', () {
      doc.loadText('see [docs](https://x.dev) and https://a.b end');
      final id = doc.doc.blocks.first.id;
      editor.focusBlock(id, offset: 7); // inside [docs]
      expect(editor.linkUrlAtCaret(), 'https://x.dev');
      editor.focusBlock(id, offset: 33); // inside the bare autolink
      expect(editor.linkUrlAtCaret(), 'https://a.b');
      editor.focusBlock(id, offset: 0); // plain text
      expect(editor.linkUrlAtCaret(), isNull);
    });

    test('openLink dispatches to the installed opener', () {
      final opened = <String>[];
      editor.linkOpener = opened.add;
      editor.openLink('https://x.dev');
      doc.loadText('[a](https://caret.dev)');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 2);
      editor.openLinkAtCaret();
      expect(opened, ['https://x.dev', 'https://caret.dev']);
    });
  });

  group('in-place table cells', () {
    test('updateActiveTableCell rewrites the cell and prettifies', () {
      doc.loadText('| a | b |\n|---|---|\n| c | d |');
      final id = doc.doc.blocks.first.id;
      editor.focusTableCell(id, 2, 0); // 'c'
      editor.updateActiveTableCell('changed', 7);
      final lines = doc.doc.blocks.single.source.split('\n');
      expect(lines[2], '| changed | d    |');
      expect(lines[0], '| a       | b    |'); // whole table re-padded
      expect(lines[1], '| ------- | ---- |');
      // Caret sits at the end of the new cell text.
      final (a, _) = TableShape(doc.doc.blocks.single.source).rangeOf(2, 0);
      expect(editor.editing.selection.baseOffset, a + 7);
    });

    test('focusTableCell selects the target cell content', () {
      doc.loadText('| a | bb |\n|---|---|\n| c | d |');
      final id = doc.doc.blocks.first.id;
      editor.focusTableCell(id, 0, 1);
      final sel = editor.editing.selection;
      expect(editor.editing.text.substring(sel.start, sel.end), 'bb');
      expect(editor.activeTableCell(), (0, 1));
    });

    test('vertical cell movement skips the delimiter and leaves at edges',
        () {
      doc.loadText('para\n\n| a | b |\n|---|---|\n| c | d |');
      final table = doc.doc.blocks[1];
      editor.focusTableCell(table.id, 0, 0);
      editor.moveTableCellVertically(up: false); // header -> first data row
      expect(editor.activeTableCell(), (2, 0));
      editor.moveTableCellVertically(up: true); // back up to the header
      expect(editor.activeTableCell(), (0, 0));
      editor.moveTableCellVertically(up: true); // leaves the table
      expect(editor.focusedBlockId, doc.doc.blocks[0].id);
    });

    test('blurring a table prettifies its source', () {
      doc.loadText('|a|b|\n|---|---|\n|c|d|\n\nafter');
      final table = doc.doc.blocks[0];
      editor.focusTableCell(table.id, 0, 0);
      editor.focusBlock(doc.doc.blocks[1].id);
      expect(doc.doc.blocks[0].source,
          '| a    | b    |\n| ---- | ---- |\n| c    | d    |');
    });

    test('insertTable produces prettified source', () {
      doc.loadText('');
      editor.focusBlock(doc.doc.blocks.first.id);
      editor.insertTable(1, 2);
      expect(doc.doc.blocks.single.source,
          '|      |      |\n| ---- | ---- |\n|      |      |');
    });
  });

  group('table row/column operations', () {
    const base = '| a    | b    |\n| ---- | ---- |\n| c    | d    |';

    test('add row below and above', () {
      doc.loadText(base);
      final id = doc.doc.blocks.first.id;
      editor.focusTableCell(id, 2, 0);
      editor.addTableRowBelow();
      expect(doc.doc.blocks.single.source.split('\n'), hasLength(4));
      expect(editor.activeTableCell(), (3, 0));
      editor.addTableRowAbove();
      expect(doc.doc.blocks.single.source.split('\n'), hasLength(5));
    });

    test('add and delete column', () {
      doc.loadText(base);
      final id = doc.doc.blocks.first.id;
      editor.focusTableCell(id, 0, 0);
      editor.addTableColumnAfter();
      expect(doc.doc.blocks.single.source.split('\n')[0],
          '| a    |      | b    |');
      expect(editor.activeTableCell(), (0, 1));
      editor.deleteTableColumn();
      expect(doc.doc.blocks.single.source.split('\n')[0], '| a    | b    |');
    });

    test('move column right swaps content and alignment', () {
      doc.loadText('| a | b |\n|:-:|---|\n| c | d |');
      final id = doc.doc.blocks.first.id;
      editor.focusTableCell(id, 0, 0);
      editor.moveTableColumnRight();
      final lines = doc.doc.blocks.single.source.split('\n');
      expect(lines[0], '| b    | a    |');
      expect(lines[1], '| ---- | :--: |');
      expect(lines[2], '| d    | c    |');
      expect(editor.activeTableCell(), (0, 1));
    });

    test('delete row keeps the header pinned', () {
      doc.loadText(base);
      final id = doc.doc.blocks.first.id;
      editor.focusTableCell(id, 0, 0); // header
      editor.deleteTableRow(); // must not delete the header
      expect(doc.doc.blocks.single.source.split('\n'), hasLength(3));
      editor.focusTableCell(id, 2, 0);
      editor.deleteTableRow();
      expect(doc.doc.blocks.single.source.split('\n'), hasLength(2));
    });

    test('delete table removes the block and refocuses', () {
      doc.loadText('before\n\n$base');
      final table = doc.doc.blocks[1];
      editor.focusTableCell(table.id, 2, 1);
      editor.deleteTable();
      expect(doc.doc.blocks.map((b) => b.kind),
          isNot(contains(BlockKind.table)));
      expect(editor.focusedBlockId, doc.doc.blocks.first.id);
    });

    test('deleting the last column deletes the table', () {
      doc.loadText('| a |\n|---|\n| b |');
      final id = doc.doc.blocks.first.id;
      editor.focusTableCell(id, 0, 0);
      editor.deleteTableColumn();
      expect(doc.doc.blocks.single.kind, BlockKind.paragraph);
    });
  });

  group('tables', () {
    test('Tab selects the next cell content', () {
      doc.loadText('| a | b |\n|---|---|\n| c | d |');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 2);
      editor.handleTab();
      // Should select 'b' in the header row.
      final sel = editor.editing.selection;
      expect(editor.editing.text.substring(sel.start, sel.end), 'b');
    });

    test('Tab from the last cell appends a row', () {
      doc.loadText('| a | b |\n|---|---|\n| c | d |');
      editor.focusBlock(doc.doc.blocks.first.id, offset: 26); // inside 'd'
      editor.handleTab();
      expect(doc.doc.blocks.single.source.split('\n'), hasLength(4));
    });
  });
}
