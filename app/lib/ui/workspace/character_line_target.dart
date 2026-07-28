import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/selection/region_selection_provider.dart';
import 'package:ubuntu_live_text/ui/workspace/character_range_painter.dart';

typedef CharacterTapCallback = void Function(Offset position, int clickCount);

class CharacterLineTarget extends ConsumerStatefulWidget {
  const CharacterLineTarget({
    super.key,
    required this.region,
    required this.readingIndex,
    required this.polygons,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
  });

  final TextRegion region;
  final int readingIndex;
  final List<List<Offset>> polygons;
  final CharacterTapCallback onTap;
  final bool Function(Offset) onDragStart;
  final ValueChanged<Offset> onDragUpdate;

  @override
  ConsumerState<CharacterLineTarget> createState() =>
      _CharacterLineTargetState();
}

class _CharacterLineTargetState extends ConsumerState<CharacterLineTarget> {
  bool _focused = false;
  int? _activePointer;
  Offset? _downPosition;
  bool _dragged = false;
  Duration? _lastTapTime;
  Offset? _lastTapPosition;
  int _clickCount = 0;

  void _pointerDown(PointerDownEvent event) {
    if (event.buttons & kPrimaryButton == 0) {
      return;
    }
    if (widget.onDragStart(event.position)) {
      _activePointer = event.pointer;
      _downPosition = event.position;
      _dragged = false;
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    if ((event.position - _downPosition!).distance > kTouchSlop) {
      _dragged = true;
      _resetClickSequence();
    }
    if (_dragged) {
      widget.onDragUpdate(event.position);
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    if (_dragged) {
      widget.onDragUpdate(event.position);
    } else {
      widget.onTap(event.position, _registerClick(event));
    }
    _activePointer = null;
    _downPosition = null;
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointer) {
      _activePointer = null;
      _downPosition = null;
      _resetClickSequence();
    }
  }

  int _registerClick(PointerUpEvent event) {
    final previousTime = _lastTapTime;
    final previousPosition = _lastTapPosition;
    final continuesSequence =
        previousTime != null &&
        previousPosition != null &&
        event.timeStamp - previousTime <= kDoubleTapTimeout &&
        (event.position - previousPosition).distance <= kDoubleTapSlop;
    _clickCount = continuesSequence
        ? (_clickCount < 3 ? _clickCount + 1 : 3)
        : 1;
    _lastTapTime = event.timeStamp;
    _lastTapPosition = event.position;
    return _clickCount;
  }

  void _resetClickSequence() {
    _lastTapTime = null;
    _lastTapPosition = null;
    _clickCount = 0;
  }

  void _activate() {
    ref
        .read(regionSelectionProvider.notifier)
        .activate(
          widget.region.id,
          extend: HardwareKeyboard.instance.isShiftPressed,
        );
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(regionSelectionProvider);
    final hovered = ref.watch(
      hoveredRegionProvider.select((id) => id == widget.region.id),
    );
    final hover = ref.read(hoveredRegionProvider.notifier);
    final selected = [
      for (final range in widget.region.ranges)
        selection.isRangeSelected(widget.region.id, range.start, range.end),
    ];
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.readingIndex.toDouble()),
      child: Semantics(
        container: true,
        button: true,
        selected: selection.isSelected(widget.region.id),
        label:
            'Line ${widget.readingIndex + 1}: ${widget.region.text}. '
            'Character selection available.',
        onTap: _activate,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.text,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          onShowHoverHighlight: (value) => value
              ? hover.enter(widget.region.id)
              : hover.leave(widget.region.id),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.deferToChild,
            excludeFromSemantics: true,
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },
            child: Listener(
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerCancel,
              child: CustomPaint(
                painter: CharacterRangePainter(
                  polygons: widget.polygons,
                  selected: selected,
                  hovered: hovered || _focused,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
