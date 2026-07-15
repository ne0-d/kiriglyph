import 'package:flutter/foundation.dart';

enum TextRegionLevel { line }

@immutable
class Point {
  const Point({required this.x, required this.y});

  final double x;
  final double y;
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
  });

  final String id;
  final TextRegionLevel level;
  final String text;
  final List<Point> polygon;
  final double confidence;
  final int readingOrder;
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
