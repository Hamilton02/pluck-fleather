import 'package:flutter_test/flutter_test.dart';
import 'package:pluck_fleather/src/fast_diff.dart';

void main() {
  group('fastDiff', () {
    test('insert', () {
      var oldText = 'fastDiff';
      var newText = 'fasterDiff';
      var result = fastDiff(oldText, newText, 6);
      expect(result.start, 4);
      expect(result.deleted, '');
      expect(result.inserted, 'er');
      expect('$result', 'DiffResult[4, "", "er"]');
    });

    test('delete', () {
      var oldText = 'fastDiff';
      var newText = 'fasDiff';
      var result = fastDiff(oldText, newText, 3);
      expect(result.start, 3);
      expect(result.deleted, 't');
      expect(result.inserted, '');
    });

    test('replace', () {
      var oldText = 'fastDiff';
      var newText = 'fas_Diff';
      var result = fastDiff(oldText, newText, 4);
      expect(result.start, 3);
      expect(result.deleted, 't');
      expect(result.inserted, '_');
    });
  });
}
