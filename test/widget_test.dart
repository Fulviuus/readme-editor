// Smoke test: the editor surface renders a loaded document without throwing.
// (Replaces the Flutter template counter test, which referenced the old
// scaffold MyApp removed when the real app entry landed.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readme/src/document/document_controller.dart';
import 'package:readme/src/editor/editor_controller.dart';
import 'package:readme/src/editor/editor_view.dart';
import 'package:readme/src/theme/readme_theme.dart';

void main() {
  testWidgets('EditorView renders a loaded document', (tester) async {
    final docCtrl = DocumentController()
      ..loadText('# Hello\n\nSome **bold** text.');
    final editor = EditorController(
      docCtrl,
      ReadmeTheme.fromJson('test', const {}),
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EditorView(editor: editor))),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(EditorView), findsOneWidget);
    expect(find.textContaining('Hello', findRichText: true), findsWidgets);
  });
}
