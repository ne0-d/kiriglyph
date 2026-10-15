import 'dart:math' as math;

import 'package:kiriglyph/segmentation/subject_segmenter.dart';

class SubjectPromptPoint {
  const SubjectPromptPoint(this.x, this.y, {this.foreground = true});

  final double x;
  final double y;
  final bool foreground;

  SubjectPoint toSegmenterPoint() => SubjectPoint(x, y, foreground: foreground);
}

class SubjectPromptState {
  const SubjectPromptState({
    this.prompt = const SubjectPrompt(),
    this.previous = const [],
  });

  final SubjectPrompt prompt;
  final List<SubjectPrompt> previous;

  bool get isEmpty =>
      prompt.points.isEmpty && prompt.box == null && prompt.polygon == null;

  SubjectPromptState replacePoint(SubjectPromptPoint point) =>
      _next(SubjectPrompt(points: [point.toSegmenterPoint()]));

  SubjectPromptState addForeground(SubjectPromptPoint point) => _next(
    SubjectPrompt(
      points: [...prompt.points, point.toSegmenterPoint()],
      box: prompt.box,
      polygon: prompt.polygon,
    ),
  );

  SubjectPromptState addBackground(SubjectPromptPoint point) => _next(
    SubjectPrompt(
      points: [
        ...prompt.points,
        SubjectPoint(point.x, point.y, foreground: false),
      ],
      box: prompt.box,
      polygon: prompt.polygon,
    ),
  );

  SubjectPromptState replaceRegion(List<SubjectPromptPoint> points) {
    if (points.length < 3) {
      return this;
    }
    var left = points.first.x;
    var right = points.first.x;
    var top = points.first.y;
    var bottom = points.first.y;
    for (final point in points.skip(1)) {
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    return _next(
      SubjectPrompt(
        box: SubjectBox(
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
        ),
        polygon: SubjectPolygon([
          for (final point in points) point.toSegmenterPoint(),
        ]),
      ),
    );
  }

  SubjectPromptState clear() => isEmpty ? this : _next(const SubjectPrompt());

  SubjectPromptState undo() {
    if (previous.isEmpty) {
      return this;
    }
    return SubjectPromptState(
      prompt: previous.last,
      previous: previous.sublist(0, previous.length - 1),
    );
  }

  SubjectPromptState _next(SubjectPrompt next) =>
      SubjectPromptState(prompt: next, previous: [...previous, prompt]);
}
