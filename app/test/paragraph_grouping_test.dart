import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/paragraph_grouping.dart';
import 'package:kiriglyph/selection/region_selection.dart';

TextRegion _line(
  String id,
  String text,
  int order,
  double left,
  double top,
  double width,
  double height, {
  double tilt = 0,
}) {
  final right = left + width;
  final bottom = top + height;
  return TextRegion(
    id: id,
    level: TextRegionLevel.line,
    text: text,
    polygon: [
      Point(x: left, y: top),
      Point(x: right, y: top + tilt),
      Point(x: right, y: bottom + tilt),
      Point(x: left, y: bottom),
    ],
    confidence: 1,
    readingOrder: order,
    ranges: [
      for (var index = 0; index < text.length; index++)
        TextCharacterRange(
          start: index,
          end: index + 1,
          text: text[index],
          polygon: const [
            Point(x: 0, y: 0),
            Point(x: 1, y: 0),
            Point(x: 1, y: 1),
            Point(x: 0, y: 1),
          ],
          geometryKind: CharacterGeometryKind.derivedCtcPolygon,
          confidence: 1,
        ),
    ],
  );
}

List<List<String>> _ids(List<TextParagraph> paragraphs) => [
  for (final paragraph in paragraphs) paragraph.regionIds,
];

void main() {
  test('groups nearby aligned lines into one paragraph', () {
    final paragraphs = groupTextParagraphs([
      _line('a', 'First', 0, 20, 10, 120, 20),
      _line('b', 'Second', 1, 22, 35, 118, 20),
      _line('c', 'Third', 2, 21, 60, 119, 20),
    ]);

    expect(_ids(paragraphs), [
      ['a', 'b', 'c'],
    ]);
    expect(paragraphs.single.totalCharacterCount, 'FirstSecondThird'.length);
  });

  test('splits paragraphs separated by a larger vertical gap', () {
    final paragraphs = groupTextParagraphs([
      _line('a', 'First', 0, 20, 10, 120, 20),
      _line('b', 'Second', 1, 20, 70, 120, 20),
    ]);

    expect(_ids(paragraphs), [
      ['a'],
      ['b'],
    ]);
  });

  test('keeps a heading with body when line heights are similar enough', () {
    final paragraphs = groupTextParagraphs([
      _line('h', 'Heading', 0, 20, 10, 140, 30),
      _line('b', 'Body', 1, 22, 48, 130, 22),
    ]);

    expect(_ids(paragraphs), [
      ['h', 'b'],
    ]);
  });

  test('does not merge side-by-side columns', () {
    final paragraphs = groupTextParagraphs([
      _line('l1', 'Left one', 0, 20, 10, 80, 20),
      _line('r1', 'Right one', 1, 160, 10, 80, 20),
      _line('r2', 'Right two', 2, 160, 35, 80, 20),
    ]);

    expect(_ids(paragraphs), [
      ['l1'],
      ['r1', 'r2'],
    ]);
  });

  test('uses polygon edge distance for tilted line height', () {
    final paragraphs = groupTextParagraphs([
      _line('a', 'Tilt one', 0, 20, 10, 120, 20, tilt: 8),
      _line('b', 'Tilt two', 1, 20, 37, 120, 20, tilt: 8),
    ]);

    expect(_ids(paragraphs), [
      ['a', 'b'],
    ]);
  });

  test('allows plausible continuation indents', () {
    final paragraphs = groupTextParagraphs([
      _line('a', 'First line', 0, 20, 10, 180, 20),
      _line('b', 'Indented continuation', 1, 70, 35, 130, 20),
    ]);

    expect(_ids(paragraphs), [
      ['a', 'b'],
    ]);
  });

  group('extendSelectionByParagraph', () {
    // Paragraphs: [a, b], [c], [d, e].
    final regions = [
      _line('a', 'one', 0, 20, 10, 120, 20),
      _line('b', 'two', 1, 20, 35, 120, 20),
      _line('c', 'three', 2, 20, 90, 120, 20),
      _line('d', 'four', 3, 20, 150, 120, 20),
      _line('e', 'five', 4, 20, 175, 120, 20),
    ];
    final paragraphs = groupTextParagraphs(regions);

    RegionSelection extend(RegionSelection selection, int direction) =>
        extendSelectionByParagraph(selection, paragraphs, direction: direction);

    String text(RegionSelection selection) =>
        selectedTextWithParagraphSeparators(selection, paragraphs);

    test('the test fixture has three paragraphs', () {
      expect(_ids(paragraphs), [
        ['a', 'b'],
        ['c'],
        ['d', 'e'],
      ]);
    });

    test('down without a selection selects the first paragraph', () {
      expect(text(extend(RegionSelection(regions), 1)), 'one\ntwo');
    });

    test('up without a selection selects the last paragraph', () {
      expect(text(extend(RegionSelection(regions), -1)), 'four\nfive');
    });

    test('repeated presses extend one paragraph at a time', () {
      var selection = extend(RegionSelection(regions), 1);
      selection = extend(selection, 1);
      expect(text(selection), 'one\ntwo\n\nthree');
      selection = extend(selection, 1);
      expect(text(selection), 'one\ntwo\n\nthree\n\nfour\nfive');
      // Nothing is left below; the selection stays as it is.
      expect(text(extend(selection, 1)), text(selection));
    });

    test('up extends towards the start of the page', () {
      var selection = extend(RegionSelection(regions), -1);
      selection = extend(selection, -1);
      expect(text(selection), 'three\n\nfour\nfive');
    });

    test('a partial selection first snaps to its whole paragraph', () {
      final partial = RegionSelection(regions).selectRange('c', 1, 3);
      expect(text(extend(partial, 1)), 'three');
      expect(text(extend(partial, -1)), 'three');
    });

    test('a partial selection spanning paragraphs snaps to all of them', () {
      final partial = RegionSelection(regions)
          .startAt(const TextPosition(regionId: 'b', offset: 1))
          .extendToPosition(const TextPosition(regionId: 'c', offset: 2));
      expect(text(extend(partial, 1)), 'one\ntwo\n\nthree');
    });

    test('a circled selection of whole lines extends from its paragraphs', () {
      final circled = RegionSelection(regions).selectLineRanges({'c': (0, 5)});
      expect(text(extend(circled, 1)), 'three\n\nfour\nfive');
      expect(text(extend(circled, -1)), 'one\ntwo\n\nthree');
    });

    test('no recognised text leaves the selection empty', () {
      final empty = RegionSelection(const []);
      expect(
        extendSelectionByParagraph(empty, const [], direction: 1).hasSelection,
        isFalse,
      );
    });
  });
}
