/// Unit tests for [DocumentController]: kind re-derivation, undo/redo with
/// typing coalescing, structural re-scan, splices, replaceAll and dirty
/// tracking (docs/DESIGN-editor-interaction.md §5, §2.4, §8).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/block.dart';
import 'package:readme/src/document/document_controller.dart';

/// Applies a typing edit the way the editor layer does: caret snapshots on
/// both sides and the committed character, so coalescing rules can engage.
DocEdit? type(
  DocumentController c,
  String blockId,
  String newSource, {
  required int caretBefore,
  String? committedChar,
}) {
  return c.changeBlockSource(
    blockId,
    newSource,
    caretBefore: CaretSnapshot(blockId, caretBefore),
    caretAfter: CaretSnapshot(blockId, newSource.length),
    committedChar: committedChar ?? newSource[newSource.length - 1],
  );
}

void main() {
  group('changeBlockSource kind re-derivation', () {
    test('paragraph becomes heading when "# " is prefixed', () {
      final c = DocumentController()..loadText('hello\n');
      final block = c.doc.blocks.single;
      expect(block.kind, BlockKind.paragraph);

      final edit = c.changeBlockSource(block.id, '# hello');
      expect(edit, isNotNull);
      expect(c.doc.blocks.single.kind, BlockKind.heading);
      expect(c.doc.blocks.single.source, '# hello');
      expect(c.doc.blocks.single.id, block.id, reason: 'id survives in place');
    });

    test('heading becomes paragraph when the # is deleted', () {
      final c = DocumentController()..loadText('# hello\n');
      final block = c.doc.blocks.single;
      expect(block.kind, BlockKind.heading);

      c.changeBlockSource(block.id, 'hello');
      expect(c.doc.blocks.single.kind, BlockKind.paragraph);
      expect(c.doc.blocks.single.source, 'hello');
    });

    test('a typing edit that changes the kind is recorded as autoConvert', () {
      final c = DocumentController()..loadText('hello\n');
      final id = c.doc.blocks.single.id;

      final convert = c.changeBlockSource(id, '- hello');
      expect(convert!.kind, EditKind.autoConvert);
      expect(c.doc.blocks.single.kind, BlockKind.list);

      final plain = c.changeBlockSource(id, '- hello!');
      expect(plain!.kind, EditKind.typing,
          reason: 'no kind change keeps the requested EditKind');
    });

    test('source that no longer scans as one block keeps the old kind', () {
      final c = DocumentController()..loadText('hello\n');
      final id = c.doc.blocks.single.id;
      c.changeBlockSource(id, 'hello\n\nworld');
      expect(c.doc.blocks.single.kind, BlockKind.paragraph);
      expect(c.doc.blocks.single.source, 'hello\n\nworld');
      expect(c.doc.blocks, hasLength(1),
          reason: 'changeBlockSource never splits; that is rescanBlock');
    });

    test('unchanged source is a no-op', () {
      final c = DocumentController()..loadText('hello\n');
      final id = c.doc.blocks.single.id;
      expect(c.changeBlockSource(id, 'hello'), isNull);
      expect(c.canUndo, isFalse);
      expect(c.dirty, isFalse);
    });

    test('unknown block id returns null', () {
      final c = DocumentController()..loadText('hello\n');
      expect(c.changeBlockSource('nope', 'x'), isNull);
    });
  });

  group('undo/redo', () {
    test('a single edit undoes to the exact prior source and redoes back',
        () {
      final c = DocumentController()..loadText('hello\n');
      final id = c.doc.blocks.single.id;

      c.changeBlockSource(id, 'hello world');
      expect(c.doc.blocks.single.source, 'hello world');

      final caret = c.undo();
      expect(c.doc.blocks.single.source, 'hello');
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isTrue);
      expect(caret, isNull, reason: 'no caretBefore was supplied');

      c.redo();
      expect(c.doc.blocks.single.source, 'hello world');
      expect(c.canRedo, isFalse);
    });

    test('undo/redo on empty stacks return null', () {
      final c = DocumentController()..loadText('hello\n');
      expect(c.undo(), isNull);
      expect(c.redo(), isNull);
    });

    test('two typing edits within 1s on the same block coalesce into one '
        'undo step', () {
      final c = DocumentController()..loadText('ab\n');
      final id = c.doc.blocks.single.id;

      type(c, id, 'abc', caretBefore: 2);
      type(c, id, 'abcd', caretBefore: 3);
      expect(c.doc.blocks.single.source, 'abcd');

      final caret = c.undo();
      expect(c.doc.blocks.single.source, 'ab',
          reason: 'the whole burst is one undo step');
      expect(c.canUndo, isFalse);
      expect(caret!.base, 2, reason: 'caretBefore of the first edit');

      final redoCaret = c.redo();
      expect(c.doc.blocks.single.source, 'abcd');
      expect(redoCaret!.base, 4, reason: 'caretAfter of the last edit');
    });

    test('a word-boundary committedChar flushes the group: the boundary '
        'char stays with the earlier group', () {
      final c = DocumentController()..loadText('x\n');
      final id = c.doc.blocks.single.id;

      type(c, id, 'xa', caretBefore: 1); // committedChar 'a'
      type(c, id, 'xa ', caretBefore: 2); // committedChar ' ' — coalesces
      type(c, id, 'xa b', caretBefore: 3); // prev char was ' ' — new group

      c.undo();
      expect(c.doc.blocks.single.source, 'xa ',
          reason: 'the space belongs to the earlier group');
      c.undo();
      expect(c.doc.blocks.single.source, 'x');
      expect(c.canUndo, isFalse);
    });

    test('edits more than 1s apart do not coalesce', () {
      final c = DocumentController()..loadText('ab\n');
      final id = c.doc.blocks.single.id;

      final first = type(c, id, 'abc', caretBefore: 2);
      // Age the recorded edit past the coalescing window.
      first!.at = first.at.subtract(const Duration(seconds: 2));
      type(c, id, 'abcd', caretBefore: 3);

      c.undo();
      expect(c.doc.blocks.single.source, 'abc');
      c.undo();
      expect(c.doc.blocks.single.source, 'ab');
    });

    test('sealUndoGroup breaks coalescing', () {
      final c = DocumentController()..loadText('ab\n');
      final id = c.doc.blocks.single.id;

      type(c, id, 'abc', caretBefore: 2);
      c.sealUndoGroup();
      type(c, id, 'abcd', caretBefore: 3);

      c.undo();
      expect(c.doc.blocks.single.source, 'abc');
      c.undo();
      expect(c.doc.blocks.single.source, 'ab');
    });

    test('a caret move between edits breaks coalescing', () {
      final c = DocumentController()..loadText('ab\n');
      final id = c.doc.blocks.single.id;

      type(c, id, 'abc', caretBefore: 2);
      // Caret jumped to 0 before the next insertion: no continuity.
      c.changeBlockSource(id, 'zabc',
          caretBefore: CaretSnapshot(id, 0),
          caretAfter: CaretSnapshot(id, 1),
          committedChar: 'z');

      c.undo();
      expect(c.doc.blocks.single.source, 'abc');
      c.undo();
      expect(c.doc.blocks.single.source, 'ab');
    });

    test('an autoConvert edit never coalesces with typing', () {
      final c = DocumentController()..loadText('Title\n');
      final id = c.doc.blocks.single.id;

      // Plain typing edit, caret ends at offset 6.
      type(c, id, 'Titles', caretBefore: 5);
      // Continues seamlessly at the same caret, but typing a setext
      // underline converts the block to a heading: autoConvert, never
      // merged into the typing group even with perfect caret continuity.
      final convert = type(c, id, 'Titles\n--', caretBefore: 6);
      expect(convert!.kind, EditKind.autoConvert);
      expect(c.doc.blocks.single.kind, BlockKind.heading);

      c.undo();
      expect(c.doc.blocks.single.source, 'Titles',
          reason: 'the conversion is its own atomic undo step');
      expect(c.doc.blocks.single.kind, BlockKind.paragraph);
      c.undo();
      expect(c.doc.blocks.single.source, 'Title');
    });

    test('a new edit clears the redo stack', () {
      final c = DocumentController()..loadText('a\n');
      final id = c.doc.blocks.single.id;

      c.changeBlockSource(id, 'ab');
      c.undo();
      expect(c.canRedo, isTrue);

      c.changeBlockSource(id, 'ax');
      expect(c.canRedo, isFalse);
      expect(c.redo(), isNull);
      expect(c.doc.blocks.single.source, 'ax');
    });
  });

  group('rescanBlock', () {
    test('a closed fence plus trailing text splits into two blocks, first '
        'keeps its id', () {
      final c = DocumentController()..loadText('intro\n\n```\ncode\n```\n');
      expect(c.doc.blocks, hasLength(2));
      final fence = c.doc.blocks[1];
      expect(fence.kind, BlockKind.fencedCode);

      final parts = c.rescanBlock(fence.id, '```\ncode\n```\ntail');
      expect(parts, hasLength(2));
      expect(parts![0].id, fence.id, reason: 'first part keeps the old id');
      expect(parts[0].kind, BlockKind.fencedCode);
      expect(parts[0].source, '```\ncode\n```');
      expect(parts[0].blankLinesBefore, fence.blankLinesBefore);
      expect(parts[1].kind, BlockKind.paragraph);
      expect(parts[1].source, 'tail');

      expect(c.doc.blocks, hasLength(3));
      expect(c.serialize(), 'intro\n\n```\ncode\n```\ntail\n');

      c.undo();
      expect(c.doc.blocks, hasLength(2));
      expect(c.doc.blocks[1].source, '```\ncode\n```');
      expect(c.doc.blocks[1].id, fence.id);
    });
  });

  group('spliceBlocks', () {
    test('split then merge round-trips via undo/redo', () {
      final c = DocumentController()..loadText('hello world\n');
      final original = c.doc.blocks.single;

      final left = Block(kind: BlockKind.paragraph, source: 'hello');
      final right = Block(kind: BlockKind.paragraph, source: 'world');
      c.spliceBlocks(
        index: 0,
        before: [original],
        after: [left, right],
        kind: EditKind.split,
      );
      expect(c.doc.blocks.map((b) => b.source), ['hello', 'world']);

      final merged = Block(kind: BlockKind.paragraph, source: 'helloworld');
      c.spliceBlocks(
        index: 0,
        before: [left, right],
        after: [merged],
        kind: EditKind.merge,
      );
      expect(c.doc.blocks.single.source, 'helloworld');

      c.undo(); // un-merge
      expect(c.doc.blocks.map((b) => b.id), [left.id, right.id]);
      c.undo(); // un-split
      final restored = c.doc.blocks.single;
      expect(restored.id, original.id);
      expect(restored.source, 'hello world');
      expect(c.canUndo, isFalse);

      c.redo();
      c.redo();
      expect(c.doc.blocks.single.source, 'helloworld');
    });

    test('record: false applies without an undo entry', () {
      final c = DocumentController()..loadText('a\n');
      c.spliceBlocks(
        index: 1,
        before: [],
        after: [Block(kind: BlockKind.paragraph, source: '')],
        kind: EditKind.blockOp,
        record: false,
      );
      expect(c.doc.blocks, hasLength(2));
      expect(c.canUndo, isFalse);
      expect(c.dirty, isFalse);
    });
  });

  group('replaceAll', () {
    test('replaces the whole document and restores it in one undo step', () {
      final c = DocumentController()..loadText('alpha\n\nbeta\n');
      expect(c.doc.blocks, hasLength(2));

      c.replaceAll('# fresh\n\ncontent\n');
      expect(c.doc.blocks.map((b) => b.kind),
          [BlockKind.heading, BlockKind.paragraph]);
      expect(c.serialize(), '# fresh\n\ncontent\n');

      c.undo();
      expect(c.serialize(), 'alpha\n\nbeta\n');
      expect(c.doc.blocks.map((b) => b.source), ['alpha', 'beta']);
      expect(c.canUndo, isFalse, reason: 'replaceAll is a single undo step');

      final caret = c.redo();
      expect(c.serialize(), '# fresh\n\ncontent\n');
      expect(caret!.blockId, c.doc.blocks.first.id);
      expect(caret.base, 0);
    });
  });

  group('dirty / markSaved / revision', () {
    test('dirty after edit, clean after markSaved, dirty again after undo '
        'past the save point', () {
      final c = DocumentController()..loadText('hello\n');
      expect(c.dirty, isFalse);
      final id = c.doc.blocks.single.id;

      c.changeBlockSource(id, 'hello!');
      expect(c.dirty, isTrue);

      c.markSaved();
      expect(c.dirty, isFalse);

      c.undo(); // past the save point
      expect(c.doc.blocks.single.source, 'hello');
      expect(c.dirty, isTrue);

      c.redo(); // back at the save point
      expect(c.dirty, isFalse);
    });

    test('undoing a coalesced typing burst returns to a clean document', () {
      final c = DocumentController()..loadText('ab\n');
      final id = c.doc.blocks.single.id;

      type(c, id, 'abc', caretBefore: 2);
      type(c, id, 'abcd', caretBefore: 3); // coalesces
      expect(c.dirty, isTrue);

      c.undo();
      expect(c.canUndo, isFalse);
      expect(c.doc.blocks.single.source, 'ab');
      expect(c.dirty, isFalse,
          reason: 'the buffer matches the loaded text again');
    });

    test('a save point seals the coalescing group so undo lands exactly on '
        'the saved state', () {
      final c = DocumentController()..loadText('ab\n');
      final id = c.doc.blocks.single.id;

      type(c, id, 'abc', caretBefore: 2);
      c.markSaved();
      expect(c.dirty, isFalse);

      type(c, id, 'abcd', caretBefore: 3); // must NOT merge across the save
      expect(c.dirty, isTrue);

      c.undo();
      expect(c.doc.blocks.single.source, 'abc',
          reason: 'undo stops at the saved state');
      expect(c.dirty, isFalse);
    });

    test('loadText resets history and dirty state', () {
      final c = DocumentController()..loadText('a\n');
      c.changeBlockSource(c.doc.blocks.single.id, 'ab');
      c.loadText('fresh\n');
      expect(c.dirty, isFalse);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
      expect(c.serialize(), 'fresh\n');
    });
  });

  group('never-empty invariant', () {
    test('removing the only block leaves one empty paragraph', () {
      final c = DocumentController()..loadText('only\n');
      final block = c.doc.blocks.single;

      c.spliceBlocks(
        index: 0,
        before: [block],
        after: [],
        kind: EditKind.blockOp,
      );

      expect(c.doc.blocks, hasLength(1));
      expect(c.doc.blocks.single.kind, BlockKind.paragraph);
      expect(c.doc.blocks.single.source, isEmpty);
    });

    test('an empty document loads as one empty paragraph', () {
      final c = DocumentController()..loadText('');
      expect(c.doc.blocks, hasLength(1));
      expect(c.doc.blocks.single.kind, BlockKind.paragraph);
      expect(c.doc.blocks.single.source, isEmpty);
      expect(c.serialize(), '');
    });
  });

  group('captureState/restoreState (tabs)', () {
    test('round-trips content, file binding, dirty flag and undo', () {
      final c = DocumentController()..loadText('one', path: '/tmp/a.md');
      type(c, c.doc.blocks.single.id, 'one!', caretBefore: 3);
      expect(c.dirty, isTrue);
      final tabA = c.captureState();

      c.restoreState(DocumentState.empty());
      expect(c.serialize(), '');
      expect(c.filePath, isNull);
      expect(c.dirty, isFalse);
      expect(c.canUndo, isFalse);

      c.restoreState(tabA);
      expect(c.serialize(), 'one!');
      expect(c.filePath, '/tmp/a.md');
      expect(c.dirty, isTrue);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.serialize(), 'one');
    });

    test('edits in one tab never leak into another', () {
      final c = DocumentController()..loadText('tab one');
      final tabA = c.captureState();
      c.restoreState(DocumentState.empty());
      type(c, c.doc.blocks.single.id, 'tab two text', caretBefore: 0);
      final tabB = c.captureState();

      c.restoreState(tabA);
      expect(c.serialize(), 'tab one');
      c.restoreState(tabB);
      // Fresh (empty) documents write a final newline once they have text.
      expect(c.serialize(), 'tab two text\n');
    });
  });
}
