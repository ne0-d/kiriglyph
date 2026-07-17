import 'package:flutter_test/flutter_test.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/selection/region_selection.dart';

TextRegion _region(String id, String text, int order) => TextRegion(
  id: id,
  level: TextRegionLevel.line,
  text: text,
  polygon: const [
    Point(x: 0, y: 0),
    Point(x: 10, y: 0),
    Point(x: 10, y: 10),
    Point(x: 0, y: 10),
  ],
  confidence: 1,
  readingOrder: order,
);

/// Supplied deliberately out of reading order.
List<TextRegion> _shuffledRegions() => [
  _region('c', 'Gamma', 2),
  _region('a', 'Alpha', 0),
  _region('d', 'Delta', 3),
  _region('b', 'Beta', 1),
];

List<String> _selectedIds(RegionSelection selection) =>
    selection.selectedRegions.map((r) => r.id).toList();

void main() {
  group('reading order', () {
    test('regions are exposed in reading order regardless of input order', () {
      final selection = RegionSelection(_shuffledRegions());

      expect(selection.regions.map((r) => r.text), [
        'Alpha',
        'Beta',
        'Gamma',
        'Delta',
      ]);
    });

    test('Copy all text joins every line in reading order with newlines', () {
      final selection = RegionSelection(_shuffledRegions());

      expect(selection.allText, 'Alpha\nBeta\nGamma\nDelta');
    });

    test('regions with equal reading order keep their input order', () {
      final selection = RegionSelection([
        _region('first', 'One', 0),
        _region('second', 'Two', 0),
      ]);

      expect(selection.regions.map((r) => r.id), ['first', 'second']);
    });

    test('an empty result has no text and no selection', () {
      final selection = RegionSelection(const []);

      expect(selection.allText, '');
      expect(selection.hasSelection, isFalse);
      expect(selection.selectedText, '');
    });
  });

  group('single selection', () {
    test('selecting a region selects only that region', () {
      final selection = RegionSelection(_shuffledRegions()).select('b');

      expect(_selectedIds(selection), ['b']);
      expect(selection.isSelected('b'), isTrue);
      expect(selection.isSelected('a'), isFalse);
      expect(selection.selectedText, 'Beta');
    });

    test('selecting another region replaces the previous selection', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('a')
          .select('d');

      expect(_selectedIds(selection), ['d']);
    });

    test('selecting an unknown region leaves the selection unchanged', () {
      final before = RegionSelection(_shuffledRegions()).select('a');

      expect(_selectedIds(before.select('missing')), ['a']);
      expect(_selectedIds(before.extendTo('missing')), ['a']);
    });

    test('clearing removes the selection', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('a')
          .extendTo('c')
          .clear();

      expect(selection.hasSelection, isFalse);
      expect(selection.selectedRegions, isEmpty);
      expect(selection.selectedText, '');
    });
  });

  group('range extension', () {
    test('extending forward selects a contiguous range from the anchor', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('a')
          .extendTo('c');

      expect(_selectedIds(selection), ['a', 'b', 'c']);
      expect(selection.selectedText, 'Alpha\nBeta\nGamma');
    });

    test('extending backward selects the range in reading order', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('d')
          .extendTo('b');

      expect(_selectedIds(selection), ['b', 'c', 'd']);
      expect(selection.selectedText, 'Beta\nGamma\nDelta');
    });

    test('the anchor stays fixed across repeated extensions', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('b')
          .extendTo('d')
          .extendTo('a');

      expect(_selectedIds(selection), ['a', 'b']);
    });

    test('extending onto the anchor leaves just the anchor selected', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('b')
          .extendTo('d')
          .extendTo('b');

      expect(_selectedIds(selection), ['b']);
    });

    test('extending with no anchor behaves like a plain selection', () {
      final selection = RegionSelection(_shuffledRegions()).extendTo('c');

      expect(_selectedIds(selection), ['c']);
    });

    test('a plain selection after extension starts a new anchor', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('a')
          .extendTo('c')
          .select('d')
          .extendTo('c');

      expect(_selectedIds(selection), ['c', 'd']);
    });

    test('extending after clearing starts from the newly chosen region', () {
      final selection = RegionSelection(_shuffledRegions())
          .select('a')
          .clear()
          .extendTo('b');

      expect(_selectedIds(selection), ['b']);
    });
  });

  test('selection operations never mutate the previous selection', () {
    final base = RegionSelection(_shuffledRegions()).select('a');
    base.extendTo('d');

    expect(_selectedIds(base), ['a']);
  });
}
