import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Material(
      key: const Key('overlay-toolbar'),
      color: colors.surface,
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highContrast ? colors.onSurface : colors.outlineVariant,
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        // Wraps instead of overflowing when text is scaled up.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
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
              order: const NumericFocusOrder(5),
              child: Tooltip(
                message: copyTooltipMessage ?? copyTooltip,
                child: FilledButton.tonalIcon(
                  key: const Key('overlay-copy'),
                  onPressed: onCopy,
                  icon: const Icon(Icons.content_copy_rounded, size: 16),
                  label: const Text('Copy'),
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(6),
              child: Tooltip(
                message: copyAllTooltipMessage ?? copyAllTooltip,
                child: OutlinedButton.icon(
                  key: const Key('overlay-copy-all'),
                  onPressed: onCopyAll,
                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                  label: const Text('Copy all'),
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(7),
              child: IconButton(
                key: const Key('overlay-close'),
                tooltip: closeTooltip,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      color: colors.surface,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highContrast ? colors.onSurface : colors.outlineVariant,
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
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
                child: FilledButton.tonalIcon(
                  key: const Key('overlay-copy-subject-image'),
                  onPressed: exporting ? null : onCopy,
                  icon: const Icon(Icons.image_rounded, size: 16),
                  label: const Text('Copy image'),
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: Tooltip(
                message: saveSubjectTooltip,
                child: OutlinedButton.icon(
                  key: const Key('overlay-save-subject-png'),
                  onPressed: exporting ? null : onSave,
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: const Text('Save PNG'),
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
      color: colors.surface,
      elevation: 7,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highContrast ? colors.onSurface : colors.outlineVariant,
          width: highContrast ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
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
