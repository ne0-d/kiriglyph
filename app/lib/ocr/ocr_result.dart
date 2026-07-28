import 'package:flutter/foundation.dart';

enum TextRegionLevel { line }

enum CharacterGeometryKind { derivedCtcPolygon, interpolatedGap }

@immutable
class Point {
  const Point({required this.x, required this.y});

  final double x;
  final double y;
}

@immutable
class TextCharacterRange {
  const TextCharacterRange({
    required this.start,
    required this.end,
    required this.text,
    required this.polygon,
    required this.geometryKind,
    required this.confidence,
  });

  final int start;
  final int end;
  final String text;
  final List<Point> polygon;
  final CharacterGeometryKind geometryKind;
  final double? confidence;
}

@immutable
class TextRegion {
  const TextRegion({
    required this.id,
    required this.level,
    required this.text,
    required this.polygon,
    required this.confidence,
    required this.readingOrder,
    this.ranges = const [],
  });

  final String id;
  final TextRegionLevel level;
  final String text;
  final List<Point> polygon;
  final double confidence;
  final int readingOrder;
  final List<TextCharacterRange> ranges;
}

@immutable
class TimingsMs {
  const TimingsMs({required this.total});

  final num total;
}

@immutable
class OcrResult {
  const OcrResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.fullText,
    required this.regions,
    required this.timingsMs,
  });

  final int imageWidth;
  final int imageHeight;
  final String fullText;
  final List<TextRegion> regions;
  final TimingsMs timingsMs;
}
