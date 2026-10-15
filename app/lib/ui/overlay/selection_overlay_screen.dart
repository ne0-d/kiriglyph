import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/diagnostics/timing_log.dart';
import 'package:kiriglyph/export/subject_export.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/overlay/toolbar_placement.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/selection/freehand_selection_geometry.dart';
import 'package:kiriglyph/selection/paragraph_grouping.dart';
import 'package:kiriglyph/selection/region_selection.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';
import 'package:kiriglyph/selection/selection_intent.dart';
import 'package:kiriglyph/selection/subject_prompt_state.dart';
import 'package:kiriglyph/ui/overlay/overlay_effects.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar.dart';
import 'package:kiriglyph/ui/overlay/subject_overlay_layer.dart';
import 'package:kiriglyph/ui/workspace/capture_canvas.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

const _feedbackDuration = Duration(milliseconds: 2500);
const _copyFailedMessage = 'Could not copy. Try again.';
const _copyImageFailedMessage = 'Could not copy image. Try again.';
const _recognizingMessage = 'Recognizing text…';
const _preparingSubjectMessage = 'Preparing subject…';
const _exportTimeout = Duration(seconds: 20);

/// The selection overlay: the frozen display edge to edge, selectable once
/// OCR is ready. Paints nothing until the frame exists, so the window shows
/// the live desktop while it is being placed.
class SelectionOverlayScreen extends ConsumerStatefulWidget {
  const SelectionOverlayScreen({super.key});

  @override
  ConsumerState<SelectionOverlayScreen> createState() =>
      _SelectionOverlayScreenState();
}

/// What the toolbar status is saying; only transient states are live.
enum _StatusKind { hint, selection, busy, feedback, failure }

class _SelectionOverlayScreenState
    extends ConsumerState<SelectionOverlayScreen> {
  String? _feedback;
  Timer? _feedbackTimer;
  SubjectPromptState _subjectPrompt = const SubjectPromptState();
  SubjectPromptState? _pendingSubjectPrompt;
  Future<SubjectEmbedding>? _embeddingFuture;
  SubjectEmbedding? _embedding;
  SubjectMaskResult? _subjectMask;
  String? _subjectMessage;
  bool _subjectBusy = false;
  bool _exportBusy = false;
  int _exportSerial = 0;
  int _subjectSerial = 0;
  bool _restartAfterProcessDeath = false;
  Object? _paintedReadyFrame;
  Object? _paintedMask;
  List<Point>? _lastLoopStroke;
  LoopInterpretation? _lastLoopInterpretation;
  bool _objectCursorActive = false;
  Point? _objectCursor;

  // Captured in build so callbacks never look up inherited widgets.
  bool _announces = false;
  FlutterView? _view;
  TextDirection _direction = TextDirection.ltr;

  /// A concise status for screen readers where the platform supports
  /// announcements. Callers pass state and counts, never recognized text.
  /// Without announcement support the status text is a live region instead.
  void _announce(String message, {bool assertive = false}) {
    final view = _view;
    if (!_announces || view == null || message.isEmpty) {
      return;
    }
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        message,
        _direction,
        assertiveness: assertive
            ? Assertiveness.assertive
            : Assertiveness.polite,
      ),
    );
  }

  (OverlayPhase, String?, int?)? _announcedState;
  String? _announcedSubjectState;

  /// Announces each new overlay state once: recognizing, how many lines were
  /// found, or why nothing could be selected. States that pass between two
  /// frames are skipped. Selection changes are never announced.
  void _announceStateChange(SelectionOverlayState overlay) {
    final lineCount = overlay.ocrResult?.regions.length;
    final state = (overlay.phase, overlay.message, lineCount);
    if (state == _announcedState) {
      return;
    }
    _announcedState = state;
    final (message, assertive) = switch (overlay.phase) {
      OverlayPhase.recognizing => (_recognizingMessage, false),
      OverlayPhase.ready when lineCount == 0 => (noTextSubjectNotice, false),
      OverlayPhase.ready => (
        '${_lines(overlay.ocrResult?.regions.length ?? 0)} found',
        false,
      ),
      OverlayPhase.failed => (overlay.message ?? '', true),
      _ => ('', false),
    };
    if (message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _announce(message, assertive: assertive);
        }
      });
    }
  }

  void _announceSubject(String message, {bool assertive = false}) {
    if (message == _announcedSubjectState) {
      return;
    }
    _announcedSubjectState = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _announce(message, assertive: assertive);
      }
    });
  }

  @override
  void dispose() {
    _exportSerial++;
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _exportSerial++;
    setState(() => _exportBusy = false);
    unawaited(ref.read(selectionOverlayProvider.notifier).dismiss());
  }

  Future<void> _copy(String text, String successMessage) async {
    var message = successMessage;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      message = _copyFailedMessage;
    }
    _showFeedback(message, assertive: message == _copyFailedMessage);
  }

  void _showFeedback(String message, {bool assertive = false}) {
    if (!mounted) {
      return;
    }
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _announce(message, assertive: assertive);
    _feedbackTimer = Timer(_feedbackDuration, () {
      if (mounted) {
        setState(() => _feedback = null);
      }
    });
  }

  void _copySelection() {
    final selection = ref.read(regionSelectionProvider);
    if (selection.hasSelection) {
      _copy(
        selectedTextWithParagraphSeparators(
          selection,
          groupTextParagraphs(selection.regions),
        ),
        'Copied ${_selectionAmount(selection)}',
      );
    }
  }

  void _copyAll() {
    final selection = ref.read(regionSelectionProvider);
    if (selection.regions.isNotEmpty) {
      _copy(
        selection.allText,
        'Copied all ${_lines(selection.regions.length)}',
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final control = HardwareKeyboard.instance.isControlPressed;
    if (_objectCursorActive) {
      return _onObjectCursorKey(event);
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _dismiss();
      case LogicalKeyboardKey.keyC when control:
        if (ref.read(selectionOverlayProvider).activeSelection ==
            SelectionActiveKind.object) {
          _copySubjectImage();
        } else {
          _copySelection();
        }
      case LogicalKeyboardKey.keyS
          when control &&
              HardwareKeyboard.instance.isShiftPressed &&
              ref.read(selectionOverlayProvider).activeSelection ==
                  SelectionActiveKind.object:
        _saveSubjectPng(saveAs: true);
      case LogicalKeyboardKey.keyS
          when control &&
              ref.read(selectionOverlayProvider).activeSelection ==
                  SelectionActiveKind.object:
        _saveSubjectPng();
      case LogicalKeyboardKey.keyA when control:
        _activateTextSelection();
        ref.read(regionSelectionProvider.notifier).selectAll();
      case LogicalKeyboardKey.keyO when !control:
        _enterObjectCursor();
      case LogicalKeyboardKey.keyZ
          when control &&
              ref.read(selectionOverlayProvider).activeSelection ==
                  SelectionActiveKind.object:
        _applySubjectPrompt(_subjectPrompt.undo());
      case LogicalKeyboardKey.backspace || LogicalKeyboardKey.delete
          when ref.read(selectionOverlayProvider).activeSelection ==
              SelectionActiveKind.object:
        _clearSubject();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onObjectCursorKey(KeyDownEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        setState(() => _objectCursorActive = false);
      case LogicalKeyboardKey.enter:
        final point = _objectCursor;
        if (point != null) {
          final intent = HardwareKeyboard.instance.isAltPressed
              ? const ObjectAddBackgroundIntent()
              : HardwareKeyboard.instance.isShiftPressed
              ? const ObjectAddForegroundIntent()
              : const ObjectClickIntent();
          _applyObjectPoint(point, intent);
        }
        setState(() => _objectCursorActive = false);
      case LogicalKeyboardKey.arrowLeft:
        _moveObjectCursor(-1, 0);
      case LogicalKeyboardKey.arrowRight:
        _moveObjectCursor(1, 0);
      case LogicalKeyboardKey.arrowUp:
        _moveObjectCursor(0, -1);
      case LogicalKeyboardKey.arrowDown:
        _moveObjectCursor(0, 1);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final overlay = ref.watch(selectionOverlayProvider);
    final selection = ref.watch(regionSelectionProvider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _announces = MediaQuery.supportsAnnounceOf(context);
    _view = View.maybeOf(context);
    _direction = Directionality.of(context);
    _announceStateChange(overlay);
    ref.listen(copySelectionRequestProvider, (previous, next) {
      if (next != previous) {
        _copySelection();
      }
    });

    final frame = overlay.frame;
    final result = overlay.ocrResult;
    final noTextReady =
        overlay.phase == OverlayPhase.ready &&
        result != null &&
        result.regions.isEmpty;
    if (overlay.phase == OverlayPhase.ready &&
        frame != null &&
        !identical(_paintedReadyFrame, frame)) {
      _paintedReadyFrame = frame;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(timingLogProvider).mark(TimingPhase.firstPaint);
        }
      });
    }
    _syncEmbedding(overlay);
    final (kind, status) = switch ((_feedback, overlay.message)) {
      (final feedback?, _) => (_StatusKind.feedback, feedback),
      (_, final message?) => (_StatusKind.failure, message),
      _ when overlay.activeSelection == SelectionActiveKind.object =>
        _subjectStatus(),
      _ when noTextReady => (_StatusKind.feedback, noTextSubjectNotice),
      _ => switch (overlay.phase) {
        OverlayPhase.recognizing => (_StatusKind.busy, _recognizingMessage),
        OverlayPhase.ready when selection.hasSelection => (
          _StatusKind.selection,
          '${_selectionAmount(selection)} selected',
        ),
        OverlayPhase.ready => (
          _StatusKind.hint,
          result == null || result.regions.isEmpty
              ? 'Click or draw around an object'
              : 'Drag across text, or click an object',
        ),
        _ => (_StatusKind.hint, ''),
      },
    };
    final showToolbar =
        overlay.phase == OverlayPhase.recognizing ||
        overlay.phase == OverlayPhase.ready ||
        overlay.phase == OverlayPhase.failed;

    return Material(
      type: MaterialType.transparency,
      child: FocusScope(
        autofocus: true,
        onKeyEvent: _onKey,
        // Tab visits the canvas, Copy, Copy all, then Close.
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final geometry = frame == null
                  ? null
                  : FittedImageGeometry.contain(
                      bounds: Offset.zero & size,
                      imageSize: Size(
                        frame.width.toDouble(),
                        frame.height.toDouble(),
                      ),
                    );
              final obstacles = [
                if (geometry != null && result != null)
                  for (final region in result.regions)
                    geometry.regionRect(region),
              ];
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (frame != null && geometry != null)
                    Positioned.fromRect(
                      rect: geometry.destination,
                      // The screenshot itself is silent for screen readers; the
                      // recognized text below carries its content.
                      child: ExcludeSemantics(
                        child: _FrozenFrame(frame: frame),
                      ),
                    ),
                  if (frame != null && geometry != null && _subjectMask != null)
                    Positioned.fill(
                      child: Semantics(
                        key: const Key('subject-overlay-layer'),
                        container: true,
                        label: 'Subject selection',
                        value: _subjectValue(_subjectMask),
                        child: SubjectMaskImage(
                          result: _subjectMask,
                          builder: (context, image) => image == null
                              ? const SizedBox.shrink()
                              : IgnorePointer(
                                  child: CustomPaint(
                                    key: const Key('subject-mask-paint'),
                                    painter: SubjectMaskPainter(
                                      mask: image.image,
                                      geometry: geometry,
                                      result: _subjectMask!,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      dimSubject: _subjectBusy,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  if (result != null)
                    Positioned.fill(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: CaptureCanvas.fullBleed(
                          ocrResult: result,
                          onTextSelectionStarted: _activateTextSelection,
                          onObjectPoint: _applyObjectPoint,
                          onObjectLoop: _applyObjectLoop,
                          onLoopInterpreted: _recordLoopInterpretation,
                        ),
                      ),
                    ),
                  if (frame != null && !reduceMotion)
                    EntryGlow(key: ObjectKey(frame)),
                  if (overlay.phase == OverlayPhase.recognizing &&
                      !reduceMotion)
                    const ScanSweep(),
                  if (_objectCursorActive &&
                      _objectCursor != null &&
                      geometry != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const Key('object-keyboard-cursor'),
                          painter: _ObjectCursorPainter(
                            position: geometry.mapPoint(_objectCursor!),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  if (_showLoopHint(geometry))
                    CustomSingleChildLayout(
                      delegate: _SubjectChipLayout(
                        subject: _loopBoundsInView(geometry!),
                        screen: size,
                        textScale: MediaQuery.textScalerOf(context).scale(1),
                      ),
                      child: LoopHintChip(
                        selectedAsText:
                            _lastLoopInterpretation == LoopInterpretation.text,
                        onFlip: () => _flipLastLoop(result!),
                      ),
                    ),
                  if (_showSubjectChip(geometry))
                    CustomSingleChildLayout(
                      delegate: _SubjectChipLayout(
                        subject: _subjectBoundsInView(geometry!),
                        screen: size,
                        textScale: MediaQuery.textScalerOf(context).scale(1),
                      ),
                      child: SubjectActionChip(
                        status: _subjectMessage,
                        exporting: _exportBusy,
                        onCopy: _canExportSubject ? _copySubjectImage : null,
                        onSave: _canExportSubject ? _saveSubjectPng : null,
                        onRemove: _clearSubject,
                      ),
                    ),
                  if (showToolbar)
                    CustomSingleChildLayout(
                      delegate: _ToolbarLayout(obstacles),
                      child: OverlayToolbar(
                        status: status,
                        statusIsLive:
                            !_announces &&
                            kind != _StatusKind.hint &&
                            kind != _StatusKind.selection,
                        onCopy: selection.hasSelection ? _copySelection : null,
                        onCopyAll: selection.regions.isEmpty ? null : _copyAll,
                        copyTooltipMessage: noTextReady
                            ? 'No text found to copy'
                            : null,
                        copyAllTooltipMessage: noTextReady
                            ? 'No recognized text to copy'
                            : null,
                        onClose: _dismiss,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _lines(int count) => count == 1 ? '1 line' : '$count lines';

  static String _selectionAmount(RegionSelection selection) {
    final lines = selection.selectedRegions.length;
    if (lines > 0) {
      return _lines(lines);
    }
    final characters = selection.selectedCharacterCount;
    return characters == 1 ? '1 character' : '$characters characters';
  }

  static String _subjectValue(SubjectMaskResult? result) {
    if (result == null ||
        result.stats.outcome != SubjectMaskOutcome.ok ||
        result.stats.areaFraction <= 0) {
      return 'No subject selected';
    }
    final percent = (result.stats.areaFraction * 100).round();
    return 'Subject selected, covers $percent percent of the screen';
  }

  (_StatusKind, String) _subjectStatus() {
    if (_exportBusy) {
      return (_StatusKind.busy, 'Exporting subject…');
    }
    if (_subjectBusy) {
      return (_StatusKind.busy, 'Finding subject…');
    }
    if (_embedding == null) {
      return (_StatusKind.busy, _preparingSubjectMessage);
    }
    if (_canExportSubject) {
      return (_StatusKind.hint, 'Click or draw around another subject');
    }
    final message = _subjectMessage;
    if (message != null) {
      return (_StatusKind.feedback, message);
    }
    return (_StatusKind.hint, 'Click or draw around a subject');
  }

  bool get _canExportSubject {
    final mask = _subjectMask;
    return !_subjectBusy &&
        !_exportBusy &&
        mask != null &&
        mask.stats.outcome == SubjectMaskOutcome.ok &&
        ref.read(selectionOverlayProvider).subjectImagePath != null;
  }

  void _activateTextSelection() {
    final overlay = ref.read(selectionOverlayProvider);
    if (overlay.activeSelection == SelectionActiveKind.object ||
        _subjectMask != null ||
        _subjectBusy) {
      _clearSubject(updateActiveSelection: false);
    }
    setState(() {
      _lastLoopStroke = null;
      _lastLoopInterpretation = null;
    });
    ref
        .read(selectionOverlayProvider.notifier)
        .setActiveSelection(SelectionActiveKind.text);
  }

  void _activateObjectSelection() {
    ref.read(regionSelectionProvider.notifier).clear();
    setState(() {
      _lastLoopStroke = null;
      _lastLoopInterpretation = null;
    });
    ref
        .read(selectionOverlayProvider.notifier)
        .setActiveSelection(SelectionActiveKind.object);
  }

  void _enterObjectCursor() {
    final frame = ref.read(selectionOverlayProvider).frame;
    if (frame == null) {
      return;
    }
    setState(() {
      _objectCursorActive = true;
      _objectCursor ??= Point(x: frame.width / 2, y: frame.height / 2);
    });
    _announceSubject('Object cursor. Use arrow keys, then Enter.');
  }

  void _moveObjectCursor(int dx, int dy) {
    final frame = ref.read(selectionOverlayProvider).frame;
    final current = _objectCursor;
    if (frame == null || current == null) {
      return;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 24.0 : 6.0;
    setState(() {
      _objectCursor = Point(
        x: (current.x + dx * step).clamp(0, frame.width.toDouble()),
        y: (current.y + dy * step).clamp(0, frame.height.toDouble()),
      );
    });
  }

  void _applyObjectPoint(Point point, SelectionIntent intent) {
    _activateObjectSelection();
    setState(() {
      _lastLoopStroke = null;
      _lastLoopInterpretation = null;
    });
    final promptPoint = SubjectPromptPoint(point.x, point.y);
    final next = switch (intent) {
      ObjectAddForegroundIntent() => _subjectPrompt.addForeground(promptPoint),
      ObjectAddBackgroundIntent() => _subjectPrompt.addBackground(promptPoint),
      _ => _subjectPrompt.replacePoint(promptPoint),
    };
    _applySubjectPrompt(next);
  }

  void _applyObjectLoop(List<Point> stroke, LoopAsObjectIntent intent) {
    _activateObjectSelection();
    _applySubjectPrompt(
      _subjectPrompt.replaceRegion([
        for (final point in stroke) SubjectPromptPoint(point.x, point.y),
      ]),
    );
  }

  void _recordLoopInterpretation(
    List<Point> stroke,
    LoopInterpretation interpretation,
  ) {
    setState(() {
      _lastLoopStroke = List<Point>.unmodifiable(stroke);
      _lastLoopInterpretation = interpretation;
    });
  }

  bool _showSubjectChip(FittedImageGeometry? geometry) {
    final mask = _subjectMask;
    return geometry != null &&
        mask != null &&
        mask.stats.outcome == SubjectMaskOutcome.ok &&
        !_subjectBusy;
  }

  bool _showLoopHint(FittedImageGeometry? geometry) =>
      geometry != null &&
      _lastLoopStroke != null &&
      _lastLoopInterpretation != null;

  void _flipLastLoop(OcrResult result) {
    final stroke = _lastLoopStroke;
    final interpretation = _lastLoopInterpretation;
    if (stroke == null || interpretation == null) {
      return;
    }
    if (interpretation == LoopInterpretation.text) {
      _applyObjectLoop(
        stroke,
        LoopAsObjectIntent(
          classifyLoop(regions: result.regions, stroke: stroke),
        ),
      );
      _recordLoopInterpretation(stroke, LoopInterpretation.object);
      _announceSubject('Selected as image');
      return;
    }
    _activateTextSelection();
    ref
        .read(regionSelectionProvider.notifier)
        .selectLineRanges(
          selectCharacterRangesInsideStroke(
            regions: result.regions,
            stroke: stroke,
            paragraphs: groupTextParagraphs(result.regions),
          ),
        );
    _recordLoopInterpretation(stroke, LoopInterpretation.text);
    _announceSubject('Selected as text');
  }

  Rect _subjectBoundsInView(FittedImageGeometry geometry) {
    final mask = _subjectMask;
    final bounds = mask?.stats.bounds ?? mask?.bounds;
    if (bounds == null) {
      return geometry.destination;
    }
    final leftTop = geometry.mapPoint(
      Point(x: bounds.x.toDouble(), y: bounds.y.toDouble()),
    );
    final rightBottom = geometry.mapPoint(
      Point(
        x: (bounds.x + bounds.width).toDouble(),
        y: (bounds.y + bounds.height).toDouble(),
      ),
    );
    return Rect.fromPoints(leftTop, rightBottom);
  }

  Rect _loopBoundsInView(FittedImageGeometry geometry) {
    final stroke = _lastLoopStroke;
    if (stroke == null || stroke.isEmpty) {
      return geometry.destination;
    }
    var left = stroke.first.x;
    var right = left;
    var top = stroke.first.y;
    var bottom = top;
    for (final point in stroke.skip(1)) {
      left = left < point.x ? left : point.x;
      right = right > point.x ? right : point.x;
      top = top < point.y ? top : point.y;
      bottom = bottom > point.y ? bottom : point.y;
    }
    final leftTop = geometry.mapPoint(Point(x: left, y: top));
    final rightBottom = geometry.mapPoint(Point(x: right, y: bottom));
    return Rect.fromPoints(leftTop, rightBottom);
  }

  Future<void> _copySubjectImage() async {
    final mask = _subjectMask;
    final sourcePath = ref.read(selectionOverlayProvider).subjectImagePath;
    if (mask == null || sourcePath == null || _exportBusy) {
      return;
    }
    final serial = ++_exportSerial;
    setState(() => _exportBusy = true);
    late final SubjectExportOutcome outcome;
    try {
      outcome = await ref
          .read(subjectExportControllerProvider)
          .copy(sourceImagePath: sourcePath, mask: mask)
          .timeout(_exportTimeout);
    } on TimeoutException {
      outcome = const SubjectExportOutcome(
        SubjectExportOutcomeKind.clipboardFailure,
      );
    } finally {
      if (mounted && serial == _exportSerial) {
        setState(() => _exportBusy = false);
      }
    }
    if (!mounted || serial != _exportSerial) {
      return;
    }
    final (message, assertive) = switch (outcome.kind) {
      SubjectExportOutcomeKind.copied => ('Copied image', false),
      SubjectExportOutcomeKind.clipboardFailure => (
        _copyImageFailedMessage,
        true,
      ),
      SubjectExportOutcomeKind.encoderFailure => (
        'Could not prepare the image. Try again.',
        true,
      ),
      SubjectExportOutcomeKind.invalidMask => (
        'Select a subject before exporting.',
        true,
      ),
      _ => ('Could not copy image. Try again.', true),
    };
    if (outcome.kind == SubjectExportOutcomeKind.copied) {
      ref.read(timingLogProvider).finish(TimingOutcome.copied);
    }
    _showFeedback(message, assertive: assertive);
  }

  Future<void> _saveSubjectPng({bool saveAs = false}) async {
    final mask = _subjectMask;
    final sourcePath = ref.read(selectionOverlayProvider).subjectImagePath;
    if (mask == null || sourcePath == null || _exportBusy) {
      return;
    }
    final serial = ++_exportSerial;
    setState(() => _exportBusy = true);
    final overlay = ref.read(selectionOverlayProvider.notifier);
    if (saveAs) {
      await overlay.beginExportInteraction();
    }
    late final SubjectExportOutcome outcome;
    try {
      final controller = ref.read(subjectExportControllerProvider);
      outcome =
          await (saveAs
                  ? controller.saveAs(sourceImagePath: sourcePath, mask: mask)
                  : controller.save(sourceImagePath: sourcePath, mask: mask))
              .timeout(_exportTimeout);
    } on TimeoutException {
      outcome = const SubjectExportOutcome(
        SubjectExportOutcomeKind.unwritableDestination,
      );
    } finally {
      if (saveAs) {
        await overlay.completeExportInteraction(dismissOverlay: false);
      }
      if (mounted && serial == _exportSerial) {
        setState(() => _exportBusy = false);
      }
    }
    if (!mounted || serial != _exportSerial) {
      return;
    }
    if (outcome.kind == SubjectExportOutcomeKind.saved) {
      ref.read(timingLogProvider).finish(TimingOutcome.saved);
    } else if (outcome.kind == SubjectExportOutcomeKind.cancelled) {
      ref.read(timingLogProvider).finish(TimingOutcome.cancelled);
    }
    final message = switch (outcome.kind) {
      SubjectExportOutcomeKind.saved =>
        'Saved to Pictures/${outcome.savedName ?? 'image.png'}',
      SubjectExportOutcomeKind.cancelled => null,
      SubjectExportOutcomeKind.overwriteDeclined => 'Save cancelled',
      SubjectExportOutcomeKind.unwritableDestination =>
        'Could not save PNG there.',
      SubjectExportOutcomeKind.encoderFailure =>
        'Could not prepare the image. Try again.',
      SubjectExportOutcomeKind.invalidMask => 'Select a subject before saving.',
      _ => 'Could not save PNG. Try again.',
    };
    if (message != null) {
      _showFeedback(message, assertive: true);
    }
  }

  void _syncEmbedding(SelectionOverlayState overlay) {
    final future = overlay.subjectEmbedding;
    if (future == null || identical(future, _embeddingFuture)) {
      return;
    }
    _embeddingFuture = future;
    _embedding = null;
    future
        .then((embedding) {
          if (!mounted || !identical(future, _embeddingFuture)) {
            return;
          }
          setState(() => _embedding = embedding);
          ref.read(timingLogProvider).mark(TimingPhase.embed);
          final pending = _pendingSubjectPrompt;
          _pendingSubjectPrompt = null;
          if (pending != null) {
            _applySubjectPrompt(pending);
          }
        })
        .catchError((Object error) {
          if (!mounted || !identical(future, _embeddingFuture)) {
            return;
          }
          setState(() => _subjectMessage = _failureMessage(error));
          _announceSubject(_subjectMessage!, assertive: true);
        });
  }

  void _applySubjectPrompt(SubjectPromptState prompt) {
    setState(() {
      _subjectPrompt = prompt;
      _subjectMessage = null;
    });
    final embedding = _embedding;
    if (embedding == null) {
      if (_embeddingFuture == null) {
        final imagePath = ref.read(selectionOverlayProvider).subjectImagePath;
        if (imagePath != null) {
          ref.invalidate(subjectSegmenterProvider);
          final embedding = ref.read(subjectSegmenterProvider).embed(imagePath);
          embedding.ignore();
          _syncEmbedding(SelectionOverlayState(subjectEmbedding: embedding));
        }
      }
      setState(() => _pendingSubjectPrompt = prompt);
      _announceSubject(_preparingSubjectMessage);
      return;
    }
    _requestSubjectMask(prompt, embedding);
  }

  void _clearSubject({bool updateActiveSelection = true}) {
    _subjectSerial++;
    unawaited(ref.read(subjectSegmenterProvider).cancelActive());
    setState(() {
      _subjectPrompt = _subjectPrompt.clear();
      _pendingSubjectPrompt = null;
      _subjectMask = null;
      _subjectMessage = null;
      _subjectBusy = false;
      _lastLoopStroke = null;
      _lastLoopInterpretation = null;
    });
    if (updateActiveSelection) {
      ref
          .read(selectionOverlayProvider.notifier)
          .setActiveSelection(SelectionActiveKind.none);
    }
  }

  Future<void> _requestSubjectMask(
    SubjectPromptState prompt,
    SubjectEmbedding embedding,
  ) async {
    final serial = ++_subjectSerial;
    final segmenter = ref.read(subjectSegmenterProvider);
    unawaited(segmenter.cancelActive());
    setState(() => _subjectBusy = true);
    try {
      final result = await segmenter.prompt(embedding, prompt.prompt);
      if (!mounted || serial != _subjectSerial) {
        return;
      }
      ref.read(timingLogProvider).mark(TimingPhase.prompt);
      final message = _messageForResult(result);
      setState(() {
        _subjectBusy = false;
        _subjectMessage = message;
        _subjectMask =
            result.stats.outcome == SubjectMaskOutcome.suspectFullImage
            ? null
            : result;
      });
      final mask = _subjectMask;
      if (mask != null && !identical(_paintedMask, mask)) {
        _paintedMask = mask;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(timingLogProvider).mark(TimingPhase.maskRender);
          }
        });
      }
      _announceSubject(message ?? 'Subject found');
    } catch (error) {
      if (!mounted || serial != _subjectSerial) {
        return;
      }
      final message = _failureMessage(error);
      if (message.isEmpty) {
        setState(() => _subjectBusy = false);
        return;
      }
      setState(() {
        _subjectBusy = false;
        _subjectMask = null;
        _subjectMessage = message;
      });
      _announceSubject(message, assertive: true);
      if (error is SubjectSegmentationException &&
          error.kind == SubjectFailureKind.processDied &&
          !_restartAfterProcessDeath) {
        _restartAfterProcessDeath = true;
        _embedding = null;
        _embeddingFuture = null;
      }
    }
  }

  String? _messageForResult(SubjectMaskResult result) {
    switch (result.stats.outcome) {
      case SubjectMaskOutcome.empty:
        return 'No subject found here';
      case SubjectMaskOutcome.suspectFullImage:
        return 'That selected almost the whole screen — try clicking closer to the subject or drawing around it';
      case SubjectMaskOutcome.ok:
        if (result.stats.touchesEdge.any) {
          return 'Subject touches the screen edge';
        }
        final count = result.stats.components.count;
        if (count > 1) {
          return '$count separate pieces';
        }
        return null;
    }
  }

  String _failureMessage(Object error) {
    if (error is SubjectSegmentationException) {
      return switch (error.kind) {
        SubjectFailureKind.cancelled || SubjectFailureKind.sessionClosed => '',
        SubjectFailureKind.modelMissing =>
          'Subject model is not installed. Run ${error.command ?? 'kiriglyph-fetch-models'}.',
        SubjectFailureKind.modelLoadFailed =>
          'Subject model could not be loaded. Try again.',
        SubjectFailureKind.outOfMemory =>
          'Not enough memory to find a subject. Try again after closing apps.',
        SubjectFailureKind.malformedOutput =>
          'Subject worker returned an invalid response. Try again.',
        SubjectFailureKind.processDied =>
          'Subject worker stopped. Click again to retry.',
        SubjectFailureKind.timeout =>
          'Finding the subject took too long. Try again.',
      };
    }
    return 'Could not find a subject. Try again.';
  }
}

/// Draws the frame without smoothing when its pixels map 1:1 onto the
/// window's buffer, so the frozen display matches the live one exactly.
class _FrozenFrame extends StatelessWidget {
  const _FrozenFrame({required this.frame});

  final OverlayFrame frame;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final exact =
            (constraints.maxWidth * ratio).round() == frame.width &&
            (constraints.maxHeight * ratio).round() == frame.height;
        return RawImage(
          key: const Key('overlay-frame'),
          image: frame.image,
          fit: BoxFit.fill,
          filterQuality: exact ? FilterQuality.none : FilterQuality.medium,
        );
      },
    );
  }
}

class _ToolbarLayout extends SingleChildLayoutDelegate {
  const _ToolbarLayout(this.obstacles);

  final List<Rect> obstacles;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => placeOverlayToolbar(
    screen: size,
    toolbar: childSize,
    obstacles: obstacles,
  );

  @override
  bool shouldRelayout(covariant _ToolbarLayout oldDelegate) =>
      !_sameRects(oldDelegate.obstacles, obstacles);

  static bool _sameRects(List<Rect> first, List<Rect> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}

class _SubjectChipLayout extends SingleChildLayoutDelegate {
  const _SubjectChipLayout({
    required this.subject,
    required this.screen,
    required this.textScale,
  });

  final Rect subject;
  final Size screen;
  final double textScale;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const margin = 16.0;
    const gap = 10.0;
    final toolbarReserve = 72.0 * textScale.clamp(1.0, 2.0);
    final maxLeft = (screen.width - childSize.width - margin).clamp(
      margin,
      double.infinity,
    );
    final maxTop = (screen.height - childSize.height - toolbarReserve).clamp(
      margin,
      double.infinity,
    );
    Offset clamp(Offset offset) => Offset(
      offset.dx.clamp(margin, maxLeft),
      offset.dy.clamp(margin, maxTop),
    );

    final below = Offset(
      subject.center.dx - childSize.width / 2,
      subject.bottom + gap,
    );
    if (below.dy + childSize.height <= maxTop) {
      return clamp(below);
    }
    final above = Offset(
      subject.center.dx - childSize.width / 2,
      subject.top - childSize.height - gap,
    );
    if (above.dy >= margin) {
      return clamp(above);
    }
    return clamp(Offset(subject.center.dx - childSize.width / 2, maxTop));
  }

  @override
  bool shouldRelayout(covariant _SubjectChipLayout oldDelegate) =>
      oldDelegate.subject != subject ||
      oldDelegate.screen != screen ||
      oldDelegate.textScale != textScale;
}

class _ObjectCursorPainter extends CustomPainter {
  const _ObjectCursorPainter({required this.position, required this.color});

  final Offset position;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas
      ..drawCircle(position, 10, paint)
      ..drawLine(position.translate(-18, 0), position.translate(-6, 0), paint)
      ..drawLine(position.translate(6, 0), position.translate(18, 0), paint)
      ..drawLine(position.translate(0, -18), position.translate(0, -6), paint)
      ..drawLine(position.translate(0, 6), position.translate(0, 18), paint);
  }

  @override
  bool shouldRepaint(covariant _ObjectCursorPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.color != color;
}
