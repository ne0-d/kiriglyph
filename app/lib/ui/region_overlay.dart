import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';

class RegionOverlay extends StatelessWidget {
  const RegionOverlay({
    super.key,
    required this.region,
    required this.imageWidth,
    required this.imageHeight,
  });

  final TextRegion region;
  final int imageWidth;
  final int imageHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: Key('ocr-region-${region.id}'),
      painter: _RegionCornerPainter(
        region: region,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ),
    );
  }
}

class _RegionCornerPainter extends CustomPainter {
  _RegionCornerPainter({
    required this.region,
    required this.imageWidth,
    required this.imageHeight,
  });

  final TextRegion region;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    final xs = region.polygon.map((p) => p.x * scaleX).toList();
    final ys = region.polygon.map((p) => p.y * scaleY).toList();
    final left = xs.reduce(math.min);
    final right = xs.reduce(math.max);
    final top = ys.reduce(math.min);
    final bottom = ys.reduce(math.max);

    final paint = Paint()
      ..color = AppColors.ubuntuOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final corner = math.min(14.0, math.min(right - left, bottom - top) / 4);

    void cornerL(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
    }

    cornerL(left, top, corner, corner);
    cornerL(right, top, -corner, corner);
    cornerL(left, bottom, corner, -corner);
    cornerL(right, bottom, -corner, -corner);
  }

  @override
  bool shouldRepaint(covariant _RegionCornerPainter oldDelegate) {
    return oldDelegate.region != region ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
