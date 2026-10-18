import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kiriglyph/theme/app_theme.dart';

/// Where an action button is in its confirm cycle.
enum ActionPhase { idle, success, failure }

const _successHold = Duration(milliseconds: 1600);
const _failureHold = Duration(milliseconds: 2400);
const _fillIn = Duration(milliseconds: 340);
const _fillOut = Duration(milliseconds: 260);
const _swap = Duration(milliseconds: 200);

/// Tells every action button how its action ended, so the button itself can
/// confirm ("Copied", "Saved") whether it was clicked or a shortcut ran.
class ActionFeedbackController extends ChangeNotifier {
  ActionFeedbackController({this.reduceMotion = false});

  /// Set from the overlay's motion policy; buttons change state instantly.
  bool reduceMotion;

  final Map<String, ActionPhase> _phases = {};
  final Map<String, Timer> _timers = {};

  ActionPhase phaseOf(String id) => _phases[id] ?? ActionPhase.idle;

  void succeed(Iterable<String> ids) =>
      _set(ids, ActionPhase.success, _successHold);

  void fail(Iterable<String> ids) =>
      _set(ids, ActionPhase.failure, _failureHold);

  void _set(Iterable<String> ids, ActionPhase phase, Duration hold) {
    if (ids.isEmpty) {
      return;
    }
    for (final id in ids) {
      _timers[id]?.cancel();
      _phases[id] = phase;
      _timers[id] = Timer(hold, () {
        _timers.remove(id);
        _phases.remove(id);
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// Makes an [ActionFeedbackController] visible to the buttons below it.
class ActionFeedbackScope extends InheritedNotifier<ActionFeedbackController> {
  const ActionFeedbackScope({
    super.key,
    required ActionFeedbackController controller,
    required super.child,
  }) : super(notifier: controller);

  static ActionFeedbackController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ActionFeedbackScope>()
      ?.notifier;
}

/// Ids shared by the buttons and the handlers that report their outcome.
abstract final class ActionIds {
  static const copyText = 'copy-text';
  static const copyAll = 'copy-all';
  static const copyScreenshot = 'copy-screenshot';
  static const saveScreenshot = 'save-screenshot';
  static const saveFullScreenshot = 'save-full-screenshot';
  static const searchWeb = 'search-web';
  static const copyDetection = 'copy-detection';
  static const copySubject = 'copy-subject';
  static const saveSubject = 'save-subject';
}

enum FeedbackButtonKind { tonal, outlined, text, icon }

/// An action button that confirms its own result: a colour fill sweeps across
/// it, a check draws in, and the label becomes "Copied" or "Saved" before
/// easing back. Every action button in the overlay uses this one behaviour.
class FeedbackActionButton extends StatefulWidget {
  const FeedbackActionButton({
    super.key,
    this.buttonKey,
    required this.actionId,
    required this.kind,
    required this.icon,
    required this.onPressed,
    this.label,
    this.doneLabel,
    this.failureLabel = 'Failed',
    this.iconSize = 16,
    this.tooltip,
    this.focusNode,
  });

  /// Key of the real Material button inside, so tests and finders reach the
  /// button itself.
  final Key? buttonKey;

  /// Shared with [ActionFeedbackController.succeed] and `.fail`.
  final String actionId;
  final FeedbackButtonKind kind;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Null for an icon-only button.
  final String? label;
  final String? doneLabel;
  final String failureLabel;
  final double iconSize;

  /// Tooltip of an icon-only button.
  final String? tooltip;
  final FocusNode? focusNode;

  @override
  State<FeedbackActionButton> createState() => _FeedbackActionButtonState();
}

class _FeedbackActionButtonState extends State<FeedbackActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: _fillIn,
    reverseDuration: _fillOut,
  );
  ActionPhase _phase = ActionPhase.idle;
  ActionPhase _lastActive = ActionPhase.success;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ActionFeedbackScope.maybeOf(context);
    _reduceMotion =
        controller?.reduceMotion ?? MediaQuery.disableAnimationsOf(context);
    final next = controller?.phaseOf(widget.actionId) ?? ActionPhase.idle;
    if (next == _phase) {
      return;
    }
    _phase = next;
    if (next != ActionPhase.idle) {
      _lastActive = next;
      if (_reduceMotion) {
        _fill.value = 1;
      } else {
        _fill.forward(from: 0);
      }
    } else if (_reduceMotion) {
      _fill.value = 0;
    } else {
      _fill.reverse();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  String? get _shownLabel => switch (_phase) {
    ActionPhase.success => widget.doneLabel ?? widget.label,
    ActionPhase.failure => widget.failureLabel,
    ActionPhase.idle => widget.label,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failed = _lastActive == ActionPhase.failure;
    final fillColor = failed ? colors.error : AppColors.success;
    final onFill = failed ? colors.onError : Colors.white;
    return AnimatedBuilder(
      animation: _fill,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_fill.value);
        final style = ButtonStyle(
          backgroundBuilder: (context, states, child) => Stack(
            fit: StackFit.passthrough,
            children: [
              if (t > 0)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      widget.kind == FeedbackButtonKind.icon
                          ? 999
                          : AppRadii.control,
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      heightFactor: 1,
                      child: ColoredBox(color: fillColor),
                    ),
                  ),
                ),
              ?child,
            ],
          ),
        );
        final icon = _GlyphSwitcher(
          key: const Key('feedback-glyph'),
          phase: _phase,
          idle: widget.icon,
          size: widget.iconSize,
          t: t,
          onFill: onFill,
          reduceMotion: _reduceMotion,
        );
        final label = widget.label == null
            ? null
            : _LabelSwitcher(
                phase: _phase,
                text: _shownLabel!,
                widest: _longest(widget.label!, widget.doneLabel ?? ''),
                t: t,
                onFill: onFill,
                reduceMotion: _reduceMotion,
              );
        return switch (widget.kind) {
          FeedbackButtonKind.tonal => FilledButton.tonalIcon(
            key: widget.buttonKey,
            focusNode: widget.focusNode,
            onPressed: widget.onPressed,
            style: style,
            clipBehavior: Clip.antiAlias,
            icon: icon,
            label: label!,
          ),
          FeedbackButtonKind.outlined => OutlinedButton.icon(
            key: widget.buttonKey,
            focusNode: widget.focusNode,
            onPressed: widget.onPressed,
            style: style,
            clipBehavior: Clip.antiAlias,
            icon: icon,
            label: label!,
          ),
          FeedbackButtonKind.text => TextButton(
            key: widget.buttonKey,
            focusNode: widget.focusNode,
            onPressed: widget.onPressed,
            style: style,
            clipBehavior: Clip.antiAlias,
            child: label!,
          ),
          FeedbackButtonKind.icon => IconButton(
            key: widget.buttonKey,
            tooltip: widget.tooltip,
            focusNode: widget.focusNode,
            onPressed: widget.onPressed,
            style: style,
            icon: icon,
          ),
        };
      },
    );
  }

  static String _longest(String a, String b) => b.length > a.length ? b : a;
}

/// The label cross-fades with a small upward slide; an invisible copy of the
/// longer text keeps the button width fixed so nothing around it moves.
class _LabelSwitcher extends StatelessWidget {
  const _LabelSwitcher({
    required this.phase,
    required this.text,
    required this.widest,
    required this.t,
    required this.onFill,
    required this.reduceMotion,
  });

  final ActionPhase phase;
  final String text;
  final String widest;
  final double t;
  final Color onFill;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final color = Color.lerp(style.color, onFill, t);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Not a Text widget, so it is never found as a second label.
        ExcludeSemantics(
          child: Opacity(
            opacity: 0,
            child: RichText(
              text: TextSpan(text: widest, style: style),
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : _swap,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            text,
            key: ValueKey(phase),
            style: style.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The icon becomes a drawing check (or a cross) and back.
class _GlyphSwitcher extends StatelessWidget {
  const _GlyphSwitcher({
    super.key,
    required this.phase,
    required this.idle,
    required this.size,
    required this.t,
    required this.onFill,
    required this.reduceMotion,
  });

  final ActionPhase phase;
  final IconData idle;
  final double size;
  final double t;
  final Color onFill;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final base = IconTheme.of(context).color;
    final color = Color.lerp(base, onFill, t) ?? onFill;
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : _swap,
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: switch (phase) {
          ActionPhase.success => TweenAnimationBuilder<double>(
            key: const ValueKey('check'),
            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => CustomPaint(
              size: Size.square(size),
              painter: CheckPainter(progress: progress, color: onFill),
            ),
          ),
          ActionPhase.failure => Icon(
            Icons.close_rounded,
            key: const ValueKey('cross'),
            size: size,
            color: onFill,
          ),
          ActionPhase.idle => Icon(
            idle,
            key: const ValueKey('idle'),
            size: size,
            color: color,
          ),
        },
      ),
    );
  }
}

/// A check mark that draws itself from its short stroke to its long stroke.
class CheckPainter extends CustomPainter {
  const CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Offset(size.width * 0.18, size.height * 0.54);
    final b = Offset(size.width * 0.42, size.height * 0.76);
    final c = Offset(size.width * 0.84, size.height * 0.28);
    final shortLength = (b - a).distance;
    final longLength = (c - b).distance;
    final drawn = (shortLength + longLength) * progress.clamp(0, 1);
    final path = Path()..moveTo(a.dx, a.dy);
    if (drawn <= shortLength) {
      final point = Offset.lerp(a, b, drawn / shortLength)!;
      path.lineTo(point.dx, point.dy);
    } else {
      final point = Offset.lerp(b, c, (drawn - shortLength) / longLength)!;
      path
        ..lineTo(b.dx, b.dy)
        ..lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(CheckPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
