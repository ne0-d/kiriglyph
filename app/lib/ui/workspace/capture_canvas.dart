import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/a11y/dual_stroke.dart';
import 'package:kiriglyph/a11y/overlay_announcer.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/freehand_selection_geometry.dart';
import 'package:kiriglyph/selection/paragraph_grouping.dart';
import 'package:kiriglyph/selection/region_selection.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart' as rect;
import 'package:kiriglyph/selection/selection_intent.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';
import 'package:kiriglyph/ui/workspace/capture_image.dart';
import 'package:kiriglyph/ui/workspace/freehand_stroke_painter.dart';
import 'package:kiriglyph/ui/workspace/character_hit_test.dart';
import 'package:kiriglyph/ui/workspace/character_line_target.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';
import 'package:kiriglyph/ui/workspace/region_target.dart';

const _canvasPadding = 24.0;
const _minZoom = 1.0;
const _maxZoom = 4.0;
const _zoomStep = 0.25;
const _clickMovementTolerance = 18.0;

/// Dark inspection canvas: the image fitted with `BoxFit.contain`, with OCR
/// regions painted and hit-tested from the same fitted rectangle.
class CaptureCanvas extends ConsumerStatefulWidget {
  const CaptureCanvas({
    super.key,
    required String this.imagePath,
    required this.ocrResult,
    this.onTextSelectionStarted,
    this.onObjectPoint,
    this.onObjectLoop,
    this.onLoopInterpreted,
    this.selectionTool = rect.SelectionTool.freeDraw,
    this.onRectangleSelectionChanged,
    this.onRectangleSelectionFinished,
    this.focusNode,
    this.rectangleClearToken = 0,
    this.cursorScale = 1,
  }) : fullBleed = false;

  /// Selection over pixels the parent paints edge to edge underneath: no
  /// padding, zoom, image, or background, and Escape is left to the parent.
  const CaptureCanvas.fullBleed({
    super.key,
    required this.ocrResult,
    this.onTextSelectionStarted,
    this.onObjectPoint,
    this.onObjectLoop,
    this.onLoopInterpreted,
    this.selectionTool = rect.SelectionTool.rectangle,
    this.onRectangleSelectionChanged,
    this.onRectangleSelectionFinished,
    this.focusNode,
    this.rectangleClearToken = 0,
    this.cursorScale = 1,
  }) : imagePath = null,
       fullBleed = true;

  final String? imagePath;
  final OcrResult ocrResult;
  final bool fullBleed;
  final VoidCallback? onTextSelectionStarted;
  final void Function(Point point, SelectionIntent intent)? onObjectPoint;
  final void Function(List<Point> stroke, LoopAsObjectIntent intent)?
  onObjectLoop;
  final void Function(List<Point> stroke, LoopInterpretation interpretation)?
  onLoopInterpreted;
  final rect.SelectionTool selectionTool;
  final void Function(rect.SelectionRect? rect)? onRectangleSelectionChanged;
  final void Function(rect.SelectionRect rect)? onRectangleSelectionFinished;
  final FocusNode? focusNode;

  /// Bump to drop the active rectangle (Escape from outside the canvas).
  final int rectangleClearToken;

  /// GNOME cursor-size scale for handles; 1 at the default size.
  final double cursorScale;

  @override
  ConsumerState<CaptureCanvas> createState() => _CaptureCanvasState();
}

class _CaptureCanvasState extends ConsumerState<CaptureCanvas>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformation = TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  late final FocusNode _ownedFocusNode = FocusNode(
    debugLabel: 'capture canvas',
  );
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;
  late final AnimationController _strokeFade;
  late final Animation<double> _strokeOpacity;
  Timer? _strokeClearTimer;
  double _zoom = _minZoom;
  int? _strokePointer;
  List<Point> _strokeSourcePoints = const [];
  List<Point> _strokeViewportPoints = const [];
  SelectionModifiers _strokeModifiers = const SelectionModifiers();
  bool _strokeStartedOnText = false;
  bool _textGestureStarted = false;
  bool _hoveringText = false;
  int? _rectanglePointer;
  Point? _rectangleStart;
  bool _rectangleStartedOnText = false;
  SelectionModifiers _rectangleModifiers = const SelectionModifiers();
  rect.RectangleSelection? _rectangleSelection;
  rect.TwoClickRectangleSession _twoClickSession =
      const rect.TwoClickRectangleSession();
  int? _twoClickPointer;
  Offset? _twoClickDown;
  OcrResult? _paragraphResult;
  List<TextParagraph> _paragraphGroups = const [];

  @override
  void initState() {
    super.initState();
    _transformation.addListener(_updateZoom);
    _strokeFade =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() {
              _strokeSourcePoints = const [];
              _strokeViewportPoints = const [];
            });
          }
        });
    _strokeOpacity = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(CurvedAnimation(parent: _strokeFade, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(CaptureCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rectangleClearToken != widget.rectangleClearToken) {
      _resetTwoClickRectangle(clearOverlay: false);
      setState(() => _rectangleSelection = null);
    } else if (oldWidget.selectionTool != widget.selectionTool) {
      _resetTwoClickRectangle();
    }
  }

  void _resetTwoClickRectangle({bool clearOverlay = true}) {
    _twoClickPointer = null;
    _twoClickDown = null;
    _twoClickSession = const rect.TwoClickRectangleSession();
    setState(() => _rectangleSelection = null);
    if (clearOverlay) {
      widget.onRectangleSelectionChanged?.call(null);
    }
  }

  @override
  void dispose() {
    _transformation
      ..removeListener(_updateZoom)
      ..dispose();
    _strokeClearTimer?.cancel();
    _strokeFade.dispose();
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _updateZoom() {
    final next = _transformation.value.getMaxScaleOnAxis();
    if ((next - _zoom).abs() > 0.001) {
      setState(() => _zoom = next);
    }
  }

  void _setZoom(double value) {
    final next = value.clamp(_minZoom, _maxZoom);
    _transformation.value = Matrix4.diagonal3Values(next, next, 1);
  }

  MotionPolicy _motionPolicy(BuildContext context) =>
      ref.watch(motionPolicyProvider(MediaQuery.disableAnimationsOf(context)));

  void _finishStrokeAnimation(BuildContext context) {
    if (_motionPolicy(context) == MotionPolicy.reduced) {
      _strokeClearTimer?.cancel();
      setState(() {
        _strokeSourcePoints = const [];
        _strokeViewportPoints = const [];
      });
    } else {
      _strokeFade.forward(from: 0);
      _strokeClearTimer?.cancel();
      _strokeClearTimer = Timer(_strokeFade.duration!, () {
        if (mounted) {
          setState(() {
            _strokeSourcePoints = const [];
            _strokeViewportPoints = const [];
          });
        }
      });
    }
  }

  bool _strokeLoopPreview() =>
      _strokeSourcePoints.length >= 3 &&
      _distance(_strokeSourcePoints.first, _strokeSourcePoints.last) < 28;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(regionSelectionProvider);
    final motion = _motionPolicy(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final fullBleed = widget.fullBleed;
        final imagePath = widget.imagePath;
        final padding = fullBleed
            ? 0.0
            : math.min(_canvasPadding, math.min(size.width, size.height) / 4);
        final geometry = FittedImageGeometry.contain(
          bounds: Rect.fromLTWH(
            padding,
            padding,
            math.max(0, size.width - 2 * padding),
            math.max(0, size.height - 2 * padding),
          ),
          imageSize: Size(
            widget.ocrResult.imageWidth.toDouble(),
            widget.ocrResult.imageHeight.toDouble(),
          ),
        );
        final characterHitTest = CharacterHitTest(selection.regions);
        final paragraphGroups = _paragraphsFor(
          widget.ocrResult,
          selection.regions,
        );

        // Larger boxes first so smaller ones stay on top and win overlaps.
        final targets = [...selection.regions]
          ..sort(
            (a, b) =>
                _area(geometry.hitRect(b))
                    .compareTo(_area(geometry.hitRect(a))),
          );

        Point sourcePoint(Offset globalPosition) {
          final renderBox =
              _viewportKey.currentContext!.findRenderObject()! as RenderBox;
          final viewportPoint = renderBox.globalToLocal(globalPosition);
          final scenePoint = _transformation.toScene(viewportPoint);
          return geometry.unmapPoint(scenePoint);
        }

        Offset scenePointFromViewport(Offset viewportPoint) =>
            _transformation.toScene(viewportPoint);

        Point sourcePointFromViewport(Offset viewportPoint) {
          return geometry.unmapPoint(scenePointFromViewport(viewportPoint));
        }

        bool isTextStart({required Point source, required Offset scene}) {
          if (characterHitTest.hit(source) != null) {
            return true;
          }
          return selection.regions.any(
            (region) =>
                region.ranges.isEmpty &&
                geometry.hitRect(region).contains(scene),
          );
        }

        final imageBounds = rect.SelectionRect(
          left: 0,
          top: 0,
          right: widget.ocrResult.imageWidth.toDouble(),
          bottom: widget.ocrResult.imageHeight.toDouble(),
        );

        void setRectangle(rect.RectangleSelection? rectSelection) {
          setState(() => _rectangleSelection = rectSelection);
          widget.onRectangleSelectionChanged?.call(rectSelection?.rect);
        }

        void finishRectangle(rect.RectangleSelection rectSelection) {
          if (!rectSelection.rect.isUsable) {
            setRectangle(null);
            return;
          }
          widget.onTextSelectionStarted?.call();
          ref.read(regionSelectionProvider.notifier).selectLineRanges({
            for (final region in widget.ocrResult.regions)
              if (_rectCoverage(rectSelection.rect, region) >= 0.60)
                region.id: (0, region.text.runes.length),
          });
          setRectangle(rectSelection);
          widget.onRectangleSelectionFinished?.call(rectSelection.rect);
        }

        void startRectangle(PointerDownEvent event) {
          final primary =
              event.buttons == 0 || event.buttons & kPrimaryButton != 0;
          if (!primary || _rectanglePointer != null) {
            return;
          }
          final scene = scenePointFromViewport(event.localPosition);
          final source = geometry.unmapPoint(scene);
          final modifiers = SelectionModifiers(
            shift: HardwareKeyboard.instance.isShiftPressed,
            alt: HardwareKeyboard.instance.isAltPressed,
            secondary: false,
            control: HardwareKeyboard.instance.isControlPressed,
          );
          final startsOnText = isTextStart(source: source, scene: scene);
          if (startsOnText && !modifiers.control) {
            return;
          }
          _focusNode.requestFocus();
          setState(() {
            _rectanglePointer = event.pointer;
            _rectangleStart = source;
            _rectangleStartedOnText = startsOnText;
            _rectangleModifiers = modifiers;
            _rectangleSelection = _rectangleFromPoints(source, source);
          });
          widget.onRectangleSelectionChanged?.call(_rectangleSelection?.rect);
        }

        void startFreehandStroke(PointerDownEvent event) {
          final primary =
              event.buttons == 0 || event.buttons & kPrimaryButton != 0;
          final secondary = event.buttons & kSecondaryMouseButton != 0;
          if ((!primary && !secondary) || _strokePointer != null) {
            return;
          }
          final scene = scenePointFromViewport(event.localPosition);
          final source = geometry.unmapPoint(scene);
          final modifiers = SelectionModifiers(
            shift: HardwareKeyboard.instance.isShiftPressed,
            alt: HardwareKeyboard.instance.isAltPressed,
            secondary: secondary,
            control: HardwareKeyboard.instance.isControlPressed,
          );
          final startsOnText = isTextStart(source: source, scene: scene);
          if (startsOnText && !modifiers.control) {
            return;
          }
          if (widget.selectionTool == rect.SelectionTool.rectangle &&
              !modifiers.control &&
              !secondary) {
            return;
          }
          _focusNode.requestFocus();
          _strokeClearTimer?.cancel();
          _strokeFade.stop();
          _strokeFade.value = 0;
          setState(() {
            _strokePointer = event.pointer;
            _strokeModifiers = modifiers;
            _strokeStartedOnText = startsOnText;
            _strokeSourcePoints = [source];
            _strokeViewportPoints = [_pointFromOffset(event.localPosition)];
          });
        }

        void addFreehandPoint(Offset position) {
          final source = sourcePointFromViewport(position);
          final viewport = _pointFromOffset(position);
          if (_strokeViewportPoints.isNotEmpty &&
              _distance(_strokeViewportPoints.last, viewport) < 1) {
            return;
          }
          setState(() {
            _strokeSourcePoints = [..._strokeSourcePoints, source];
            _strokeViewportPoints = [..._strokeViewportPoints, viewport];
          });
        }

        void announceTwoClick(String message) {
          ref.read(overlayAnnouncerProvider).announce(message, immediate: true);
        }

        void updateTwoClickPreview(Offset viewportPoint) {
          if (!_twoClickSession.awaitingSecondClick) {
            return;
          }
          final source = sourcePointFromViewport(viewportPoint);
          final preview = _twoClickSession.preview(
            rect.SelectionPoint(source.x, source.y),
          );
          if (preview != null) {
            setRectangle(preview);
          }
        }

        void startTwoClick(PointerDownEvent event) {
          final primary =
              event.buttons == 0 || event.buttons & kPrimaryButton != 0;
          if (!primary || _twoClickPointer != null) {
            return;
          }
          _focusNode.requestFocus();
          setState(() {
            _twoClickPointer = event.pointer;
            _twoClickDown = event.localPosition;
          });
        }

        void finishTwoClick(PointerUpEvent event) {
          if (event.pointer != _twoClickPointer) {
            return;
          }
          final down = _twoClickDown;
          _twoClickPointer = null;
          _twoClickDown = null;
          if (down == null) {
            return;
          }
          if ((down - event.localPosition).distance > _clickMovementTolerance) {
            return;
          }
          final source = sourcePointFromViewport(event.localPosition);
          final point = rect.SelectionPoint(source.x, source.y);
          final outcome = _twoClickSession.applyClick(point);
          final completed = outcome.selection;
          setState(() => _twoClickSession = outcome.session);
          if (completed != null) {
            if (!completed.rect.isUsable) {
              setRectangle(null);
              return;
            }
            finishRectangle(completed);
            announceTwoClick('Second corner set');
            return;
          }
          announceTwoClick(
            'First corner set. Move the pointer and click the opposite corner.',
          );
          updateTwoClickPreview(event.localPosition);
        }

        void updateFreehandStroke(PointerMoveEvent event) {
          if (widget.selectionTool == rect.SelectionTool.twoClicks &&
              event.pointer != _twoClickPointer) {
            updateTwoClickPreview(event.localPosition);
          }
          if (event.pointer == _rectanglePointer) {
            final start = _rectangleStart;
            if (start != null) {
              final source = sourcePointFromViewport(event.localPosition);
              setRectangle(_rectangleFromPoints(start, source));
            }
            return;
          }
          if (event.pointer != _strokePointer) {
            return;
          }
          addFreehandPoint(event.localPosition);
        }

        void finishFreehandStroke(PointerUpEvent event) {
          if (event.pointer == _rectanglePointer) {
            final start = _rectangleStart;
            final source = sourcePointFromViewport(event.localPosition);
            _rectanglePointer = null;
            _rectangleStart = null;
            if (start != null) {
              final selection = _rectangleFromPoints(start, source);
              if (!selection.rect.isUsable &&
                  fullBleed &&
                  widget.onObjectPoint != null) {
                final intent = classifyPointerDownIntent(
                  startsOnText: _rectangleStartedOnText,
                  modifiers: _rectangleModifiers,
                  isClick: true,
                );
                switch (intent) {
                  case ObjectClickIntent() ||
                      ObjectAddForegroundIntent() ||
                      ObjectAddBackgroundIntent():
                    widget.onObjectPoint?.call(source, intent);
                  case ClearSelectionIntent():
                    widget.onTextSelectionStarted?.call();
                    ref.read(regionSelectionProvider.notifier).clear();
                  default:
                    ref.read(regionSelectionProvider.notifier).clear();
                }
                setRectangle(null);
              } else {
                finishRectangle(selection);
              }
            }
            return;
          }
          if (event.pointer != _strokePointer) {
            return;
          }
          addFreehandPoint(event.localPosition);
          final sourceStroke = _strokeSourcePoints;
          final viewportStroke = _strokeViewportPoints;
          _strokePointer = null;
          final controller = ref.read(regionSelectionProvider.notifier);
          if (isUsableFreehandStroke(viewportStroke)) {
            if (!fullBleed || widget.onObjectLoop == null) {
              controller.selectLineRanges(
                selectCharacterRangesInsideStroke(
                  regions: selection.regions,
                  stroke: sourceStroke,
                  paragraphs: paragraphGroups,
                ),
              );
              _finishStrokeAnimation(context);
              return;
            }
            final textRanges = selectCharacterRangesInsideStroke(
              regions: selection.regions,
              stroke: sourceStroke,
              paragraphs: paragraphGroups,
            );
            if (!_strokeModifiers.control && textRanges.isNotEmpty) {
              widget.onTextSelectionStarted?.call();
              controller.selectLineRanges(textRanges);
              widget.onLoopInterpreted?.call(
                sourceStroke,
                LoopInterpretation.text,
              );
              _finishStrokeAnimation(context);
              return;
            }
            final intent = classifyLoopIntent(
              regions: selection.regions,
              stroke: sourceStroke,
              forceObject: _strokeModifiers.control,
            );
            switch (intent) {
              case LoopAsTextIntent():
                widget.onTextSelectionStarted?.call();
                controller.selectLineRanges(
                  selectCharacterRangesInsideStroke(
                    regions: selection.regions,
                    stroke: sourceStroke,
                    paragraphs: paragraphGroups,
                  ),
                );
                widget.onLoopInterpreted?.call(
                  sourceStroke,
                  LoopInterpretation.text,
                );
              case LoopAsObjectIntent():
                widget.onObjectLoop?.call(sourceStroke, intent);
                widget.onLoopInterpreted?.call(
                  sourceStroke,
                  LoopInterpretation.object,
                );
              default:
                break;
            }
          } else {
            if (!fullBleed || widget.onObjectPoint == null) {
              if (!_textGestureStarted) {
                controller.clear();
              }
              _textGestureStarted = false;
              _finishStrokeAnimation(context);
              return;
            }
            final intent = classifyPointerDownIntent(
              startsOnText: _strokeStartedOnText,
              modifiers: _strokeModifiers,
              isClick: true,
            );
            switch (intent) {
              case ObjectClickIntent() ||
                  ObjectAddForegroundIntent() ||
                  ObjectAddBackgroundIntent():
                widget.onObjectPoint?.call(sourceStroke.last, intent);
              case ClearSelectionIntent():
                widget.onTextSelectionStarted?.call();
                controller.clear();
              default:
                controller.clear();
            }
          }
          _finishStrokeAnimation(context);
        }

        void cancelFreehandStroke(PointerCancelEvent event) {
          if (event.pointer == _rectanglePointer) {
            setState(() {
              _rectanglePointer = null;
              _rectangleStart = null;
            });
            return;
          }
          if (event.pointer != _strokePointer) {
            return;
          }
          _strokeClearTimer?.cancel();
          setState(() {
            _strokePointer = null;
            _strokeSourcePoints = const [];
            _strokeViewportPoints = const [];
          });
        }

        void updateCursor(PointerHoverEvent event) {
          final scene = scenePointFromViewport(event.localPosition);
          final source = geometry.unmapPoint(scene);
          final hovering = isTextStart(source: source, scene: scene);
          if (hovering != _hoveringText) {
            setState(() => _hoveringText = hovering);
          }
          if (widget.selectionTool == rect.SelectionTool.twoClicks) {
            updateTwoClickPreview(event.localPosition);
          }
        }

        void tapCharacter(Offset globalPosition, int clickCount) {
          _focusNode.requestFocus();
          _textGestureStarted = true;
          final hit = characterHitTest.hit(sourcePoint(globalPosition));
          if (hit == null) {
            return;
          }
          final controller = ref.read(regionSelectionProvider.notifier);
          switch (clickCount) {
            case 2:
              widget.onTextSelectionStarted?.call();
              controller.selectWord(hit.region.id, hit.range.start);
            case 3:
              widget.onTextSelectionStarted?.call();
              controller.selectLineRanges(
                _paragraphLineRanges(hit.region.id, selection, paragraphGroups),
              );
            default:
              widget.onTextSelectionStarted?.call();
              controller.selectCharacter(hit.region.id, hit.range.start);
          }
        }

        bool startCharacterDrag(Offset globalPosition) {
          _focusNode.requestFocus();
          final hit = characterHitTest.hit(sourcePoint(globalPosition));
          if (hit == null) {
            return false;
          }
          _textGestureStarted = true;
          widget.onTextSelectionStarted?.call();
          ref.read(regionSelectionProvider.notifier).startAt(hit.position);
          return true;
        }

        void updateCharacterDrag(Offset globalPosition) {
          if (!selection.regions.any((region) => region.ranges.isNotEmpty)) {
            return;
          }
          final hit = characterHitTest.nearest(sourcePoint(globalPosition));
          ref
              .read(regionSelectionProvider.notifier)
              .extendToPosition(hit.position);
        }

        final selectionController = ref.read(regionSelectionProvider.notifier);

        return Focus(
          key: const Key('capture-canvas-focus'),
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final shift = HardwareKeyboard.instance.isShiftPressed;
            final control = HardwareKeyboard.instance.isControlPressed;
            final modifiedArrow =
                control ||
                HardwareKeyboard.instance.isAltPressed ||
                HardwareKeyboard.instance.isMetaPressed;
            final rectangle = _rectangleSelection;
            if (widget.selectionTool == rect.SelectionTool.rectangle &&
                rectangle != null) {
              final command = switch (event.logicalKey) {
                LogicalKeyboardKey.arrowLeft =>
                  rect.RectangleKeyboardCommand.arrowLeft,
                LogicalKeyboardKey.arrowRight =>
                  rect.RectangleKeyboardCommand.arrowRight,
                LogicalKeyboardKey.arrowUp =>
                  rect.RectangleKeyboardCommand.arrowUp,
                LogicalKeyboardKey.arrowDown =>
                  rect.RectangleKeyboardCommand.arrowDown,
                _ => null,
              };
              if (command != null) {
                final next = rectangle.applyKeyboard(
                  command,
                  modifiers: rect.RectangleKeyboardModifiers(
                    alt: HardwareKeyboard.instance.isAltPressed,
                    control: control,
                    shift: shift,
                  ),
                  bounds: imageBounds,
                );
                finishRectangle(next);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.keyR) {
                finishRectangle(rectangle.reset(imageBounds));
                return KeyEventResult.handled;
              }
            } else if (widget.selectionTool == rect.SelectionTool.rectangle &&
                event.logicalKey == LogicalKeyboardKey.keyR &&
                !control &&
                !HardwareKeyboard.instance.isAltPressed) {
              // Keyboard twin of dragging a rectangle: start one in the
              // middle of the display, then resize and move it with keys.
              final width = imageBounds.right;
              final height = imageBounds.bottom;
              finishRectangle(
                rect.RectangleSelection(
                  rect.SelectionRect(
                    left: width / 4,
                    top: height / 4,
                    right: width * 3 / 4,
                    bottom: height * 3 / 4,
                  ),
                ),
              );
              ref
                  .read(overlayAnnouncerProvider)
                  .announce(
                    'Rectangle started. Arrow keys resize, Alt plus arrow '
                    'keys move, Escape removes it.',
                    immediate: true,
                  );
              return KeyEventResult.handled;
            }
            switch (event.logicalKey) {
              case LogicalKeyboardKey.arrowDown when control && shift:
                selectionController.extendByParagraph(paragraphGroups, 1);
              case LogicalKeyboardKey.arrowUp when control && shift:
                selectionController.extendByParagraph(paragraphGroups, -1);
              case LogicalKeyboardKey.arrowLeft
                  when control && !HardwareKeyboard.instance.isAltPressed:
                selectionController.moveByWord(-1, extend: shift);
              case LogicalKeyboardKey.arrowRight
                  when control && !HardwareKeyboard.instance.isAltPressed:
                selectionController.moveByWord(1, extend: shift);
              case LogicalKeyboardKey.home when !modifiedArrow:
                selectionController.moveToLineEdge(end: false, extend: shift);
              case LogicalKeyboardKey.end when !modifiedArrow:
                selectionController.moveToLineEdge(end: true, extend: shift);
              case LogicalKeyboardKey.arrowLeft when !modifiedArrow:
                selectionController.moveHorizontal(-1, extend: shift);
              case LogicalKeyboardKey.arrowRight when !modifiedArrow:
                selectionController.moveHorizontal(1, extend: shift);
              case LogicalKeyboardKey.arrowUp when !modifiedArrow:
                selectionController.moveVertical(-1, extend: shift);
              case LogicalKeyboardKey.arrowDown when !modifiedArrow:
                selectionController.moveVertical(1, extend: shift);
              case LogicalKeyboardKey.keyA when control:
                widget.onTextSelectionStarted?.call();
                selectionController.selectAll();
              case LogicalKeyboardKey.keyC when control && !shift:
                if (ref.read(regionSelectionProvider).hasSelection) {
                  ref.read(copySelectionRequestProvider.notifier).request();
                } else {
                  return KeyEventResult.ignored;
                }
              case LogicalKeyboardKey.escape:
                if (fullBleed ||
                    !ref.read(regionSelectionProvider).hasSelection) {
                  return KeyEventResult.ignored;
                }
                selectionController.clear();
              default:
                return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: Semantics(
            container: true,
            label: 'Recognized text',
            hint:
                'Arrow keys select text. Ctrl+Shift+Down or Up selects whole '
                'paragraphs. Ctrl+A selects all. Ctrl+C copies.',
            value: selection.hasSelection
                ? '${selection.selectedText.runes.length} '
                      '${selection.selectedText.runes.length == 1 ? 'character' : 'characters'} '
                      'selected'
                : 'No text selected',
            child: ColoredBox(
              key: const Key('capture-canvas'),
              color: fullBleed ? Colors.transparent : AppColors.canvas,
              child: Stack(
                key: _viewportKey,
                fit: StackFit.expand,
                children: [
                  MouseRegion(
                    cursor: _hoveringText
                        ? SystemMouseCursors.text
                        : SystemMouseCursors.precise,
                    onHover: updateCursor,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: switch (widget.selectionTool) {
                        rect.SelectionTool.rectangle => (event) {
                          startRectangle(event);
                          startFreehandStroke(event);
                        },
                        rect.SelectionTool.twoClicks => startTwoClick,
                        rect.SelectionTool.freeDraw => startFreehandStroke,
                      },
                      onPointerMove: updateFreehandStroke,
                      onPointerUp: (event) {
                        finishTwoClick(event);
                        finishFreehandStroke(event);
                      },
                      onPointerCancel: cancelFreehandStroke,
                      child: InteractiveViewer(
                        transformationController: _transformation,
                        minScale: _minZoom,
                        maxScale: fullBleed ? _minZoom : _maxZoom,
                        scaleEnabled: !fullBleed,
                        panEnabled: _zoom > _minZoom && _strokePointer == null,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: fullBleed
                              ? ref.read(regionSelectionProvider.notifier).clear
                              : null,
                          excludeFromSemantics: true,
                          child: FocusTraversalGroup(
                            policy: OrderedTraversalPolicy(),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (imagePath != null &&
                                    !geometry.destination.isEmpty)
                                  Positioned.fromRect(
                                    rect: geometry.destination,
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0x66000000),
                                            blurRadius: 16,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: CaptureImage(
                                        key: const Key('capture-image'),
                                        imagePath: imagePath,
                                        label: 'Captured image',
                                      ),
                                    ),
                                  ),
                                if (!geometry.destination.isEmpty)
                                  for (final region in targets)
                                    if (region.ranges.isEmpty)
                                      Positioned.fromRect(
                                        key: Key('ocr-region-${region.id}'),
                                        rect: geometry.hitRect(region),
                                        child: RegionTarget(
                                          region: region,
                                          focusable: !fullBleed,
                                          readingIndex:
                                              selection.indexOf(region.id) ?? 0,
                                          polygon: [
                                            for (final point
                                                in geometry.regionPolygon(
                                                  region,
                                                ))
                                              point -
                                                  geometry
                                                      .hitRect(region)
                                                      .topLeft,
                                          ],
                                        ),
                                      ),
                                for (final region in targets)
                                  if (region.ranges.isNotEmpty)
                                    Positioned.fromRect(
                                      key: Key(
                                        'ocr-character-line-${region.id}',
                                      ),
                                      rect: geometry.hitRect(region),
                                      child: CharacterLineTarget(
                                        region: region,
                                        focusable: !fullBleed,
                                        readingIndex:
                                            selection.indexOf(region.id) ?? 0,
                                        linePolygon: [
                                          for (final point
                                              in geometry.regionPolygon(region))
                                            point -
                                                geometry
                                                    .hitRect(region)
                                                    .topLeft,
                                        ],
                                        polygons: [
                                          for (final range in region.ranges)
                                            [
                                              for (final point
                                                  in geometry.rangePolygon(
                                                    range,
                                                  ))
                                                point -
                                                    geometry
                                                        .hitRect(region)
                                                        .topLeft,
                                            ],
                                        ],
                                        onTap: tapCharacter,
                                        onDragStart: startCharacterDrag,
                                        onDragUpdate: updateCharacterDrag,
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_rectangleSelection != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const Key('rectangle-selection-overlay'),
                          painter: _RectangleSelectionPainter(
                            selection: _rectangleSelection!,
                            geometry: geometry,
                            transform: _transformation.value,
                          ),
                        ),
                      ),
                    ),
                  if (widget.selectionTool == rect.SelectionTool.twoClicks &&
                      _twoClickSession.firstCorner != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const Key('two-click-corner-marker'),
                          painter: _TwoClickCornerMarkerPainter(
                            corner: _twoClickSession.firstCorner!,
                            geometry: geometry,
                            transform: _transformation.value,
                            color: AppColors.neonMagenta,
                          ),
                        ),
                      ),
                    ),
                  if (fullBleed)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ListenableBuilder(
                          listenable: _focusNode,
                          builder: (context, _) => _CanvasFocusRing(
                            visible:
                                _focusNode.hasFocus &&
                                FocusManager.instance.highlightMode ==
                                    FocusHighlightMode.traditional,
                          ),
                        ),
                      ),
                    ),
                  if (_strokeSourcePoints.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _strokeOpacity,
                          builder: (context, _) {
                            return CustomPaint(
                              key: const Key('freehand-selection-stroke'),
                              painter: FreehandStrokePainter(
                                points: _strokeSourcePoints,
                                geometry: geometry,
                                transform: _transformation.value,
                                opacity: _strokePointer == null
                                    ? _strokeOpacity.value
                                    : 1,
                                color: AppColors.neonMagenta,
                                secondaryColor: AppColors.neonOrchid,
                                policy: motion,
                                closedLoop: _strokeLoopPreview(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  if (!fullBleed)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _ZoomControls(
                        zoom: _zoom,
                        onZoomOut: _zoom > _minZoom
                            ? () => _setZoom(_zoom - _zoomStep)
                            : null,
                        onReset: _zoom > _minZoom
                            ? () => _setZoom(_minZoom)
                            : null,
                        onZoomIn: _zoom < _maxZoom
                            ? () => _setZoom(_zoom + _zoomStep)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static double _area(Rect rect) => rect.width * rect.height;

  static Point _pointFromOffset(Offset offset) =>
      Point(x: offset.dx, y: offset.dy);

  static rect.RectangleSelection _rectangleFromPoints(Point start, Point end) =>
      rect.RectangleSelection.fromDrag(
        rect.SelectionPoint(start.x, start.y),
        rect.SelectionPoint(end.x, end.y),
      );

  static double _distance(Point first, Point second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _rectCoverage(rect.SelectionRect rect, TextRegion region) {
    final regionBounds = _sourceBounds(region.polygon);
    final left = math.max(rect.left, regionBounds.left);
    final top = math.max(rect.top, regionBounds.top);
    final right = math.min(rect.right, regionBounds.right);
    final bottom = math.min(rect.bottom, regionBounds.bottom);
    final intersection = math.max(0, right - left) * math.max(0, bottom - top);
    final area = regionBounds.width * regionBounds.height;
    return area <= 0 ? 0 : intersection / area;
  }

  static rect.SelectionRect _sourceBounds(List<Point> points) {
    if (points.isEmpty) {
      return const rect.SelectionRect(left: 0, top: 0, right: 0, bottom: 0);
    }
    var left = points.first.x;
    var top = points.first.y;
    var right = points.first.x;
    var bottom = points.first.y;
    for (final point in points.skip(1)) {
      left = math.min(left, point.x);
      top = math.min(top, point.y);
      right = math.max(right, point.x);
      bottom = math.max(bottom, point.y);
    }
    return rect.SelectionRect(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  List<TextParagraph> _paragraphsFor(
    OcrResult result,
    List<TextRegion> regions,
  ) {
    if (!identical(_paragraphResult, result)) {
      _paragraphResult = result;
      _paragraphGroups = groupTextParagraphs(regions);
    }
    return _paragraphGroups;
  }

  static Map<String, (int, int)> _paragraphLineRanges(
    String regionId,
    RegionSelection selection,
    List<TextParagraph> paragraphs,
  ) {
    final ids = paragraphs
        .firstWhere(
          (paragraph) => paragraph.regionIds.contains(regionId),
          orElse: () =>
              TextParagraph(regionIds: [regionId], totalCharacterCount: 0),
        )
        .regionIds;
    final regionById = {
      for (final region in selection.regions) region.id: region,
    };
    return {
      for (final id in ids)
        if (regionById[id] != null && regionById[id]!.text.runes.isNotEmpty)
          id: (0, regionById[id]!.text.runes.length),
    };
  }
}

class _RectangleSelectionPainter extends CustomPainter {
  const _RectangleSelectionPainter({
    required this.selection,
    required this.geometry,
    required this.transform,
  });

  final rect.RectangleSelection selection;
  final FittedImageGeometry geometry;
  final Matrix4 transform;

  @override
  void paint(Canvas canvas, Size size) {
    final source = selection.rect;
    final topLeft = MatrixUtils.transformPoint(
      transform,
      geometry.mapPoint(Point(x: source.left, y: source.top)),
    );
    final bottomRight = MatrixUtils.transformPoint(
      transform,
      geometry.mapPoint(Point(x: source.right, y: source.bottom)),
    );
    final drawnRect = Rect.fromPoints(topLeft, bottomRight);
    // A light tint inside, then a neon outline with a thin dark rim, so the
    // boundary shows on light and dark pixels and never relies on colour alone.
    canvas.drawRect(
      drawnRect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.neonMagenta.withValues(alpha: 0.08),
    );
    drawNeonOutlineRect(canvas, drawnRect);
  }

  @override
  bool shouldRepaint(covariant _RectangleSelectionPainter oldDelegate) =>
      oldDelegate.selection != selection ||
      oldDelegate.geometry != geometry ||
      oldDelegate.transform != transform;
}

class _TwoClickCornerMarkerPainter extends CustomPainter {
  const _TwoClickCornerMarkerPainter({
    required this.corner,
    required this.geometry,
    required this.transform,
    required this.color,
  });

  final rect.SelectionPoint corner;
  final FittedImageGeometry geometry;
  final Matrix4 transform;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = MatrixUtils.transformPoint(
      transform,
      geometry.mapPoint(Point(x: corner.x, y: corner.y)),
    );
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    canvas
      ..drawCircle(
        center,
        rect.twoClickCornerMarkerRadius + 1,
        Paint()..color = dualStrokeDark.withValues(alpha: 0.6),
      )
      ..drawCircle(center, rect.twoClickCornerMarkerRadius, fill);
  }

  @override
  bool shouldRepaint(covariant _TwoClickCornerMarkerPainter oldDelegate) =>
      oldDelegate.corner != corner ||
      oldDelegate.geometry != geometry ||
      oldDelegate.transform != transform ||
      oldDelegate.color != color;
}

/// A 2 px keyboard focus outline around the whole canvas, in a dark and a
/// light line so it shows on any screenshot.
class _CanvasFocusRing extends StatelessWidget {
  const _CanvasFocusRing({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      key: const Key('canvas-focus-ring'),
      painter: const _FocusRingPainter(),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final inset = AppA11y.focusRingWidth * 2;
    drawDualStrokeRect(
      canvas,
      (Offset.zero & size).deflate(inset),
      width: AppA11y.focusRingWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) => false;
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.zoom,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final double zoom;
  final VoidCallback? onZoomOut;
  final VoidCallback? onReset;
  final VoidCallback? onZoomIn;

  @override
  Widget build(BuildContext context) {
    const iconConstraints = BoxConstraints.tightFor(width: 36, height: 36);
    const iconPadding = EdgeInsets.zero;

    return Material(
      color: AppColors.aubergine.withValues(alpha: 0.94),
      elevation: 2,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('zoom-out'),
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            constraints: iconConstraints,
            padding: iconPadding,
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.remove, size: 18),
          ),
          TextButton(
            key: const Key('zoom-reset'),
            onPressed: onReset,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white70,
              minimumSize: const Size(54, 36),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              shape: const RoundedRectangleBorder(),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text('${(zoom * 100).round()}%'),
          ),
          IconButton(
            key: const Key('zoom-in'),
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            constraints: iconConstraints,
            padding: iconPadding,
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}
