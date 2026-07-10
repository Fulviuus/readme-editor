import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/block.dart';
import 'package:readme/src/document/document_controller.dart';
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
