import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/document_controller.dart';
import 'package:readme/src/editor/editor_controller.dart';
import 'package:readme/src/editor/editor_view.dart';
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
  testWidgets('type, Enter, type again keeps working', (tester) async {
    final docCtrl = DocumentController()..loadText('hello');
    final editor = EditorController(docCtrl, theme());
    addTearDown(() {
      editor.dispose();
      docCtrl.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EditorView(editor: editor)),
    ));
    await tester.pumpAndSettle();

    // Focus the paragraph like a click would.
    await tester.tapAt(tester.getCenter(find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('hello'))));
    await tester.pumpAndSettle();
    expect(editor.focusedBlockId, isNotNull);

    // Type at the end.
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'hello XYZ',
      selection: TextSelection.collapsed(offset: 9),
    ));
    await tester.pump();
    expect(docCtrl.doc.blocks.first.source, 'hello XYZ');

    // Real Enter key through the Focus chain (splits the paragraph).
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(docCtrl.doc.blocks, hasLength(2),
        reason: 'Enter should split into a new block');
    expect(editor.focusedBlockId, docCtrl.doc.blocks[1].id);
    expect(editor.focusNode.hasFocus, isTrue,
        reason: 'the editing field must keep keyboard focus after Enter');

    // Keep typing in the new block.
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'ABC',
      selection: TextSelection.collapsed(offset: 3),
    ));
    await tester.pump();
    expect(docCtrl.doc.blocks[1].source, 'ABC');

    // Flush the spell-check debounce before teardown.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
