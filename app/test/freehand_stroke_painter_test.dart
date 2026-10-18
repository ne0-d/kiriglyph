import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';
import 'package:kiriglyph/ui/workspace/freehand_stroke_painter.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

void main() {
  test('centripetalCatmullRomPath produces more than two segments', () {
    final path = FreehandStrokePainter.centripetalCatmullRomPath(const [
      Offset(0, 0),
      Offset(20, 5),
      Offset(40, 0),
      Offset(60, 8),
    ]);
    expect(path.getBounds().width, greaterThan(40));
  });

  testWidgets('reduced motion painter keeps a simple stroke', (tester) async {
    final geometry = FittedImageGeometry.contain(
      bounds: const Rect.fromLTWH(0, 0, 400, 200),
      imageSize: const Size(400, 200),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: FreehandStrokePainter(
            points: const [
              Point(x: 10, y: 10),
              Point(x: 80, y: 12),
              Point(x: 80, y: 80),
            ],
            geometry: geometry,
            transform: Matrix4.identity(),
            opacity: 1,
            color: Colors.orange,
            secondaryColor: Colors.deepOrange,
            policy: MotionPolicy.reduced,
            closedLoop: true,
          ),
          size: const Size(400, 200),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
