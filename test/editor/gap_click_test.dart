import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/block.dart';
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
  testWidgets('clicking the gap between two blocks opens a new line there',
      (tester) async {
    final docCtrl = DocumentController()..loadText('alpha one\n\nbeta two');
    final editor = EditorController(docCtrl, theme());
    addTearDown(() {
      editor.dispose();
      docCtrl.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EditorView(editor: editor)),
    ));
    await tester.pumpAndSettle();

    Finder blockText(String needle) => find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(needle));
    final bottomOfFirst = tester.getBottomLeft(blockText('alpha one'));
    final topOfSecond = tester.getTopLeft(blockText('beta two'));
    // Midpoint of the visual gap, horizontally over the text column.
    final gap = Offset(
      bottomOfFirst.dx + 40,
      (bottomOfFirst.dy + topOfSecond.dy) / 2,
    );

    await tester.tapAt(gap);
    await tester.pumpAndSettle();

    expect(docCtrl.doc.blocks, hasLength(3));
    final middle = docCtrl.doc.blocks[1];
    expect(middle.kind, BlockKind.paragraph);
    expect(middle.source, isEmpty);
    expect(editor.focusedBlockId, middle.id);

    // Clicking away again abandons it without a trace.
    await tester.tapAt(tester.getCenter(blockText('alpha one')));
    await tester.pumpAndSettle();
    expect(docCtrl.doc.blocks, hasLength(2));
    expect(docCtrl.dirty, isFalse);

    // Let the focus-triggered spell-check debounce fire before teardown.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
