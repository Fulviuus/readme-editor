import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/app/open_quickly.dart';

void main() {
  group('fuzzyScore', () {
    test('non-subsequence returns null', () {
      expect(fuzzyScore('xyz', 'notes.md'), isNull);
    });

    test('empty query matches everything', () {
      expect(fuzzyScore('', 'anything'), 0);
    });

    test('subsequence matches', () {
      expect(fuzzyScore('nts', 'notes.md'), isNotNull);
    });

    test('word-start match scores better than mid-word', () {
      final start = fuzzyScore('r', 'readme.md')!;
      final mid = fuzzyScore('r', 'aardvark.md')!;
      expect(start, lessThan(mid));
    });

    test('contiguous run scores better than scattered', () {
      final run = fuzzyScore('rea', 'readme')!;
      final scattered = fuzzyScore('rme', 'readme')!;
      expect(run, lessThan(scattered));
    });
  });
}
