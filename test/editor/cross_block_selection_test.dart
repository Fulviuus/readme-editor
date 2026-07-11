import 'package:flutter/gestures.dart';
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
  testWidgets('mouse drag selects across blocks; copy joins their text',
      (tester) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });

    final docCtrl = DocumentController()
      ..loadText('alpha one\n\nbeta two');
    final editor = EditorController(docCtrl, theme());
    addTearDown(() {
      editor.dispose();
      docCtrl.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EditorView(editor: editor)),
    ));
    await tester.pumpAndSettle();

    RichText findBlock(String needle) => tester.widget<RichText>(
          find.byWidgetPredicate((w) =>
              w is RichText && w.text.toPlainText().contains(needle)),
        );
    expect(findBlock('alpha one'), isNotNull);
    expect(findBlock('beta two'), isNotNull);

    final start = tester.getTopLeft(find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('alpha one'))) +
        const Offset(1, 8);
    final end = tester.getBottomRight(find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('beta two'))) -
        const Offset(1, 8);

    final gesture = await tester.startGesture(start,
        kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Copy exactly the way the macOS menu bar does: dispatch the intent to
    // whatever has focus (the selection region grabs it on drag).
    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    Actions.invoke(focus!.context!, CopySelectionTextIntent.copy);
    await tester.pumpAndSettle();

    expect(clipboard, isNotEmpty);
    expect(clipboard.last, contains('alpha one'));
    expect(clipboard.last, contains('beta two'));
  });

  testWidgets('plain click still focuses the block through SelectionArea',
      (tester) async {
    final docCtrl = DocumentController()
      ..loadText('alpha one\n\nbeta two');
    final editor = EditorController(docCtrl, theme());
    addTearDown(() {
      editor.dispose();
      docCtrl.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EditorView(editor: editor)),
    ));
    await tester.pumpAndSettle();
    expect(editor.focusedBlockId, isNull);

    await tester.tapAt(tester.getCenter(find.byWidgetPredicate((w) =>
        w is RichText && w.text.toPlainText().contains('beta two'))));
    await tester.pumpAndSettle();

    expect(editor.focusedBlockId, docCtrl.doc.blocks[1].id);
    // Let the focus-triggered spell-check debounce fire before teardown.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
