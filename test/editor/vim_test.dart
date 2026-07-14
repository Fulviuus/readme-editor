import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/document_controller.dart';
import 'package:readme/src/editor/editor_controller.dart';
import 'package:readme/src/editor/editor_view.dart';
import 'package:readme/src/editor/vim_controller.dart';
import 'package:readme/src/theme/readme_theme.dart';

ReadmeTheme theme() => ReadmeTheme.fromJson('t', {
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
  late DocumentController docCtrl;
  late EditorController editor;

  Future<void> boot(WidgetTester tester, String text,
      {int focusBlockIndex = 0, int offset = 0}) async {
    docCtrl = DocumentController()..loadText(text);
    editor = EditorController(docCtrl, theme())..vimEnabled = true;
    addTearDown(() {
      editor.dispose();
      docCtrl.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EditorView(editor: editor)),
    ));
    await tester.pumpAndSettle();
    editor.focusBlock(docCtrl.doc.blocks[focusBlockIndex].id,
        offset: offset);
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
      {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(k);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 300));

  testWidgets('starts in normal mode; unbound keys are swallowed',
      (tester) async {
    await boot(tester, 'alpha beta');
    expect(editor.vim.mode, VimMode.normal);
    await key(tester, LogicalKeyboardKey.keyZ);
    expect(docCtrl.doc.serialize(), 'alpha beta');
    await settle(tester);
  });

  testWidgets('x deletes under the caret, with counts', (tester) async {
    await boot(tester, 'alpha beta');
    await key(tester, LogicalKeyboardKey.keyX);
    expect(editor.editing.text, 'lpha beta');
    await key(tester, LogicalKeyboardKey.digit2);
    await key(tester, LogicalKeyboardKey.keyX);
    expect(editor.editing.text, 'ha beta');
    await settle(tester);
  });

  testWidgets('i enters insert mode; Escape returns and retreats',
      (tester) async {
    await boot(tester, 'alpha', offset: 2);
    await key(tester, LogicalKeyboardKey.keyI);
    expect(editor.vim.mode, VimMode.insert);
    await key(tester, LogicalKeyboardKey.escape);
    expect(editor.vim.mode, VimMode.normal);
    expect(editor.editing.selection.baseOffset, 1);
    // The block stays focused (Escape did not blur).
    expect(editor.focusedBlockId, isNotNull);
    await settle(tester);
  });

  testWidgets('word motions and dw', (tester) async {
    await boot(tester, 'alpha beta gamma');
    await key(tester, LogicalKeyboardKey.keyW);
    expect(editor.editing.selection.baseOffset, 6);
    await key(tester, LogicalKeyboardKey.keyW);
    expect(editor.editing.selection.baseOffset, 11);
    await key(tester, LogicalKeyboardKey.keyB);
    expect(editor.editing.selection.baseOffset, 6);
    await key(tester, LogicalKeyboardKey.digit0);
    expect(editor.editing.selection.baseOffset, 0);
    await key(tester, LogicalKeyboardKey.keyD);
    await key(tester, LogicalKeyboardKey.keyW);
    expect(editor.editing.text, 'beta gamma');
    await settle(tester);
  });

  testWidgets('dd removes a single-line block; u restores it',
      (tester) async {
    await boot(tester, 'first\n\nsecond');
    expect(docCtrl.doc.blocks, hasLength(2));
    await key(tester, LogicalKeyboardKey.keyD);
    await key(tester, LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(docCtrl.doc.serialize(), 'second');
    await key(tester, LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();
    expect(docCtrl.doc.serialize(), 'first\n\nsecond');
    await settle(tester);
  });

  testWidgets('yy then p pastes the line below', (tester) async {
    await boot(tester, 'only line');
    await key(tester, LogicalKeyboardKey.keyY);
    await key(tester, LogicalKeyboardKey.keyY);
    await key(tester, LogicalKeyboardKey.keyP);
    expect(editor.editing.text, 'only line\nonly line');
    await settle(tester);
  });

  testWidgets('visual mode: v e d deletes the first word inclusively',
      (tester) async {
    await boot(tester, 'alpha beta');
    await key(tester, LogicalKeyboardKey.keyV);
    expect(editor.vim.mode, VimMode.visual);
    await key(tester, LogicalKeyboardKey.keyE);
    await key(tester, LogicalKeyboardKey.keyD);
    expect(editor.editing.text, ' beta');
    expect(editor.vim.mode, VimMode.normal);
    await settle(tester);
  });

  testWidgets('j and k cross block boundaries', (tester) async {
    await boot(tester, 'first\n\nsecond');
    final ids = [for (final b in docCtrl.doc.blocks) b.id];
    await key(tester, LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(editor.focusedBlockId, ids[1]);
    await key(tester, LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(editor.focusedBlockId, ids[0]);
    await settle(tester);
  });

  testWidgets('G and gg jump to the document ends', (tester) async {
    await boot(tester, 'first\n\nsecond\n\nthird');
    final ids = [for (final b in docCtrl.doc.blocks) b.id];
    await key(tester, LogicalKeyboardKey.keyG, shift: true);
    await tester.pumpAndSettle();
    expect(editor.focusedBlockId, ids[2]);
    await key(tester, LogicalKeyboardKey.keyG);
    await key(tester, LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(editor.focusedBlockId, ids[0]);
    await settle(tester);
  });

  testWidgets('o opens a line below and enters insert mode',
      (tester) async {
    await boot(tester, 'first\n\nsecond');
    await key(tester, LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    expect(editor.vim.mode, VimMode.insert);
    expect(docCtrl.doc.blocks, hasLength(3));
    expect(editor.focusedBlockId, docCtrl.doc.blocks[1].id);
    await settle(tester);
  });

  testWidgets('disabled bindings leave keys untouched', (tester) async {
    await boot(tester, 'alpha');
    editor.vimEnabled = false;
    await key(tester, LogicalKeyboardKey.keyX);
    expect(editor.editing.text, 'alpha');
    await settle(tester);
  });
}
