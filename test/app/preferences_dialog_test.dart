import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:readme/src/app/preferences_dialog.dart';
import 'package:readme/src/app/settings_controller.dart';
import 'package:readme/src/document/document_controller.dart';
import 'package:readme/src/editor/editor_controller.dart';
import 'package:readme/src/theme/theme_manager.dart';
import 'package:readme/src/workspace/workspace_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  late final ThemeManager tm;
  setUpAll(() async {
    tm = ThemeManager();
    await tm.init();
  });

  testWidgets('preferences pages carry the full option set', (tester) async {
    final doc = DocumentController()..loadText('');
    final editor = EditorController(doc, tm.current);
    final workspace = WorkspaceController(doc);
    final settings = SettingsController();
    addTearDown(() {
      editor.dispose();
      workspace.dispose();
      doc.dispose();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeManager>.value(value: tm),
        ChangeNotifierProvider<DocumentController>.value(value: doc),
        ChangeNotifierProvider<EditorController>.value(value: editor),
        ChangeNotifierProvider<WorkspaceController>.value(value: workspace),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPreferences(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Future<void> page(IconData icon, String name, List<String> expected) async {
      await tester.tap(find.byIcon(icon));
      await tester.pump(const Duration(milliseconds: 300));
      final list = find
          .descendant(of: find.byType(Dialog), matching: find.byType(ListView))
          .last;
      // Start from the top of the page.
      await tester.drag(list, const Offset(0, 4000));
      await tester.pump();
      for (final t in expected) {
        for (var i = 0;
            i < 30 && find.text(t).evaluate().isEmpty;
            i++) {
          await tester.drag(list, const Offset(0, -120));
          await tester.pump();
        }
        expect(find.text(t), findsWidgets, reason: '$name: $t');
      }
    }

    await page(Icons.description_outlined, 'Files', [
      'On launch',
      'Default extension',
      'Save when switching files',
      'Record recent files',
      'Folders',
      'Markdown files',
      'Importable documents',
    ]);

    await page(Icons.edit_outlined, 'Editor', [
      'Indent size',
      'Pretty indentation',
      'Auto pair brackets and quotes',
      'Auto pair common markdown syntax',
      'Enable autocomplete for emojis',
      'Display source for simple blocks on focus',
      'Copy markdown source as plain text',
      'Copy or cut the whole line when there is no selection',
      'Always keep the caret in the middle of the screen',
      'Turn off Typewriter / Focus Mode',
      'Check spelling',
    ]);

    await page(Icons.tag, 'Markdown', [
      'Heading style',
      'Bullet list marker',
      'Ordered list delimiter',
      'Inline math',
      'Subscript',
      'Superscript',
      'Highlight',
      'Diagrams',
      'Smart quotes',
      'Display line numbers for code fences',
      'Auto wrap long lines',
      'Default code fence language',
      'Preserve single line break',
    ]);

    await page(Icons.palette_outlined, 'Appearance', [
      'Theme in dark mode',
      'Zoom with the mouse wheel',
      'Always show word count',
    ]);

    await page(Icons.settings_outlined, 'General', [
      'Quit when the window is closed',
      'Check for updates automatically',
    ]);
  });
}
