import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kiriglyph/ocr/ocr_result.dart' as ocr;
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/selection/freehand_selection_geometry.dart';
import 'package:kiriglyph/selection/subject_prompt_state.dart';
import 'package:kiriglyph/ui/overlay/subject_mask_alpha.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

class SubjectOverlayLayer extends StatefulWidget {
  const SubjectOverlayLayer({
    super.key,
    required this.geometry,
    required this.imageWidth,
    required this.imageHeight,
    required this.promptState,
    required this.maskImage,
    required this.maskResult,
    required this.onPromptChanged,
    this.dimMask = false,
  });

  final FittedImageGeometry geometry;
  final int imageWidth;
  final int imageHeight;
  final SubjectPromptState promptState;
  final CanonicalSubjectMask? maskImage;
  final SubjectMaskResult? maskResult;
  final ValueChanged<SubjectPromptState> onPromptChanged;
  final bool dimMask;

  @override
  State<SubjectOverlayLayer> createState() => _SubjectOverlayLayerState();
}

class _SubjectOverlayLayerState extends State<SubjectOverlayLayer> {
  int? _pointer;
  List<ocr.Point> _sourceStroke = const [];
  List<ocr.Point> _viewportStroke = const [];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Subject selection',
      hint:
          'Click to select a subject. Shift click adds foreground. Alt click '
          'or right click adds background. Drag to draw around a subject.',
      value: _subjectValue(widget.maskResult),
      selected: widget.maskResult?.stats.outcome == SubjectMaskOutcome.ok,
      child: Listener(
        key: const Key('subject-overlay-layer'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.maskImage != null && widget.maskResult != null)
              Positioned.fill(
                child: CustomPaint(
                  key: const Key('subject-mask-paint'),
                  painter: SubjectMaskPainter(
                    mask: widget.maskImage!.image,
                    geometry: widget.geometry,
                    result: widget.maskResult!,
                    color: Theme.of(context).colorScheme.primary,
                    dimSubject: widget.dimMask,
                  ),
                ),
              ),
            if (_viewportStroke.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('subject-lasso-stroke'),
                    painter: _SubjectStrokePainter(
                      points: _viewportStroke,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _sourceStroke = [_sourcePoint(event.localPosition)];
    _viewportStroke = [_point(event.localPosition)];
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final next = _point(event.localPosition);
    if (_viewportStroke.isNotEmpty &&
        pathLength([_viewportStroke.last, next]) < 1) {
      return;
    }
    setState(() {
      _viewportStroke = [..._viewportStroke, next];
      _sourceStroke = [..._sourceStroke, _sourcePoint(event.localPosition)];
    });
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final source = [..._sourceStroke, _sourcePoint(event.localPosition)];
    final viewport = [..._viewportStroke, _point(event.localPosition)];
    final base = widget.promptState;
    final next = isUsableFreehandStroke(viewport)
        ? base.replaceRegion([
            for (final point in source) SubjectPromptPoint(point.x, point.y),
          ])
        : _clickPrompt(event, base, source.last);
    setState(() {
      _pointer = null;
      _sourceStroke = const [];
      _viewportStroke = const [];
    });
    widget.onPromptChanged(next);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    setState(() {
      _pointer = null;
      _sourceStroke = const [];
      _viewportStroke = const [];
    });
  }

  SubjectPromptState _clickPrompt(
    PointerUpEvent event,
    SubjectPromptState base,
    ocr.Point point,
  ) {
    final promptPoint = SubjectPromptPoint(point.x, point.y);
    final alt = HardwareKeyboard.instance.isAltPressed;
    final secondary = event.buttons & kSecondaryMouseButton != 0;
    if (alt || secondary) {
      return base.addBackground(promptPoint);
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return base.addForeground(promptPoint);
    }
    return base.replacePoint(promptPoint);
  }

  ocr.Point _sourcePoint(Offset position) {
    final raw = widget.geometry.unmapPoint(position);
    return ocr.Point(
      x: raw.x.clamp(0, widget.imageWidth.toDouble()),
      y: raw.y.clamp(0, widget.imageHeight.toDouble()),
    );
  }

  static ocr.Point _point(Offset offset) =>
      ocr.Point(x: offset.dx, y: offset.dy);

  static String _subjectValue(SubjectMaskResult? result) {
    if (result == null ||
        result.stats.outcome != SubjectMaskOutcome.ok ||
        result.stats.areaFraction <= 0) {
      return 'No subject selected';
    }
    final percent = (result.stats.areaFraction * 100).round();
    return 'Subject selected, covers $percent percent of the screen';
  }
}

class SubjectMaskImage extends StatefulWidget {
  const SubjectMaskImage({
    super.key,
    required this.result,
    required this.builder,
  });

  final SubjectMaskResult? result;
  final Widget Function(BuildContext context, CanonicalSubjectMask? image)
  builder;

  @override
  State<SubjectMaskImage> createState() => _SubjectMaskImageState();
}

class _SubjectMaskImageState extends State<SubjectMaskImage> {
  String? _path;
  CanonicalSubjectMask? _image;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant SubjectMaskImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  void _loadIfNeeded() {
    final path = widget.result?.mask.path;
    if (path == _path) {
      return;
    }
    _image?.dispose();
    _path = path;
    _image = null;
    if (path == null) {
      return;
    }
    unawaited(_load(path));
  }

  Future<void> _load(String path) async {
    try {
      final image = await loadCanonicalSubjectMask(path);
      if (mounted && path == _path) {
        setState(() => _image = image);
      } else {
        image.dispose();
      }
    } catch (_) {
      // A failed mask load is recoverable; keep status text visible.
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _image);
}

class SubjectMaskPainter extends CustomPainter {
  const SubjectMaskPainter({
    required this.mask,
    required this.geometry,
    required this.result,
    required this.color,
    this.scrimOpacity = 0.30,
    this.dimSubject = false,
  });

  final ui.Image mask;
  final FittedImageGeometry geometry;
  final SubjectMaskResult result;
  final Color color;
  final double scrimOpacity;
  final bool dimSubject;

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.destination.isEmpty ||
        result.stats.outcome == SubjectMaskOutcome.suspectFullImage) {
      return;
    }
    final src = Rect.fromLTWH(
      0,
      0,
      mask.width.toDouble(),
      mask.height.toDouble(),
    );
    final dst = geometry.destination;
    if (scrimOpacity > 0) {
      canvas.saveLayer(Offset.zero & size, Paint());
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: scrimOpacity),
      );
      canvas.drawImageRect(
        mask,
        src,
        dst,
        Paint()
          ..isAntiAlias = true
          ..blendMode = BlendMode.dstOut,
      );
      canvas.restore();
    }
    // Border only: draw a dilated halo (dark outer, light inner) and then
    // punch the subject itself out of that layer so its interior is untouched.
    final outline = Paint()
      ..isAntiAlias = true
      ..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn);
    final bright = Paint()
      ..isAntiAlias = true
      ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn);
    final punch = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.dstOut;
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final offset in _haloOffsets(3)) {
      canvas.drawImageRect(mask, src, dst.shift(offset), outline);
    }
    for (final offset in _haloOffsets(1.5)) {
      canvas.drawImageRect(mask, src, dst.shift(offset), bright);
    }
    canvas.drawImageRect(mask, src, dst, punch);
    canvas.restore();
  }

  static List<Offset> _haloOffsets(double radius) {
    final diagonal = radius * 0.7071;
    return [
      Offset(-radius, 0),
      Offset(radius, 0),
      Offset(0, -radius),
      Offset(0, radius),
      Offset(-diagonal, -diagonal),
      Offset(diagonal, -diagonal),
      Offset(-diagonal, diagonal),
      Offset(diagonal, diagonal),
    ];
  }

  @override
  bool shouldRepaint(covariant SubjectMaskPainter oldDelegate) =>
      oldDelegate.mask != mask ||
      oldDelegate.geometry != geometry ||
      oldDelegate.result != result ||
      oldDelegate.color != color ||
      oldDelegate.scrimOpacity != scrimOpacity ||
      oldDelegate.dimSubject != dimSubject;
}

class _SubjectStrokePainter extends CustomPainter {
  const _SubjectStrokePainter({required this.points, required this.color});

  final List<ocr.Point> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SubjectStrokePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
