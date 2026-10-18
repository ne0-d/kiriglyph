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
    'Save selected subject to Pictures (Ctrl+S)\nSave as… (Ctrl+Shift+S)';
const removeSubjectTooltip = 'Remove selection (Backspace or Delete)';
const searchWebTooltip =
    'Search the web\nSelected text leaves this computer only when clicked.';

/// The small floating toolbar over the frozen display.
///
/// Tab visits Copy, Copy all, then Close after the canvas and any selection
/// chips. Subject actions live in [SubjectActionChip].
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
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final move = ToolbarMoveControls.maybeOf(context);
    return Material(
      key: const Key('overlay-toolbar'),
      color: colors.surfaceContainerLow,
      elevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.18),
      surfaceTintColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.surface),
        side: BorderSide(
          color: highContrast ? colors.onSurface : colors.outlineVariant,
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        // Wraps instead of overflowing when text is scaled up.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (move != null) move.grip,
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 120,
                maxWidth: 320 * math.max(1, scale),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Semantics(
                  liveRegion: statusIsLive,
                  child: Text(
                    status,
                    key: const Key('overlay-status'),
                    style: text.bodySmall?.copyWith(
                      color: highContrast
                          ? colors.onSurface
                          : colors.onSurface.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                descendantsAreFocusable: false,
                child: SegmentedButton<SelectionTool>(
                  key: const Key('overlay-selection-tool-switch'),
                  segments: const [
                    ButtonSegment(
                      value: SelectionTool.rectangle,
                      label: Text('Rectangle'),
                      icon: Icon(Icons.crop_square_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: SelectionTool.twoClicks,
                      label: Text('Two clicks'),
                      tooltip: 'Click two opposite corners',
                      icon: Icon(Icons.touch_app_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: SelectionTool.freeDraw,
                      label: Text('Free draw'),
                      icon: Icon(Icons.gesture_rounded, size: 16),
                    ),
                  ],
                  selected: {tool},
                  onSelectionChanged: (selected) =>
                      onToolChanged(selected.single),
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(5),
              child: Tooltip(
                message: copyTooltipMessage ?? copyTooltip,
                child: FeedbackActionButton(
                  buttonKey: const Key('overlay-copy'),
                  actionId: ActionIds.copyText,
                  kind: FeedbackButtonKind.tonal,
                  focusNode: copyFocusNode,
                  onPressed: onCopy,
                  icon: Icons.content_copy_rounded,
                  label: 'Copy',
                  doneLabel: 'Copied',
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(6),
              child: Tooltip(
                message: copyAllTooltipMessage ?? copyAllTooltip,
                child: FeedbackActionButton(
                  buttonKey: const Key('overlay-copy-all'),
                  actionId: ActionIds.copyAll,
                  kind: FeedbackButtonKind.outlined,
                  focusNode: copyAllFocusNode,
                  onPressed: onCopyAll,
                  icon: Icons.copy_all_rounded,
                  label: 'Copy all',
                  doneLabel: 'Copied',
                ),
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
                  kind: FeedbackButtonKind.icon,
                  tooltip: 'Save full screenshot (Ctrl+Shift+F)',
                  onPressed: onSaveFullScreenshot,
                  icon: Icons.wallpaper_rounded,
                  iconSize: 18,
                ),
              ),
            ),
            if (move != null) move.menu,
            FocusTraversalOrder(
              order: const NumericFocusOrder(7),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.tab): () {
                    onCloseTabForward?.call();
                  },
                },
                child: IconButton(
                  key: const Key('overlay-close'),
                  focusNode: closeFocusNode,
                  tooltip: closeTooltip,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
            ),
          ],
        ),
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
    final highContrast = MediaQuery.highContrastOf(context);
    return Material(
      key: const Key('selection-action-chip'),
      color: colors.surfaceContainerLow,
      elevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.16),
      surfaceTintColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.surface),
        side: BorderSide(
          color: highContrast ? colors.onSurface : colors.outlineVariant,
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (canCopyText)
              FeedbackActionButton(
                buttonKey: const Key('selection-copy-text'),
                actionId: ActionIds.copyText,
                kind: FeedbackButtonKind.tonal,
                onPressed: onCopyText,
                icon: Icons.text_snippet_rounded,
                label: 'Copy text',
                doneLabel: 'Copied',
              ),
            if (canLiftObject)
              OutlinedButton.icon(
                key: const Key('selection-lift-object'),
                onPressed: onLiftObject,
                icon: const Icon(Icons.auto_awesome_motion_rounded, size: 16),
                label: const Text('Lift object'),
              ),
            if (canCopyScreenshot)
              FeedbackActionButton(
                buttonKey: const Key('selection-copy-screenshot'),
                actionId: ActionIds.copyScreenshot,
                kind: FeedbackButtonKind.outlined,
                onPressed: onCopyScreenshot,
                icon: Icons.content_copy_rounded,
                label: 'Copy screenshot',
                doneLabel: 'Copied',
              ),
            if (canSaveScreenshot)
              FeedbackActionButton(
                buttonKey: const Key('selection-save-screenshot'),
                actionId: ActionIds.saveScreenshot,
                kind: FeedbackButtonKind.outlined,
                onPressed: onSaveScreenshot,
                icon: Icons.save_alt_rounded,
                label: 'Save screenshot',
                doneLabel: 'Saved',
              ),
            if (canSearchWeb)
              Tooltip(
                message: searchWebTooltip,
                child: FeedbackActionButton(
                  buttonKey: const Key('selection-search-web'),
                  actionId: ActionIds.searchWeb,
                  kind: FeedbackButtonKind.outlined,
                  onPressed: onSearchWeb,
                  icon: Icons.travel_explore_rounded,
                  label: 'Search the web',
                  doneLabel: 'Opened',
                ),
              ),
            for (final item in detections) ...[
              if (_canOpen(item))
                OutlinedButton(
                  key: Key('selection-open-${item.kind.name}'),
                  onPressed: () => onOpenDetection?.call(item),
                  child: Text(_openLabel(item.kind)),
                ),
              FeedbackActionButton(
                buttonKey: Key('selection-copy-${item.kind.name}'),
                actionId: ActionIds.copyDetection,
                kind: FeedbackButtonKind.text,
                onPressed: () => onCopyDetection?.call(item),
                icon: Icons.content_copy_rounded,
                label: 'Copy',
                doneLabel: 'Copied',
              ),
            ],
            if (confirmTarget case final target?)
              DecoratedBox(
                key: const Key('selection-open-confirmation'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  color: colors.surfaceContainerHighest,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
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
      ),
    );
  }

  static String _openLabel(DetectedTextKind kind) => switch (kind) {
    DetectedTextKind.link => 'Open link',
    DetectedTextKind.email => 'Compose email',
    DetectedTextKind.phone => 'Copy number',
    DetectedTextKind.code => 'Open code content',
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
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return Material(
      key: const Key('subject-action-chip'),
      color: colors.surfaceContainerLow,
      elevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.16),
      surfaceTintColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.surface),
        side: BorderSide(
          color: highContrast ? colors.onSurface : colors.outlineVariant,
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (exporting)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                exporting ? 'Exporting subject…' : status ?? 'Subject selected',
                key: const Key('subject-chip-status'),
                style: text.bodySmall?.copyWith(
                  color: highContrast
                      ? colors.onSurface
                      : colors.onSurface.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: Tooltip(
                message: copySubjectTooltip,
                child: FeedbackActionButton(
                  buttonKey: const Key('overlay-copy-subject-image'),
                  actionId: ActionIds.copySubject,
                  kind: FeedbackButtonKind.tonal,
                  onPressed: exporting ? null : onCopy,
                  icon: Icons.image_rounded,
                  label: 'Copy image',
                  doneLabel: 'Copied',
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: Tooltip(
                message: saveSubjectTooltip,
                child: FeedbackActionButton(
                  buttonKey: const Key('overlay-save-subject-png'),
                  actionId: ActionIds.saveSubject,
                  kind: FeedbackButtonKind.outlined,
                  onPressed: exporting ? null : onSave,
                  icon: Icons.save_alt_rounded,
                  label: 'Save PNG',
                  doneLabel: 'Saved',
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: IconButton(
                key: const Key('overlay-remove-subject'),
                tooltip: removeSubjectTooltip,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
          ],
        ),
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
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return Material(
      key: const Key('selection-loop-hint-chip'),
      color: colors.surfaceContainerLow,
      elevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.14),
      surfaceTintColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.surface),
        side: BorderSide(
          color: highContrast ? colors.onSurface : colors.outlineVariant,
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(selectedAsText ? 'Selected as text' : 'Selected as image'),
            const Text('·'),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: TextButton(
                key: const Key('selection-loop-flip'),
                onPressed: onFlip,
                child: Text(
                  selectedAsText
                      ? 'Select as image instead'
                      : 'Select as text instead',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
