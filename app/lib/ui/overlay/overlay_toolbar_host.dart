import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/a11y/overlay_announcer.dart';
import 'package:kiriglyph/overlay/toolbar_placement.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar.dart';
import 'package:kiriglyph/ui/overlay/toolbar_move_controls.dart';
import 'package:kiriglyph/ui/overlay/toolbar_session.dart';

const _keyboardStep = 16.0;
const _keyboardStepLarge = 64.0;

/// Positions [OverlayToolbar] with drag, menu, and keyboard alternatives.
class OverlayToolbarHost extends ConsumerStatefulWidget {
  const OverlayToolbarHost({
    super.key,
    required this.displayKey,
    required this.screen,
    required this.obstacles,
    required this.selectionBounds,
    required this.policy,
    required this.toolbar,
    this.focusNode,
  });

  /// Focus node of the toolbar scope, so the screen can tell whether focus
  /// is inside the toolbar (F6).
  final FocusNode? focusNode;
  final String displayKey;
  final Size screen;
  final List<Rect> obstacles;
  final Rect? selectionBounds;
  final MotionPolicy policy;
  final OverlayToolbar toolbar;

  @override
  ConsumerState<OverlayToolbarHost> createState() => _OverlayToolbarHostState();
}

class _OverlayToolbarHostState extends ConsumerState<OverlayToolbarHost> {
  Offset? _dragOrigin;
  Offset? _dragStartOffset;
  Size? _childSize;

  ToolbarSessionPlacement _session(String key) =>
      ref.watch(toolbarSessionProvider)[key] ?? const ToolbarSessionPlacement();

  void _writeSession(ToolbarSessionPlacement placement) {
    ref
        .read(toolbarSessionProvider.notifier)
        .updateDisplay(widget.displayKey, placement);
  }

  void _announce(String message) => ref
      .read(overlayAnnouncerProvider)
      .announce(message, topic: 'toolbar-move');

  Offset _resolvedOffset(Size childSize) {
    return resolveToolbarPosition(
      screen: widget.screen,
      toolbar: childSize,
      obstacles: widget.obstacles,
      session: _session(widget.displayKey),
      selectionBounds: widget.selectionBounds,
    );
  }

  Offset _defaultOffset(Size childSize) {
    final session = _session(widget.displayKey);
    return defaultToolbarOffset(
      screen: widget.screen,
      toolbar: childSize,
      mode: session.userMovedManually ? ToolbarAnchorMode.auto : session.mode,
      obstacles: widget.obstacles,
      selectionBounds: widget.selectionBounds,
    );
  }

  void _setAnchor(ToolbarAnchorMode mode, String announcement) {
    _writeSession(
      _session(widget.displayKey).copyWith(
        mode: mode,
        userMovedManually: false,
        manualOffset: Offset.zero,
      ),
    );
    _announce(announcement);
  }

  static String _directionName(Offset delta) => delta.dy < 0
      ? 'up'
      : delta.dy > 0
      ? 'down'
      : delta.dx < 0
      ? 'left'
      : 'right';

  void _nudge(Offset delta) {
    final size = _childSize;
    if (size == null) {
      return;
    }
    final session = _session(widget.displayKey);
    final current = _resolvedOffset(size);
    final next = nudgeToolbar(
      current: current,
      screen: widget.screen,
      toolbar: size,
      delta: delta,
    );
    _writeSession(
      session.copyWith(
        manualOffset: next - _defaultOffset(size),
        userMovedManually: true,
      ),
    );
    _announce('Toolbar moved ${_directionName(delta)}');
  }

  @override
  Widget build(BuildContext context) {
    final glowEnabled = ref.watch(glowEnabledProvider);
    final session = _session(widget.displayKey);

    return CustomSingleChildLayout(
      delegate: _ToolbarHostLayoutDelegate(
        screen: widget.screen,
        obstacles: widget.obstacles,
        session: session,
        selectionBounds: widget.selectionBounds,
      ),
      child: MeasureSize(
        onChange: (size) {
          if (_childSize != size) {
            setState(() => _childSize = size);
          }
        },
        child: ToolbarMoveControls(
          grip: _ToolbarGrip(onNudge: _nudge),
          menu: _ToolbarMoveMenu(
            glowEnabled: glowEnabled,
            onGlowToggle: () => ref.read(glowEnabledProvider.notifier).toggle(),
            onMoveTop: () =>
                _setAnchor(ToolbarAnchorMode.top, 'Toolbar moved to top'),
            onMoveBottom: () =>
                _setAnchor(ToolbarAnchorMode.bottom, 'Toolbar moved to bottom'),
            onMoveFollow: () => _setAnchor(
              ToolbarAnchorMode.followSelection,
              'Toolbar follows selection',
            ),
          ),
          // The whole toolbar is the drag target; buttons still click.
          child: MouseRegion(
            cursor: _dragOrigin == null
                ? SystemMouseCursors.grab
                : SystemMouseCursors.grabbing,
            child: GestureDetector(
              onPanStart: (details) {
                final size = _childSize;
                if (size == null) {
                  return;
                }
                setState(() {
                  _dragOrigin = details.globalPosition;
                  _dragStartOffset = _resolvedOffset(size);
                });
              },
              onPanUpdate: (details) {
                final size = _childSize;
                final start = _dragStartOffset;
                final origin = _dragOrigin;
                if (size == null || start == null || origin == null) {
                  return;
                }
                final delta = details.globalPosition - origin;
                final next = nudgeToolbar(
                  current: start,
                  screen: widget.screen,
                  toolbar: size,
                  delta: delta,
                );
                _writeSession(
                  _session(widget.displayKey).copyWith(
                    manualOffset: next - _defaultOffset(size),
                    userMovedManually: true,
                  ),
                );
              },
              onPanEnd: (_) => setState(() {
                _dragOrigin = null;
                _dragStartOffset = null;
              }),
              onPanCancel: () => setState(() {
                _dragOrigin = null;
                _dragStartOffset = null;
              }),
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                      NudgeOverlayToolbarIntent(Offset(0, -_keyboardStep)),
                  SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                      NudgeOverlayToolbarIntent(Offset(0, _keyboardStep)),
                  SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                      NudgeOverlayToolbarIntent(Offset(-_keyboardStep, 0)),
                  SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
                      NudgeOverlayToolbarIntent(Offset(_keyboardStep, 0)),
                  SingleActivator(
                    LogicalKeyboardKey.arrowUp,
                    alt: true,
                    shift: true,
                  ): NudgeOverlayToolbarIntent(
                    Offset(0, -_keyboardStepLarge),
                  ),
                  SingleActivator(
                    LogicalKeyboardKey.arrowDown,
                    alt: true,
                    shift: true,
                  ): NudgeOverlayToolbarIntent(
                    Offset(0, _keyboardStepLarge),
                  ),
                  SingleActivator(
                    LogicalKeyboardKey.arrowLeft,
                    alt: true,
                    shift: true,
                  ): NudgeOverlayToolbarIntent(
                    Offset(-_keyboardStepLarge, 0),
                  ),
                  SingleActivator(
                    LogicalKeyboardKey.arrowRight,
                    alt: true,
                    shift: true,
                  ): NudgeOverlayToolbarIntent(
                    Offset(_keyboardStepLarge, 0),
                  ),
                },
                child: Actions(
                  actions: {
                    NudgeOverlayToolbarIntent:
                        CallbackAction<NudgeOverlayToolbarIntent>(
                          onInvoke: (intent) {
                            _nudge(intent.delta);
                            return null;
                          },
                        ),
                  },
                  child: Focus(
                    key: const Key('overlay-toolbar-focus'),
                    focusNode: widget.focusNode,
                    child: widget.toolbar,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarHostLayoutDelegate extends SingleChildLayoutDelegate {
  _ToolbarHostLayoutDelegate({
    required this.screen,
    required this.obstacles,
    required this.session,
    required this.selectionBounds,
  });

  final Size screen;
  final List<Rect> obstacles;
  final ToolbarSessionPlacement session;
  final Rect? selectionBounds;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      resolveToolbarPosition(
        screen: screen,
        toolbar: childSize,
        obstacles: obstacles,
        session: session,
        selectionBounds: selectionBounds,
      );

  @override
  bool shouldRelayout(covariant _ToolbarHostLayoutDelegate oldDelegate) =>
      oldDelegate.screen != screen ||
      oldDelegate.session != session ||
      oldDelegate.selectionBounds != selectionBounds ||
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

class MeasureSize extends StatefulWidget {
  const MeasureSize({super.key, required this.onChange, required this.child});

  final ValueChanged<Size> onChange;
  final Widget child;

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = this.context;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      if (_oldSize != box.size) {
        _oldSize = box.size;
        widget.onChange(box.size);
      }
    });
    return widget.child;
  }
}

/// Keyboard/menu nudge intent for [OverlayToolbarHost] shortcuts.
class NudgeOverlayToolbarIntent extends Intent {
  const NudgeOverlayToolbarIntent(this.delta);

  final Offset delta;
}

/// The keyboard twin of dragging: click it, then use the arrow keys.
class _ToolbarGrip extends StatelessWidget {
  const _ToolbarGrip({required this.onNudge});

  final ValueChanged<Offset> onNudge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final step = HardwareKeyboard.instance.isShiftPressed
            ? _keyboardStepLarge
            : _keyboardStep;
        final delta = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowUp => Offset(0, -step),
          LogicalKeyboardKey.arrowDown => Offset(0, step),
          LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
          LogicalKeyboardKey.arrowRight => Offset(step, 0),
          _ => null,
        };
        if (delta == null) {
          return KeyEventResult.ignored;
        }
        onNudge(delta);
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Semantics(
            label: 'Move toolbar',
            hint: 'Drag the toolbar, or use the arrow keys',
            button: true,
            focusable: true,
            focused: focused,
            child: Listener(
              onPointerDown: (_) => Focus.of(context).requestFocus(),
              child: DecoratedBox(
                key: const Key('overlay-toolbar-move-grip'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  border: focused
                      ? Border.all(
                          color: colors.primary,
                          width: AppA11y.focusRingWidth,
                        )
                      : null,
                ),
                child: SizedBox(
                  key: const Key('overlay-toolbar-move-grip-target'),
                  width: AppA11y.minTapTarget,
                  height: AppA11y.minTapTarget,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolbarMoveMenu extends StatelessWidget {
  const _ToolbarMoveMenu({
    required this.onMoveTop,
    required this.onMoveBottom,
    required this.onMoveFollow,
    required this.glowEnabled,
    required this.onGlowToggle,
  });

  final VoidCallback onMoveTop;
  final VoidCallback onMoveBottom;
  final VoidCallback onMoveFollow;
  final bool glowEnabled;
  final VoidCallback onGlowToggle;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('overlay-toolbar-move-menu'),
      tooltip: 'Move toolbar',
      icon: const Icon(Icons.open_with, size: 18),
      onSelected: (value) => switch (value) {
        'top' => onMoveTop(),
        'bottom' => onMoveBottom(),
        'follow' => onMoveFollow(),
        'glow' => onGlowToggle(),
        _ => null,
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'top', child: Text('Top')),
        const PopupMenuItem(value: 'bottom', child: Text('Bottom')),
        const PopupMenuItem(value: 'follow', child: Text('Follow selection')),
        CheckedPopupMenuItem(
          value: 'glow',
          checked: glowEnabled,
          child: const Text('Edge glow'),
        ),
      ],
    );
  }
}
