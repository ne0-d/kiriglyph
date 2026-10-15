import 'dart:io';

enum SubjectFailureKind {
  cancelled,
  timeout,
  malformedOutput,
  modelLoadFailed,
  modelMissing,
  processDied,
  outOfMemory,
  sessionClosed,
}

enum SubjectMaskOutcome { ok, empty, suspectFullImage }

class SubjectSegmentationException implements Exception {
  const SubjectSegmentationException({
    required this.kind,
    required this.message,
    this.command,
  });

  final SubjectFailureKind kind;
  final String message;
  final String? command;

  @override
  String toString() => 'SubjectSegmentationException(${kind.name}): $message';
}

class SubjectEmbedding {
  const SubjectEmbedding({
    required this.handle,
    required this.imageWidth,
    required this.imageHeight,
    required this.timings,
  });

  final String handle;
  final int imageWidth;
  final int imageHeight;
  final SubjectSegmentationTimings timings;
}

class SubjectPoint {
  const SubjectPoint(this.x, this.y, {this.foreground = true});

  final double x;
  final double y;
  final bool foreground;

  Map<String, Object> toJson() => {
    'x': x,
    'y': y,
    'label': foreground ? 'foreground' : 'background',
  };
}

class SubjectBox {
  const SubjectBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

class SubjectPolygon {
  const SubjectPolygon(this.points);

  final List<SubjectPoint> points;

  Map<String, Object> toJson() => {
    'points': points.map((point) => point.toJson()).toList(growable: false),
  };
}

class SubjectPrompt {
  const SubjectPrompt({this.points = const [], this.box, this.polygon});

  final List<SubjectPoint> points;
  final SubjectBox? box;
  final SubjectPolygon? polygon;

  Map<String, Object?> toJson() => {
    'points': points.map((point) => point.toJson()).toList(growable: false),
    'box': box?.toJson(),
    'polygon': polygon?.toJson(),
  };
}

class SubjectMaskReference {
  const SubjectMaskReference({
    required this.path,
    required this.byteLength,
    required this.sha256,
  });

  final String path;
  final int byteLength;
  final String sha256;
}

class SubjectRect {
  const SubjectRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

class SubjectEdgeTouches {
  const SubjectEdgeTouches({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final bool left;
  final bool top;
  final bool right;
  final bool bottom;

  bool get any => left || top || right || bottom;
}

class SubjectComponentStats {
  const SubjectComponentStats({required this.count, this.largestBounds});

  final int count;
  final SubjectRect? largestBounds;

  bool get multipleComponents => count > 1;
}

class SubjectMaskStats {
  const SubjectMaskStats({
    required this.outcome,
    required this.areaFraction,
    required this.bounds,
    required this.touchesEdge,
    required this.components,
  });

  final SubjectMaskOutcome outcome;
  final double areaFraction;
  final SubjectRect? bounds;
  final SubjectEdgeTouches touchesEdge;
  final SubjectComponentStats components;
}

class SubjectSegmentationTimings {
  const SubjectSegmentationTimings({
    this.loadMs,
    this.embedMs,
    this.firstMaskMs,
    this.promptMs,
  });

  final double? loadMs;
  final double? embedMs;
  final double? firstMaskMs;
  final double? promptMs;
}

class SubjectMaskResult {
  const SubjectMaskResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.mask,
    required this.bounds,
    required this.stats,
    required this.timings,
    this.confidence,
    this.stabilityScore,
  });

  final int imageWidth;
  final int imageHeight;
  final SubjectMaskReference mask;
  final SubjectRect? bounds;
  final SubjectMaskStats stats;
  final SubjectSegmentationTimings timings;
  final double? confidence;
  final double? stabilityScore;
}

abstract class SubjectSegmenter {
  Future<SubjectEmbedding> embed(String imagePath);

  Future<SubjectMaskResult> prompt(
    SubjectEmbedding embedding,
    SubjectPrompt prompt,
  );

  Future<void> cancelActive();

  Future<void> close();
}

Future<void> deleteMaskFile(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // Mask files are session-scoped temp files. Missing already means clean.
  }
}
