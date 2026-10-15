import 'dart:math' as math;
import 'dart:ui';

import 'package:kiriglyph/ocr/ocr_result.dart';

/// Maps source-image coordinates onto a `BoxFit.contain` destination.
///
/// This is the single source of truth for where the image sits inside the
/// canvas. The image, the painted OCR regions and the pointer hit targets
/// all derive their rectangles from the same instance, so they cannot drift
/// apart when the window is resized.
class FittedImageGeometry {
  const FittedImageGeometry._({required this.destination, required this.scale});

  /// Fits an image of [imageSize] inside [bounds], centred, preserving its
  /// aspect ratio. Never stretches. Empty inputs produce an empty
  /// destination.
  factory FittedImageGeometry.contain({
    required Rect bounds,
    required Size imageSize,
  }) {
    if (bounds.width <= 0 ||
        bounds.height <= 0 ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return FittedImageGeometry._(
        destination: Rect.fromLTWH(bounds.left, bounds.top, 0, 0),
        scale: 0,
      );
    }
    final scale = math.min(
      bounds.width / imageSize.width,
      bounds.height / imageSize.height,
    );
    final width = imageSize.width * scale;
    final height = imageSize.height * scale;
    return FittedImageGeometry._(
      destination: Rect.fromLTWH(
        bounds.left + (bounds.width - width) / 2,
        bounds.top + (bounds.height - height) / 2,
        width,
        height,
      ),
      scale: scale,
    );
  }

  /// Smallest hit target edge, in logical pixels, for tiny OCR boxes.
  static const double minHitExtent = 32;

  /// Where the image is drawn, in canvas coordinates.
  final Rect destination;

  /// Display pixels per source pixel.
  final double scale;

  /// Maps a source-image point to canvas coordinates.
  Offset mapPoint(Point point) => Offset(
    destination.left + point.x * scale,
    destination.top + point.y * scale,
  );

  /// Maps a canvas point back into source-image coordinates.
  Point unmapPoint(Offset point) {
    if (scale == 0) {
      return const Point(x: 0, y: 0);
    }
    return Point(
      x: (point.dx - destination.left) / scale,
      y: (point.dy - destination.top) / scale,
    );
  }

  /// The region's polygon in canvas coordinates.
  List<Offset> regionPolygon(TextRegion region) =>
      region.polygon.map(mapPoint).toList(growable: false);

  List<Offset> rangePolygon(TextCharacterRange range) =>
      range.polygon.map(mapPoint).toList(growable: false);

  /// Axis-aligned bounds of the region as it is drawn.
  Rect regionRect(TextRegion region) => _bounds(regionPolygon(region));

  Rect rangeRect(TextCharacterRange range) => _bounds(rangePolygon(range));

  Rect _bounds(List<Offset> points) {
    if (points.isEmpty) {
      return Rect.zero;
    }
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// The pointer target for [region]: the drawn bounds, grown symmetrically
  /// about their centre to at least [minExtent] on each axis. Drawing keeps
  /// using [regionRect].
  Rect hitRect(TextRegion region, {double minExtent = minHitExtent}) {
    final drawn = regionRect(region);
    final width = math.max(drawn.width, minExtent);
    final height = math.max(drawn.height, minExtent);
    return Rect.fromCenter(center: drawn.center, width: width, height: height);
  }
}
