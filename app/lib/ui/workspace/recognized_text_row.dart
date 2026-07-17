import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/selection/region_selection_provider.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';

/// One recognized line: a reading-order number and ordinary selectable text.
///
/// The row mirrors the region's selected and hovered state. It is
/// deliberately not clickable so the text keeps normal character-level
/// selection through the surrounding [SelectionArea].
class RecognizedTextRow extends ConsumerWidget {
  const RecognizedTextRow({
    super.key,
    required this.region,
    required this.number,
    required this.numberWidth,
  });

  final TextRegion region;

  /// One-based reading-order number.
  final int number;

  final double numberWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = region.id;
    final selected = ref.watch(
      regionSelectionProvider.select((s) => s.isSelected(id)),
    );
    final hovered = ref.watch(hoveredRegionProvider.select((h) => h == id));
    final hover = ref.read(hoveredRegionProvider.notifier);

    ref.listen(regionSelectionProvider.select((s) => s.isSelected(id)), (
      previous,
      next,
    ) {
      if (next && previous != true && context.mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 120),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });

    return Semantics(
      key: Key('ocr-row-$id'),
      container: true,
      selected: selected,
      child: MouseRegion(
        onEnter: (_) => hover.enter(id),
        onExit: (_) => hover.leave(id),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.ubuntuOrange.withValues(alpha: 0.10)
                : hovered
                ? AppColors.shell
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                width: 3,
                color: selected ? AppColors.ubuntuOrange : Colors.transparent,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 7, 16, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SelectionContainer.disabled(
                  child: SizedBox(
                    width: numberWidth,
                    child: Text(
                      '$number',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: selected ? AppColors.ink : AppColors.muted,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    region.text,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
