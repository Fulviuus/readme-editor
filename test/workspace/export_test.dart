import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/document.dart';
import 'package:readme/src/theme/readme_theme.dart';
import 'package:readme/src/workspace/export/docx_export.dart';
import 'package:readme/src/workspace/export/epub_export.dart';
import 'package:readme/src/workspace/export/latex_export.dart';
import 'package:readme/src/workspace/export/rtf_export.dart';

const _md = '''
# Title

Some **bold**, *italic*, `code`, and a [link](https://example.com).

- one
- two
  - nested

1. first
2. second

- [x] done task

> quoted line

```dart
void main() {}
```

| A | B |
|---|---|
| 1 | 2 |

Math \$x^2\$ inline.
''';

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
  final doc = Document.parse(_md);

  group('docx export', () {
    final bytes = buildDocx(doc, title: 'Test');
    final zip = ZipDecoder().decodeBytes(bytes);
    String part(String name) =>
        utf8.decode(zip.findFile(name)!.content as List<int>);

    test('package has the required parts', () {
      for (final name in [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/numbering.xml',
        'word/_rels/document.xml.rels',
      ]) {
        expect(zip.findFile(name), isNotNull, reason: name);
      }
    });

    test('document.xml carries styled content', () {
      final xml = part('word/document.xml');
      expect(xml, contains('w:pStyle w:val="Heading1"'));
      expect(xml, contains('<w:b/>'));
      expect(xml, contains('<w:i/>'));
      expect(xml, contains('bold'));
      expect(xml, contains('<w:hyperlink r:id='));
      expect(xml, contains('<w:tbl>'));
      expect(xml, contains('w:numId'));
      expect(xml, contains('☑'));
      expect(xml, contains('void main() {}'));
      // Escaping stays intact.
      expect(xml, isNot(contains('&&')));
    });

    test('hyperlink relationship targets the URL', () {
      expect(part('word/_rels/document.xml.rels'),
          contains('https://example.com'));
    });
  });

  group('epub export', () {
    final bytes = buildEpub(_md, theme(), title: 'Test');
    final zip = ZipDecoder().decodeBytes(bytes);

    test('mimetype is the first entry and stored uncompressed', () {
      final first = zip.files.first;
      expect(first.name, 'mimetype');
      expect(utf8.decode(first.content as List<int>),
          'application/epub+zip');
      // Raw bytes of the archive: stored mimetype starts at a fixed spot.
      expect(bytes.sublist(38, 38 + 20),
          utf8.encode('application/epub+zip'));
    });

    test('container, opf, nav, chapter and css are present', () {
      for (final name in [
        'META-INF/container.xml',
        'OEBPS/content.opf',
        'OEBPS/nav.xhtml',
        'OEBPS/doc.xhtml',
        'OEBPS/style.css',
      ]) {
        expect(zip.findFile(name), isNotNull, reason: name);
      }
      final chapter =
          utf8.decode(zip.findFile('OEBPS/doc.xhtml')!.content as List<int>);
      expect(chapter, contains('<strong>bold</strong>'));
      expect(chapter, contains('Title'));
    });
  });

  group('rtf export', () {
    final rtf = buildRtf(doc);
    test('is a well-formed RTF document with content', () {
      expect(rtf, startsWith(r'{\rtf1'));
      expect(rtf, endsWith('}'));
      expect(rtf, contains(r'\b'));
      expect(rtf, contains('bold'));
      expect(rtf, contains(r'\trowd'));
      expect(rtf, contains('void main() {}'.replaceAll('{', r'\{').replaceAll('}', r'\}')));
      // Balanced groups.
      var depth = 0;
      for (var i = 0; i < rtf.length; i++) {
        if (rtf[i] == r'\'[0] ) { i++; continue; }
        if (rtf[i] == '{') depth++;
        if (rtf[i] == '}') depth--;
        expect(depth, greaterThanOrEqualTo(0));
      }
      expect(depth, 0);
    });
  });

  group('latex export', () {
    final tex = buildLatex(doc, title: 'Test');
    test('is a standalone article with escaped content', () {
      expect(tex, contains(r'\documentclass'));
      expect(tex, contains(r'\section*{Title}'));
      expect(tex, contains(r'\textbf{bold}'));
      expect(tex, contains(r'\begin{itemize}'));
      expect(tex, contains(r'\begin{enumerate}'));
      expect(tex, contains(r'\begin{verbatim}'));
      expect(tex, contains(r'\href{https://example.com}'));
      expect(tex, contains(r'$x^2$'));
      expect(tex, contains(r'\end{document}'));
    });
  });
}
