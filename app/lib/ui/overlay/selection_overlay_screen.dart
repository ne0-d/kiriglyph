import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/a11y/cursor_size.dart';
import 'package:kiriglyph/a11y/dual_stroke.dart';
import 'package:kiriglyph/a11y/object_candidates.dart';
import 'package:kiriglyph/a11y/overlay_announcer.dart';
import 'package:kiriglyph/diagnostics/timing_log.dart';
import 'package:kiriglyph/detection/text_detectors.dart';
import 'package:kiriglyph/export/screenshot_export.dart';
import 'package:kiriglyph/export/subject_export.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/overlay/toolbar_placement.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/selection/freehand_selection_geometry.dart';
import 'package:kiriglyph/selection/paragraph_grouping.dart';
import 'package:kiriglyph/selection/region_selection.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart' as rect;
import 'package:kiriglyph/selection/selection_intent.dart';
import 'package:kiriglyph/selection/subject_prompt_state.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/overlay/action_feedback.dart';
import 'package:kiriglyph/ui/motion/app_motion.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';
import 'package:kiriglyph/ui/overlay/keyboard_help_panel.dart';
import 'package:kiriglyph/ui/overlay/overlay_effects.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar_host.dart';
import 'package:kiriglyph/ui/overlay/persistent_edge_glow.dart';
import 'package:kiriglyph/ui/overlay/subject_overlay_layer.dart';
import 'package:kiriglyph/ui/workspace/capture_canvas.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

const _feedbackDuration = Duration(milliseconds: 2500);
const _copyFailedMessage = 'Could not copy. Try again.';
const _copyImageFailedMessage = 'Could not copy image. Try again.';
const _recognizingMessage = 'Recognizing text…';
const _preparingSubjectMessage = 'Preparing subject…';
const _exportTimeout = Duration(seconds: 20);
const _helpHint = 'press question mark for help';

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
  final FocusNode _canvasFocusNode = FocusNode(debugLabel: 'overlay canvas');
  final FocusNode _closeFocusNode = FocusNode(debugLabel: 'overlay close');
  final FocusNode _toolbarFocusNode = FocusNode(debugLabel: 'overlay toolbar');
  final FocusNode _copyFocusNode = FocusNode(debugLabel: 'overlay copy');
  final FocusNode _copyAllFocusNode = FocusNode(debugLabel: 'overlay copy all');
  bool _helpOpen = false;
  int? _objectIndex;
  int _rectangleClearToken = 0;
  String? _feedback;
  Timer? _feedbackTimer;
  final ActionFeedbackController _actionFeedback = ActionFeedbackController();
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
  rect.SelectionTool _selectionTool = rect.SelectionTool.rectangle;
  rect.SelectionRect? _activeRectangle;
  int _codeDecodeSerial = 0;
  List<DetectedTextItem> _decodedCodeItems = const [];
  DetectedTextItem? _pendingOpenItem;

  // Captured in build so callbacks never look up inherited widgets.
  bool _announces = false;

  /// A concise status for screen readers. Callers pass state and counts,
  /// never recognized text. Flutter's Linux embedder ignores live regions, so
  /// every state change is announced explicitly.
  void _announce(
    String message, {
    bool assertive = false,
    bool immediate = false,
    String? topic,
  }) {
    if (message.isEmpty) {
      return;
    }
    ref
        .read(overlayAnnouncerProvider)
        .announce(
          message,
          assertive: assertive,
          immediate: immediate,
          topic: topic,
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
      OverlayPhase.ready when lineCount == 0 => (
        'Kiriglyph capture open, no text found, click or draw around an '
            'object, $_helpHint',
        false,
      ),
      OverlayPhase.ready => (
        'Kiriglyph capture open, ${_lines(lineCount ?? 0)} found, $_helpHint',
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
    _codeDecodeSerial++;
    _feedbackTimer?.cancel();
    _actionFeedback.dispose();
    _canvasFocusNode.dispose();
    _closeFocusNode.dispose();
    _toolbarFocusNode.dispose();
    _copyFocusNode.dispose();
    _copyAllFocusNode.dispose();
    super.dispose();
  }

  void _dismiss() {
    _exportSerial++;
    _codeDecodeSerial++;
    _announce('Kiriglyph capture closed', immediate: true);
    setState(() {
      _exportBusy = false;
      _helpOpen = false;
    });
    unawaited(ref.read(selectionOverlayProvider.notifier).dismiss());
  }

  Future<void> _copy(
    String text,
    String successMessage, {
    Set<String> actions = const {},
  }) async {
    var message = successMessage;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      message = _copyFailedMessage;
    }
    _showFeedback(
      message,
      assertive: message == _copyFailedMessage,
      actions: actions,
    );
  }

  /// Shows [message] and tells the buttons in [actions] how it ended, so
  /// each one confirms itself ("Copied", "Saved") or shows "Failed".
  void _showFeedback(
    String message, {
    bool assertive = false,
    Set<String> actions = const {},
  }) {
    if (!mounted) {
      return;
    }
    if (assertive) {
      _actionFeedback.fail(actions);
    } else {
      _actionFeedback.succeed(actions);
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
        actions: {ActionIds.copyText},
      );
    }
  }

  void _copyAll() {
    final selection = ref.read(regionSelectionProvider);
    if (selection.regions.isNotEmpty) {
      _copy(
        selection.allText,
        'Copied all ${_lines(selection.regions.length)}',
        actions: {ActionIds.copyAll},
      );
    }
  }

  Future<Uint8List?> _capturedPngBytes() async {
    final path = ref.read(selectionOverlayProvider).subjectImagePath;
    if (path == null) {
      return null;
    }
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  void _clearDecodedCodes() {
    _codeDecodeSerial++;
    if (_decodedCodeItems.isNotEmpty || _pendingOpenItem != null) {
      setState(() {
        _decodedCodeItems = const [];
        _pendingOpenItem = null;
      });
    }
  }

  void _decodeCodesForActiveSelection() {
    final serial = ++_codeDecodeSerial;
    setState(() {
      _decodedCodeItems = const [];
      _pendingOpenItem = null;
    });
    unawaited(_decodeCodesForActiveSelectionSerial(serial));
  }

  Future<void> _decodeCodesForActiveSelectionSerial(int serial) async {
    final bytes = await _capturedPngBytes();
    final crop = _activeScreenshotCrop();
    if (bytes == null || crop == null) {
      return;
    }
    Directory? tempDir;
    File? tempFile;
    try {
      final cropBytes = await ref
          .read(screenshotImageCodecProvider)
          .cropPng(bytes, crop);
      if (!mounted || serial != _codeDecodeSerial) {
        return;
      }
      tempDir = await Directory.systemTemp.createTemp('kiriglyph-code-');
      tempFile = File('${tempDir.path}/selection.png');
      await tempFile.writeAsBytes(cropBytes, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', tempFile.path]);
      }
      final codes = await ref
          .read(ocrWorkerProvider)
          .decodeCodes(tempFile.path);
      if (!mounted || serial != _codeDecodeSerial) {
        return;
      }
      setState(() {
        _decodedCodeItems = [
          for (final code in codes) detectedCodeItem(code.text),
        ];
      });
    } catch (_) {
      if (mounted && serial == _codeDecodeSerial) {
        setState(() => _decodedCodeItems = const []);
      }
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
        if (tempDir != null && await tempDir.exists()) {
          await tempDir.delete();
        }
      } on FileSystemException {
        // Best-effort cleanup of the private decode crop.
      }
    }
  }

  ScreenshotCrop? _activeScreenshotCrop() {
    final overlay = ref.read(selectionOverlayProvider);
    final result = overlay.ocrResult;
    if (result == null) {
      return null;
    }
    final bounds = _activeSelectionBoundsInSource();
    if (bounds == null || bounds.isEmpty) {
      return null;
    }
    final left = bounds.left.floor().clamp(0, result.imageWidth - 1);
    final top = bounds.top.floor().clamp(0, result.imageHeight - 1);
    final right = bounds.right.ceil().clamp(left + 1, result.imageWidth);
    final bottom = bounds.bottom.ceil().clamp(top + 1, result.imageHeight);
    return ScreenshotCrop(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  Future<void> _copyAreaScreenshot() async {
    final bytes = await _capturedPngBytes();
    final crop = _activeScreenshotCrop();
    if (bytes == null || crop == null) {
      _showFeedback(
        'Select an area before copying.',
        assertive: true,
        actions: {ActionIds.copyScreenshot},
      );
      return;
    }
    final outcome = await ref
        .read(screenshotExportControllerProvider)
        .copyCrop(encodedPng: bytes, crop: crop)
        .timeout(_exportTimeout);
    _showFeedback(
      outcome.kind == ScreenshotExportOutcomeKind.copied
          ? 'Copied screenshot'
          : _copyImageFailedMessage,
      assertive: outcome.kind != ScreenshotExportOutcomeKind.copied,
      actions: {ActionIds.copyScreenshot},
    );
  }

  Future<void> _saveAreaScreenshot() async {
    if (ref.read(selectionOverlayProvider).activeSelection ==
            SelectionActiveKind.object &&
        _canExportSubject) {
      await _saveSubjectPng();
      return;
    }
    final bytes = await _capturedPngBytes();
    final crop = _activeScreenshotCrop();
    if (bytes == null || crop == null) {
      _showFeedback(
        'Select an area before saving.',
        assertive: true,
        actions: {ActionIds.saveScreenshot},
      );
      return;
    }
    final outcome = await ref
        .read(screenshotExportControllerProvider)
        .saveCrop(encodedPng: bytes, crop: crop)
        .timeout(_exportTimeout);
    _showSavedScreenshotOutcome(outcome);
  }

  Future<void> _saveFullScreenshot() async {
    final bytes = await _capturedPngBytes();
    if (bytes == null) {
      _showFeedback(
        'Could not save screenshot.',
        assertive: true,
        actions: {ActionIds.saveFullScreenshot},
      );
      return;
    }
    final outcome = await ref
        .read(screenshotExportControllerProvider)
        .save(bytes)
        .timeout(_exportTimeout);
    _showSavedScreenshotOutcome(outcome, full: true);
  }

  void _showSavedScreenshotOutcome(
    ScreenshotExportOutcome outcome, {
    bool full = false,
  }) {
    _showFeedback(
      outcome.kind == ScreenshotExportOutcomeKind.saved
          ? '${full ? 'Saved full screenshot' : 'Saved'} to '
                'Pictures/${outcome.savedName ?? 'kiriglyph.png'}'
          : 'Could not save screenshot.',
      assertive: outcome.kind != ScreenshotExportOutcomeKind.saved,
      actions: {full ? ActionIds.saveFullScreenshot : ActionIds.saveScreenshot},
    );
  }

  void _liftActiveArea() {
    final rect = _activeRectangle;
    final loop = _lastLoopStroke;
    if (rect != null) {
      final stroke = _rectStroke(rect);
      _applyObjectLoop(
        stroke,
        LoopAsObjectIntent(classifyLoop(regions: const [], stroke: stroke)),
      );
    } else if (loop != null) {
      _applyObjectLoop(
        loop,
        LoopAsObjectIntent(classifyLoop(regions: const [], stroke: loop)),
      );
    }
  }

  Future<void> _searchWeb(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    try {
      await ref.read(webSearchLauncherProvider).search(text);
      _showFeedback('Opened web search', actions: {ActionIds.searchWeb});
    } catch (_) {
      _showFeedback(
        'Could not open web search.',
        assertive: true,
        actions: {ActionIds.searchWeb},
      );
    }
  }

  Future<void> _openDetection(DetectedTextItem item) async {
    if (item.kind == DetectedTextKind.phone) {
      await _copy(item.text, 'Copied number');
      return;
    }
    if (!_targetIsOpenable(item.target)) {
      _showFeedback('That target cannot be opened.', assertive: true);
      return;
    }
    setState(() => _pendingOpenItem = item);
    _announce('Open ${item.target}? Choose Open to confirm or Cancel.');
  }

  Future<void> _confirmOpenDetection() async {
    final item = _pendingOpenItem;
    if (item == null || !_targetIsOpenable(item.target)) {
      setState(() => _pendingOpenItem = null);
      _showFeedback('That target cannot be opened.', assertive: true);
      return;
    }
    try {
      await ref.read(linkOpenerProvider).open(item.target);
      _showFeedback('Opened ${item.target}');
    } catch (_) {
      _showFeedback('Could not open ${item.target}.', assertive: true);
    } finally {
      if (mounted) {
        setState(() => _pendingOpenItem = null);
      }
    }
  }

  void _copyDetection(DetectedTextItem item) {
    _copy(item.text, 'Copied', actions: {ActionIds.copyDetection});
  }

  bool _targetIsOpenable(String target) {
    final uri = Uri.tryParse(target);
    return uri != null && allowedDetectedSchemes.contains(uri.scheme);
  }

  static bool _isHelpKey(KeyEvent event) {
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.question ||
        key == LogicalKeyboardKey.f1 ||
        (key == LogicalKeyboardKey.slash &&
            HardwareKeyboard.instance.isShiftPressed) ||
        event.character == '?';
  }

  void _openHelp() {
    if (_helpOpen) {
      return;
    }
    setState(() {
      _helpOpen = true;
      _objectCursorActive = false;
    });
    _announce('Keyboard shortcuts. Press Escape to close.', immediate: true);
  }

  void _closeHelp() {
    if (!_helpOpen) {
      return;
    }
    setState(() => _helpOpen = false);
    _canvasFocusNode.requestFocus();
    _announce('Keyboard shortcuts closed', immediate: true);
  }

  void _setTool(rect.SelectionTool tool) {
    if (tool == _selectionTool) {
      return;
    }
    setState(() {
      _selectionTool = tool;
      _rectangleClearToken++;
      _activeRectangle = null;
    });
    _announce(_toolAnnouncement(tool), topic: 'tool');
  }

  String _toolAnnouncement(rect.SelectionTool tool) => switch (tool) {
    rect.SelectionTool.rectangle =>
      'Rectangle tool. Press R to start a rectangle.',
    rect.SelectionTool.twoClicks =>
      'Two clicks tool. Click two opposite corners.',
    rect.SelectionTool.freeDraw => 'Free draw tool',
  };

  rect.SelectionTool _nextSelectionTool(rect.SelectionTool tool) =>
      switch (tool) {
        rect.SelectionTool.rectangle => rect.SelectionTool.twoClicks,
        rect.SelectionTool.twoClicks => rect.SelectionTool.freeDraw,
        rect.SelectionTool.freeDraw => rect.SelectionTool.rectangle,
      };

  /// F6: moves focus between the canvas and the toolbar.
  void _togglePanelFocus(SelectionOverlayState overlay) {
    if (_toolbarFocusNode.hasFocus) {
      _canvasFocusNode.requestFocus();
      _announce('Canvas');
      return;
    }
    final selection = ref.read(regionSelectionProvider);
    final target = selection.hasSelection
        ? _copyFocusNode
        : selection.regions.isNotEmpty
        ? _copyAllFocusNode
        : _closeFocusNode;
    target.requestFocus();
    _announce(
      'Toolbar. Alt plus arrow keys move it. F6 returns to the canvas.',
    );
  }

  /// Escape steps back one level: the rectangle, then the selection, then
  /// the overlay.
  void _escape() {
    if (_helpOpen) {
      _closeHelp();
      return;
    }
    if (_activeRectangle != null) {
      setState(() {
        _rectangleClearToken++;
        _activeRectangle = null;
      });
      _announce(
        _selectionTool == rect.SelectionTool.twoClicks
            ? 'Two-click rectangle cancelled'
            : 'Rectangle cleared',
      );
      return;
    }
    final overlay = ref.read(selectionOverlayProvider);
    final hasSelection =
        ref.read(regionSelectionProvider).hasSelection ||
        overlay.activeSelection == SelectionActiveKind.object ||
        _subjectMask != null ||
        _subjectBusy ||
        _lastLoopStroke != null;
    if (hasSelection) {
      ref.read(regionSelectionProvider.notifier).clear();
      _clearSubject();
      _announce('Selection cleared');
      return;
    }
    _dismiss();
  }

  void _copyActiveImage() {
    if (ref.read(selectionOverlayProvider).activeSelection ==
            SelectionActiveKind.object &&
        _canExportSubject) {
      _copySubjectImage();
    } else {
      _copyAreaScreenshot();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final control = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (_helpOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape || _isHelpKey(event)) {
        _closeHelp();
        return KeyEventResult.handled;
      }
      // The panel owns the keyboard; nothing below it reacts.
      return KeyEventResult.ignored;
    }
    if (_isHelpKey(event)) {
      _openHelp();
      return KeyEventResult.handled;
    }
    if (_objectCursorActive) {
      return _onObjectCursorKey(event);
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.tab when shift && _canvasFocusNode.hasFocus:
        _closeFocusNode.requestFocus();
      case LogicalKeyboardKey.f6:
        _togglePanelFocus(ref.read(selectionOverlayProvider));
      case LogicalKeyboardKey.escape:
        _escape();
      case LogicalKeyboardKey.keyC when control && shift:
        _copyActiveImage();
      case LogicalKeyboardKey.keyC when control:
        if (ref.read(selectionOverlayProvider).activeSelection ==
            SelectionActiveKind.object) {
          _copySubjectImage();
        } else {
          _copySelection();
        }
      case LogicalKeyboardKey.keyS
          when control &&
              shift &&
              ref.read(selectionOverlayProvider).activeSelection ==
                  SelectionActiveKind.object:
        _saveSubjectPng(saveAs: true);
      case LogicalKeyboardKey.keyS when control && shift:
        _saveAreaScreenshot();
      case LogicalKeyboardKey.keyF when control && shift:
        _saveFullScreenshot();
      case LogicalKeyboardKey.keyS
          when control &&
              ref.read(selectionOverlayProvider).activeSelection ==
                  SelectionActiveKind.object:
        _saveSubjectPng();
      case LogicalKeyboardKey.keyS when control:
        _saveAreaScreenshot();
      case LogicalKeyboardKey.keyA when control:
        _activateTextSelection();
        ref.read(regionSelectionProvider.notifier).selectAll();
      case LogicalKeyboardKey.keyO when !control:
        _cycleObject(forward: !shift);
      case LogicalKeyboardKey.keyT when !control:
        _setTool(_nextSelectionTool(_selectionTool));
      case LogicalKeyboardKey.keyR
          when !control && _selectionTool == rect.SelectionTool.freeDraw:
        _setTool(rect.SelectionTool.rectangle);
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
        setState(() {
          _objectCursorActive = false;
          _objectIndex = null;
        });
        _announce('Object cursor closed');
      case LogicalKeyboardKey.keyO
          when !HardwareKeyboard.instance.isControlPressed:
        _cycleObject(forward: !HardwareKeyboard.instance.isShiftPressed);
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
        setState(() {
          _objectCursorActive = false;
          _objectIndex = null;
        });
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
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final motion = ref.watch(motionPolicyProvider(disableAnimations));
    final glowEnabled = ref.watch(glowEnabledProvider);
    _announces = MediaQuery.supportsAnnounceOf(context);
    final cursorScale = ref.watch(cursorScaleProvider);
    _announceStateChange(overlay);
    ref.listen(regionSelectionProvider, (previous, next) {
      if (next.hasSelection && !identical(previous, next)) {
        _announce('${_selectionAmount(next)} selected', topic: 'selection');
      }
    });
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
              _actionFeedback.reduceMotion = motion == MotionPolicy.reduced;
              return ActionFeedbackScope(
                controller: _actionFeedback,
                child: Stack(
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
                    if (frame != null &&
                        geometry != null &&
                        _subjectMask != null)
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
                            selectionTool: _selectionTool,
                            focusNode: _canvasFocusNode,
                            rectangleClearToken: _rectangleClearToken,
                            cursorScale: cursorScale,
                            onRectangleSelectionChanged: (rect) {
                              setState(() {
                                _activeRectangle = rect;
                                if (rect != null) {
                                  _codeDecodeSerial++;
                                  _decodedCodeItems = const [];
                                  _pendingOpenItem = null;
                                  _lastLoopStroke = null;
                                  _lastLoopInterpretation = null;
                                }
                              });
                              if (rect != null && rect.isUsable) {
                                _decodeCodesForActiveSelection();
                              }
                            },
                            onRectangleSelectionFinished: (area) {
                              _announce(
                                'Area selected, ${area.width.round()} by '
                                '${area.height.round()} pixels',
                                topic: 'rectangle',
                              );
                              _decodeCodesForActiveSelection();
                            },
                          ),
                        ),
                      ),
                    if (frame != null && motion == MotionPolicy.full)
                      EntryGlow(key: ObjectKey(frame)),
                    if (frame != null)
                      PersistentEdgeGlow(
                        busy:
                            overlay.phase == OverlayPhase.recognizing ||
                            _subjectBusy ||
                            _exportBusy,
                        policy: motion,
                        enabled: glowEnabled,
                      ),
                    if (overlay.phase == OverlayPhase.recognizing &&
                        motion == MotionPolicy.full)
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
                              scale: cursorScale,
                            ),
                          ),
                        ),
                      ),
                    if (_showSelectionActionChip(geometry, selection) ||
                        _showLoopHint(geometry) ||
                        _showSubjectChip(geometry))
                      // One stack for every chip near the selection, so the
                      // "Selected as text" hint, the action chip and the subject
                      // chip never draw over each other.
                      CustomSingleChildLayout(
                        delegate: _SubjectChipLayout(
                          subject: _showSelectionActionChip(geometry, selection)
                              ? _activeSelectionBoundsInView(
                                  geometry!,
                                  selection,
                                )
                              : _showLoopHint(geometry)
                              ? _loopBoundsInView(geometry!)
                              : _subjectBoundsInView(geometry!),
                          screen: size,
                          textScale: MediaQuery.textScalerOf(context).scale(1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: AppSpacing.sm,
                          children: [
                            if (_showLoopHint(geometry))
                              _AnimatedOverlayChip(
                                policy: motion,
                                child: LoopHintChip(
                                  selectedAsText:
                                      _lastLoopInterpretation ==
                                      LoopInterpretation.text,
                                  onFlip: () => _flipLastLoop(result!),
                                ),
                              ),
                            if (_showSelectionActionChip(geometry, selection))
                              _AnimatedOverlayChip(
                                policy: motion,
                                child: SelectionActionChip(
                                  canCopyText: selection.hasSelection,
                                  canLiftObject: _hasActiveAreaSelection,
                                  canCopyScreenshot: _hasActiveAreaSelection,
                                  canSaveScreenshot: _hasActiveAreaSelection,
                                  canSearchWeb: selection.hasSelection,
                                  detections: [
                                    ...detectTextItems(selection.selectedText),
                                    ..._decodedCodeItems,
                                  ],
                                  confirmTarget: _pendingOpenItem?.target,
                                  onCopyText: _copySelection,
                                  onLiftObject: _liftActiveArea,
                                  onCopyScreenshot: _copyAreaScreenshot,
                                  onSaveScreenshot: _saveAreaScreenshot,
                                  onSearchWeb: () =>
                                      _searchWeb(selection.selectedText),
                                  onOpenDetection: _openDetection,
                                  onCopyDetection: _copyDetection,
                                  onConfirmOpen: _confirmOpenDetection,
                                  onCancelOpen: () =>
                                      setState(() => _pendingOpenItem = null),
                                ),
                              ),
                            if (_showSubjectChip(geometry))
                              _AnimatedOverlayChip(
                                policy: motion,
                                child: SubjectActionChip(
                                  status: _subjectMessage,
                                  exporting: _exportBusy,
                                  onCopy: _canExportSubject
                                      ? _copySubjectImage
                                      : null,
                                  onSave: _canExportSubject
                                      ? _saveSubjectPng
                                      : null,
                                  onRemove: _clearSubject,
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (showToolbar)
                      OverlayToolbarHost(
                        focusNode: _toolbarFocusNode,
                        displayKey: displayIdentityFromSize(size),
                        screen: size,
                        obstacles: obstacles,
                        selectionBounds: geometry != null
                            ? _activeSelectionBoundsInView(geometry, selection)
                            : null,
                        policy: motion,
                        toolbar: OverlayToolbar(
                          status: status,
                          statusIsLive:
                              !_announces &&
                              kind != _StatusKind.hint &&
                              kind != _StatusKind.selection,
                          onCopy: selection.hasSelection
                              ? _copySelection
                              : null,
                          onCopyAll: selection.regions.isEmpty
                              ? null
                              : _copyAll,
                          copyTooltipMessage: noTextReady
                              ? 'No text found to copy'
                              : null,
                          copyAllTooltipMessage: noTextReady
                              ? 'No recognized text to copy'
                              : null,
                          tool: _selectionTool,
                          onToolChanged: _setTool,
                          copyFocusNode: _copyFocusNode,
                          copyAllFocusNode: _copyAllFocusNode,
                          onSaveFullScreenshot: _saveFullScreenshot,
                          closeFocusNode: _closeFocusNode,
                          onCloseTabForward: _canvasFocusNode.requestFocus,
                          onClose: _dismiss,
                        ),
                      ),
                    if (_helpOpen)
                      Positioned.fill(
                        child: Stack(
                          children: [
                            ModalBarrier(
                              key: const Key('keyboard-help-barrier'),
                              color: Colors.black.withValues(alpha: 0.5),
                              onDismiss: _closeHelp,
                            ),
                            KeyboardHelpPanel(onClose: _closeHelp),
                          ],
                        ),
                      ),
                  ],
                ),
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
    _clearDecodedCodes();
    final overlay = ref.read(selectionOverlayProvider);
    if (overlay.activeSelection == SelectionActiveKind.object ||
        _subjectMask != null ||
        _subjectBusy) {
      _clearSubject(updateActiveSelection: false);
    }
    setState(() {
      _lastLoopStroke = null;
      _lastLoopInterpretation = null;
      _activeRectangle = null;
    });
    ref
        .read(selectionOverlayProvider.notifier)
        .setActiveSelection(SelectionActiveKind.text);
  }

  void _activateObjectSelection() {
    _clearDecodedCodes();
    ref.read(regionSelectionProvider.notifier).clear();
    setState(() {
      _lastLoopStroke = null;
      _lastLoopInterpretation = null;
      _activeRectangle = null;
    });
    ref
        .read(selectionOverlayProvider.notifier)
        .setActiveSelection(SelectionActiveKind.object);
  }

  /// O / Shift+O: puts the object cursor on the next or previous object
  /// area and says where it is.
  void _cycleObject({required bool forward}) {
    final overlay = ref.read(selectionOverlayProvider);
    final frame = overlay.frame;
    if (frame == null) {
      return;
    }
    final candidates = objectCandidates(
      imageWidth: frame.width,
      imageHeight: frame.height,
      regions: overlay.ocrResult?.regions ?? const [],
    );
    if (candidates.isEmpty) {
      return;
    }
    final entering = !_objectCursorActive;
    final index = cycleObjectIndex(
      _objectIndex,
      candidates.length,
      forward: forward,
    );
    setState(() {
      _objectCursorActive = true;
      _objectIndex = index;
      _objectCursor = candidates[index].point;
    });
    final where = objectCandidateAnnouncement(index, candidates);
    _announce(
      entering
          ? '$where. Arrow keys adjust, Enter selects, Escape cancels.'
          : where,
      immediate: true,
    );
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
    _clearDecodedCodes();
    _activateObjectSelection();
    setState(() {
      _lastLoopStroke = null;
      _lastLoopInterpretation = null;
      _activeRectangle = null;
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
      _activeRectangle = null;
    });
    _decodeCodesForActiveSelection();
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

  bool get _hasActiveAreaSelection =>
      _activeRectangle != null || _lastLoopStroke != null;

  bool _showSelectionActionChip(
    FittedImageGeometry? geometry,
    RegionSelection selection,
  ) => geometry != null && (selection.hasSelection || _hasActiveAreaSelection);

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

  Rect _activeSelectionBoundsInView(
    FittedImageGeometry geometry,
    RegionSelection selection,
  ) {
    final source = _activeSelectionBoundsInSource();
    if (source != null) {
      return Rect.fromPoints(
        geometry.mapPoint(Point(x: source.left, y: source.top)),
        geometry.mapPoint(Point(x: source.right, y: source.bottom)),
      );
    }
    final selected = selection.selectedRegions;
    if (selected.isEmpty) {
      return geometry.destination;
    }
    var bounds = geometry.regionRect(selected.first);
    for (final region in selected.skip(1)) {
      bounds = bounds.expandToInclude(geometry.regionRect(region));
    }
    return bounds;
  }

  Rect? _activeSelectionBoundsInSource() {
    final rectangle = _activeRectangle;
    if (rectangle != null) {
      return Rect.fromLTRB(
        rectangle.left,
        rectangle.top,
        rectangle.right,
        rectangle.bottom,
      );
    }
    final stroke = _lastLoopStroke;
    if (stroke == null || stroke.isEmpty) {
      final bounds = _subjectMask?.stats.bounds ?? _subjectMask?.bounds;
      if (bounds == null) {
        return null;
      }
      return Rect.fromLTWH(
        bounds.x.toDouble(),
        bounds.y.toDouble(),
        bounds.width.toDouble(),
        bounds.height.toDouble(),
      );
    }
    var left = stroke.first.x;
    var right = stroke.first.x;
    var top = stroke.first.y;
    var bottom = stroke.first.y;
    for (final point in stroke.skip(1)) {
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  List<Point> _rectStroke(rect.SelectionRect rect) => [
    Point(x: rect.left, y: rect.top),
    Point(x: rect.right, y: rect.top),
    Point(x: rect.right, y: rect.bottom),
    Point(x: rect.left, y: rect.bottom),
    Point(x: rect.left, y: rect.top),
  ];

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
    _showFeedback(
      message,
      assertive: assertive,
      actions: {ActionIds.copySubject},
    );
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
      _showFeedback(
        message,
        assertive: outcome.kind != SubjectExportOutcomeKind.saved,
        // The chip's "Save screenshot" saves the object PNG when one is lifted.
        actions: {ActionIds.saveSubject, ActionIds.saveScreenshot},
      );
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
    _clearDecodedCodes();
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
      if (mask != null) {
        _decodeCodesForActiveSelection();
      }
      _announceSubject(message ?? 'Object selected');
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
        return 'No object found here. Try drawing around it.';
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

class _AnimatedOverlayChip extends StatelessWidget {
  const _AnimatedOverlayChip({required this.policy, required this.child});

  final MotionPolicy policy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionDuration(policy, AppMotionDurations.chip),
      switchInCurve: motionCurve,
      switchOutCurve: motionCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
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
  const _ObjectCursorPainter({
    required this.position,
    required this.color,
    required this.scale,
  });

  final Offset position;
  final Color color;

  /// GNOME cursor-size scale; 1 at the default size.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = 10 * scale;
    final inner = 6 * scale;
    final outer = 18 * scale;
    // Dark rim and light core stay visible on any pixels.
    drawDualStrokeCircle(canvas, position, ring);
    drawDualStrokeLine(
      canvas,
      position.translate(-outer, 0),
      position.translate(-inner, 0),
    );
    drawDualStrokeLine(
      canvas,
      position.translate(inner, 0),
      position.translate(outer, 0),
    );
    drawDualStrokeLine(
      canvas,
      position.translate(0, -outer),
      position.translate(0, -inner),
    );
    drawDualStrokeLine(
      canvas,
      position.translate(0, inner),
      position.translate(0, outer),
    );
    canvas.drawCircle(position, 2 * scale, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ObjectCursorPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.color != color ||
      oldDelegate.scale != scale;
}
