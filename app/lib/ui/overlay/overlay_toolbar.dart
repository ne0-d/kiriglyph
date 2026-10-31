import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiriglyph/detection/text_detectors.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/overlay/action_feedback.dart';
import 'package:kiriglyph/ui/overlay/toolbar_move_controls.dart';

/// Keys shown in the toolbar tooltips; the handlers live in the overlay
/// screen and the canvas.
const copyTooltip =
    'Copy selected text (Ctrl+C)\n'
    'Select a paragraph: Ctrl+Shift+Down or Ctrl+Shift+Up';
const copyAllTooltip = 'Copy all recognized text\nSelect all: Ctrl+A';
const closeTooltip = 'Close (Esc)';
const copySubjectTooltip = 'Copy selected subject image (Ctrl+C)';
const saveSubjectTooltip =
    'Save selected subject (Ctrl+S)\nSave as… (Ctrl+Shift+S)';
const removeSubjectTooltip = 'Remove selection (Backspace or Delete)';
const searchWebTooltip =
    'Search the web\nSelected text leaves this computer only when clicked.';

const _chromeRadius = 16.0;

/// The one floating surface every overlay toolbar and chip shares: a soft
/// rounded panel with a hairline border and a deep, quiet shadow.
class OverlayChrome extends StatelessWidget {
  const OverlayChrome({super.key, required this.child, this.surfaceKey});

  /// Key of the [Material] itself, which tests and finders look up.
  final Key? surfaceKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return Material(
      key: surfaceKey,
      color: highContrast
          ? colors.surfaceContainerLow
          : colors.surfaceContainerLow.withValues(alpha: 0.95),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_chromeRadius),
        side: BorderSide(
          color: highContrast
              ? colors.onSurface
              : colors.outlineVariant.withValues(alpha: 0.7),
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(6), child: child),
    );
  }
}

/// A thin vertical rule between groups of controls.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.8),
  );
}

/// An icon button without a confirm cycle (it starts something rather than
/// finishing it), sized and shaped like [FeedbackActionButton].
class OverlayIconButton extends StatelessWidget {
  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.focusNode,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => IconButton(
    focusNode: focusNode,
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 18,
    style: IconButton.styleFrom(
      visualDensity: VisualDensity.standard,
      maximumSize: const Size.square(overlayIconButtonSize),
      fixedSize: const Size.square(overlayIconButtonSize),
      minimumSize: const Size.square(overlayIconButtonSize),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(overlayIconButtonRadius),
      ),
    ),
    icon: Icon(icon),
  );
}

TextStyle? _statusStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  final highContrast = MediaQuery.highContrastOf(context);
  return Theme.of(context).textTheme.bodySmall?.copyWith(
    color: highContrast
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.8),
    fontWeight: FontWeight.w600,
  );
}

/// The small floating toolbar over the frozen display.
///
/// Every action is an icon; hover shows its name. Tab visits Copy, Copy all,
/// then Close after the canvas and any selection chips. Subject actions live
/// in [SubjectActionChip].
class OverlayToolbar extends StatelessWidget {
  const OverlayToolbar({
    super.key,
    required this.status,
    this.statusIsLive = false,
    required this.onCopy,
    required this.onCopyAll,
    this.copyTooltipMessage,
    this.copyAllTooltipMessage,
    required this.tool,
    required this.onToolChanged,
    required this.onSaveFullScreenshot,
    this.closeFocusNode,
    this.copyFocusNode,
    this.copyAllFocusNode,
    this.onCloseTabForward,
    required this.onClose,
  });

  /// Progress, selection, copy confirmation, or failure text.
  final String status;

  /// Whether the status is a live region, for platforms where announcements
  /// are unavailable. Only transient states set it, never recognized text.
  final bool statusIsLive;
  final VoidCallback? onCopy;
  final VoidCallback? onCopyAll;
  final String? copyTooltipMessage;
  final String? copyAllTooltipMessage;
  final SelectionTool tool;
  final ValueChanged<SelectionTool> onToolChanged;
  final VoidCallback? onSaveFullScreenshot;
  final FocusNode? closeFocusNode;
  final FocusNode? copyFocusNode;
  final FocusNode? copyAllFocusNode;
  final VoidCallback? onCloseTabForward;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final move = ToolbarMoveControls.maybeOf(context);
    return OverlayChrome(
      surfaceKey: const Key('overlay-toolbar'),
      // Wraps instead of overflowing when text is scaled up.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 96,
              maxWidth: 280 * math.max(1, scale),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Semantics(
                liveRegion: statusIsLive,
                child: Text(
                  status,
                  key: const Key('overlay-status'),
                  style: _statusStyle(context),
                ),
              ),
            ),
          ),
          const _GroupDivider(),
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              descendantsAreFocusable: false,
              child: SegmentedButton<SelectionTool>(
                key: const Key('overlay-selection-tool-switch'),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(40, overlayIconButtonSize),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide.none,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      overlayIconButtonRadius,
                    ),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: SelectionTool.rectangle,
                    tooltip: 'Rectangle',
                    icon: Icon(Icons.crop_square_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: SelectionTool.twoClicks,
                    tooltip: 'Two clicks',
                    icon: Icon(Icons.ads_click_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: SelectionTool.freeDraw,
                    tooltip: 'Free draw',
                    icon: Icon(Icons.gesture_rounded, size: 18),
                  ),
                ],
                selected: {tool},
                onSelectionChanged: (selected) =>
                    onToolChanged(selected.single),
              ),
            ),
          ),
          const _GroupDivider(),
          FocusTraversalOrder(
            order: const NumericFocusOrder(5),
            child: FeedbackActionButton(
              buttonKey: const Key('overlay-copy'),
              actionId: ActionIds.copyText,
              tonal: true,
              focusNode: copyFocusNode,
              onPressed: onCopy,
              icon: Icons.content_copy_rounded,
              tooltip: copyTooltipMessage ?? copyTooltip,
              doneTooltip: 'Copied',
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(6),
            child: FeedbackActionButton(
              buttonKey: const Key('overlay-copy-all'),
              actionId: ActionIds.copyAll,
              focusNode: copyAllFocusNode,
              onPressed: onCopyAll,
              icon: Icons.copy_all_rounded,
              tooltip: copyAllTooltipMessage ?? copyAllTooltip,
              doneTooltip: 'Copied',
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(99),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              descendantsAreFocusable: false,
              child: FeedbackActionButton(
                buttonKey: const Key('overlay-save-full-screenshot'),
                actionId: ActionIds.saveFullScreenshot,
                tooltip: 'Save full screenshot (Ctrl+Shift+F)',
                doneTooltip: 'Saved',
                onPressed: onSaveFullScreenshot,
                icon: Icons.wallpaper_rounded,
              ),
            ),
          ),
          const _GroupDivider(),
          ?move?.menu,
          FocusTraversalOrder(
            order: const NumericFocusOrder(7),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.tab): () {
                  onCloseTabForward?.call();
                },
              },
              child: OverlayIconButton(
                key: const Key('overlay-close'),
                focusNode: closeFocusNode,
                tooltip: closeTooltip,
                onPressed: onClose,
                icon: Icons.close_rounded,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SelectionActionChip extends StatelessWidget {
  const SelectionActionChip({
    super.key,
    required this.canCopyText,
    required this.canLiftObject,
    required this.canCopyScreenshot,
    required this.canSaveScreenshot,
    required this.canSearchWeb,
    required this.detections,
    this.confirmTarget,
    this.onCopyText,
    this.onLiftObject,
    this.onCopyScreenshot,
    this.onSaveScreenshot,
    this.onSearchWeb,
    this.onOpenDetection,
    this.onCopyDetection,
    this.onConfirmOpen,
    this.onCancelOpen,
  });

  final bool canCopyText;
  final bool canLiftObject;
  final bool canCopyScreenshot;
  final bool canSaveScreenshot;
  final bool canSearchWeb;
  final List<DetectedTextItem> detections;
  final String? confirmTarget;
  final VoidCallback? onCopyText;
  final VoidCallback? onLiftObject;
  final VoidCallback? onCopyScreenshot;
  final VoidCallback? onSaveScreenshot;
  final VoidCallback? onSearchWeb;
  final void Function(DetectedTextItem item)? onOpenDetection;
  final void Function(DetectedTextItem item)? onCopyDetection;
  final VoidCallback? onConfirmOpen;
  final VoidCallback? onCancelOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OverlayChrome(
      surfaceKey: const Key('selection-action-chip'),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (canCopyText)
            FeedbackActionButton(
              buttonKey: const Key('selection-copy-text'),
              actionId: ActionIds.copyText,
              tonal: true,
              onPressed: onCopyText,
              icon: Icons.text_snippet_rounded,
              tooltip: 'Copy text',
              doneTooltip: 'Copied',
            ),
          if (canLiftObject)
            OverlayIconButton(
              key: const Key('selection-lift-object'),
              onPressed: onLiftObject,
              icon: Icons.auto_awesome_motion_rounded,
              tooltip: 'Lift object',
            ),
          if (canCopyScreenshot)
            FeedbackActionButton(
              buttonKey: const Key('selection-copy-screenshot'),
              actionId: ActionIds.copyScreenshot,
              onPressed: onCopyScreenshot,
              icon: Icons.content_copy_rounded,
              tooltip: 'Copy screenshot',
              doneTooltip: 'Copied',
            ),
          if (canSaveScreenshot)
            FeedbackActionButton(
              buttonKey: const Key('selection-save-screenshot'),
              actionId: ActionIds.saveScreenshot,
              onPressed: onSaveScreenshot,
              icon: Icons.save_alt_rounded,
              tooltip: 'Save screenshot',
              doneTooltip: 'Saved',
            ),
          if (canSearchWeb)
            FeedbackActionButton(
              buttonKey: const Key('selection-search-web'),
              actionId: ActionIds.searchWeb,
              onPressed: onSearchWeb,
              icon: Icons.travel_explore_rounded,
              tooltip: searchWebTooltip,
              doneTooltip: 'Opened',
            ),
          for (final item in detections) ...[
            const _GroupDivider(),
            if (_canOpen(item))
              OverlayIconButton(
                key: Key('selection-open-${item.kind.name}'),
                onPressed: () => onOpenDetection?.call(item),
                icon: _openIcon(item.kind),
                tooltip: _openLabel(item.kind),
              ),
            FeedbackActionButton(
              buttonKey: Key('selection-copy-${item.kind.name}'),
              actionId: ActionIds.copyDetection,
              onPressed: () => onCopyDetection?.call(item),
              icon: Icons.content_copy_rounded,
              tooltip: _copyLabel(item.kind),
              doneTooltip: 'Copied',
            ),
          ],
          if (confirmTarget case final target?)
            DecoratedBox(
              key: const Key('selection-open-confirmation'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(overlayIconButtonRadius),
                color: colors.surfaceContainerHighest,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text('Open $target?'),
                    ),
                    FilledButton(
                      key: const Key('selection-confirm-open'),
                      onPressed: onConfirmOpen,
                      child: const Text('Open'),
                    ),
                    TextButton(
                      key: const Key('selection-cancel-open'),
                      onPressed: onCancelOpen,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _openLabel(DetectedTextKind kind) => switch (kind) {
    DetectedTextKind.link => 'Open link',
    DetectedTextKind.email => 'Compose email',
    DetectedTextKind.phone => 'Copy number',
    DetectedTextKind.code => 'Open code content',
  };

  static String _copyLabel(DetectedTextKind kind) => switch (kind) {
    DetectedTextKind.link => 'Copy link',
    DetectedTextKind.email => 'Copy email address',
    DetectedTextKind.phone => 'Copy number',
    DetectedTextKind.code => 'Copy code content',
  };

  static IconData _openIcon(DetectedTextKind kind) => switch (kind) {
    DetectedTextKind.link => Icons.open_in_new_rounded,
    DetectedTextKind.email => Icons.mail_outline_rounded,
    DetectedTextKind.phone => Icons.phone_rounded,
    DetectedTextKind.code => Icons.qr_code_2_rounded,
  };

  static bool _canOpen(DetectedTextItem item) =>
      item.kind != DetectedTextKind.phone && item.target.isNotEmpty;
}

class SubjectActionChip extends StatelessWidget {
  const SubjectActionChip({
    super.key,
    required this.status,
    required this.exporting,
    required this.onCopy,
    required this.onSave,
    required this.onRemove,
  });

  final String? status;
  final bool exporting;
  final VoidCallback? onCopy;
  final VoidCallback? onSave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return OverlayChrome(
      surfaceKey: const Key('subject-action-chip'),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (exporting) ...[
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    exporting
                        ? 'Exporting subject…'
                        : status ?? 'Subject selected',
                    key: const Key('subject-chip-status'),
                    style: _statusStyle(context),
                  ),
                ),
              ],
            ),
          ),
          const _GroupDivider(),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: FeedbackActionButton(
              buttonKey: const Key('overlay-copy-subject-image'),
              actionId: ActionIds.copySubject,
              tonal: true,
              onPressed: exporting ? null : onCopy,
              icon: Icons.image_rounded,
              tooltip: copySubjectTooltip,
              doneTooltip: 'Copied',
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: FeedbackActionButton(
              buttonKey: const Key('overlay-save-subject-png'),
              actionId: ActionIds.saveSubject,
              onPressed: exporting ? null : onSave,
              icon: Icons.save_alt_rounded,
              tooltip: saveSubjectTooltip,
              doneTooltip: 'Saved',
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: OverlayIconButton(
              key: const Key('overlay-remove-subject'),
              tooltip: removeSubjectTooltip,
              onPressed: onRemove,
              icon: Icons.close_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class LoopHintChip extends StatelessWidget {
  const LoopHintChip({
    super.key,
    required this.selectedAsText,
    required this.onFlip,
  });

  final bool selectedAsText;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return OverlayChrome(
      surfaceKey: const Key('selection-loop-hint-chip'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              selectedAsText ? 'Selected as text' : 'Selected as image',
              style: _statusStyle(context),
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: OverlayIconButton(
              key: const Key('selection-loop-flip'),
              onPressed: onFlip,
              icon: Icons.swap_horiz_rounded,
              tooltip: selectedAsText
                  ? 'Select as image instead'
                  : 'Select as text instead',
            ),
          ),
        ],
      ),
    );
  }
}
