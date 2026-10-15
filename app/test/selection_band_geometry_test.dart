import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/ui/workspace/selection_band_geometry.dart';

void main() {
  test('builds one continuous tilted band across unselected gaps', () {
    const line = [
      Offset(0, 0),
      Offset(100, 10),
      Offset(100, 30),
      Offset(0, 20),
    ];
    const characters = [
      [Offset(0, 0), Offset(10, 1), Offset(10, 21), Offset(0, 20)],
      [Offset(30, 3), Offset(40, 4), Offset(40, 24), Offset(30, 23)],
    ];

    final band = buildLineSelectionBand(
      characterPolygons: characters,
      selected: const [true, true],
      linePolygon: line,
    );

    expect(band, isNotNull);
    expect(band![0], const Offset(0, 0));
    expect(band[3], const Offset(0, 20));
    expect(band[1].dx, closeTo(40, 0.001));
    expect(band[1].dy, closeTo(4, 0.001));
    expect(band[2].dx, closeTo(40, 0.001));
    expect(band[2].dy, closeTo(24, 0.001));
  });

  test('uses the full line height for a short selected glyph', () {
    const line = [Offset(0, 0), Offset(100, 0), Offset(100, 30), Offset(0, 30)];
    const characters = [
      [Offset(20, 8), Offset(30, 8), Offset(30, 18), Offset(20, 18)],
    ];

    final band = buildLineSelectionBand(
      characterPolygons: characters,
      selected: const [true],
      linePolygon: line,
    );

    expect(band, [
      const Offset(20, 0),
      const Offset(30, 0),
      const Offset(30, 30),
      const Offset(20, 30),
    ]);
  });
}
