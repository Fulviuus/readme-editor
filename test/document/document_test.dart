import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/document/document.dart';

void main() {
  group('link definitions', () {
    test('collects [ref]: url across blocks, normalized', () {
      final doc = Document.parse(
          'See [text][My Ref].\n\n[my ref]: https://example.com\n');
      expect(doc.linkDefinitions['my ref'], 'https://example.com');
    });

    test('first definition wins', () {
      final doc = Document.parse('[a]: one\n\n[a]: two');
      expect(doc.linkDefinitions['a'], 'one');
    });
  });

  group('footnotes', () {
    test('numbers by first reference order; collects definition text', () {
      final doc = Document.parse(
          'First[^b] then[^a].\n\n[^a]: alpha\n\n[^b]: beta\n');
      expect(doc.footnotes.numbers['b'], 1);
      expect(doc.footnotes.numbers['a'], 2);
      expect(doc.footnotes.texts['a'], 'alpha');
      expect(doc.footnotes.texts['b'], 'beta');
    });

    test('definition lines are not counted as references', () {
      final doc = Document.parse('[^1]: only a definition');
      expect(doc.footnotes.numbers, isEmpty);
      expect(doc.footnotes.texts['1'], 'only a definition');
    });
  });
}
