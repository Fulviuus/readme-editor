import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/document.dart';
import 'package:readme/src/theme/readme_theme.dart';
import 'package:readme/src/workspace/pdf_render.dart';

ReadmeTheme theme() => ReadmeTheme.fromJson('t', {
      'name': 'Test',
      'foreground': '#222222',
      'background': '#ffffff',
      'accent': '#4183C4',
      'blockquoteBorder': '#dfe2e5',
      'link': '#4183C4',
      'linkHover': '#4183C4',
      'hr': '#e7e7e7',
      'checkboxAccent': '#4183C4',
      'tableBorder': '#dddddd',
      'sidebarBackground': '#fafafa',
      'sidebarForeground': '#777777',
      'sidebarActiveBackground': '#eeeeee',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a kitchen-sink document to valid PDF bytes', () async {
    final doc = Document.parse(
      '# Heading — with unicode ✓ ✔ … “quotes”\n\n'
      'A paragraph with **bold**, *italic*, `code`, ~~strike~~ and '
      '[a link](https://example.com).\n\n'
      '> A blockquote line.\n\n'
      '- one\n- two\n  - nested\n- [x] done\n\n'
      '1. first\n2. second\n\n'
      '```dart\nvoid main() {}\n```\n\n'
      '| a | b |\n|---|---|\n| 1 | 2 |\n\n'
      '---\n\n'
      'Final paragraph.\n',
    );
    final bytes = await renderDocumentPdf(doc, theme(), title: 'Probe');

    // Valid PDF: %PDF- header, %%EOF trailer, non-trivial size.
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final tail = String.fromCharCodes(bytes.sublist(bytes.length - 8));
    expect(tail, contains('EOF'));
  });

  test('empty document still renders', () async {
    final bytes = await renderDocumentPdf(Document.parse(''), theme());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
