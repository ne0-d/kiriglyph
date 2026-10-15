import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/workspace/region_painter.dart';

/// One OCR region on the canvas: paints its polygon and owns the pointer,
/// keyboard and accessibility behavior for it.
///
/// The parent positions this widget at the region's hit rectangle and supplies
/// [polygon] relative to it, so painting and hit testing share one geometry.
class RegionTarget extends ConsumerStatefulWidget {
  const RegionTarget({
    super.key,
    required this.region,
    this.focusable = true,
    required this.readingIndex,
    required this.polygon,
  });

  final TextRegion region;

  /// Whether Tab can stop on this line; off in the overlay, where the canvas
  /// owns the keyboard.
  final bool focusable;

  /// Zero-based position in reading order.
  final int readingIndex;

  final List<Offset> polygon;

  @override
  ConsumerState<RegionTarget> createState() => _RegionTargetState();
}

class _RegionTargetState extends ConsumerState<RegionTarget> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'recognized line',
    canRequestFocus: widget.focusable,
    skipTraversal: !widget.focusable,
  );
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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
    final id = widget.region.id;
    final selected = ref.watch(
      regionSelectionProvider.select((s) => s.isSelected(id)),
    );
    final hover = ref.read(hoveredRegionProvider.notifier);

    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.readingIndex.toDouble()),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        sortKey: OrdinalSortKey(widget.readingIndex.toDouble()),
        label: 'Line ${widget.readingIndex + 1}: ${widget.region.text}',
        onTap: _activate,
        child: FocusableActionDetector(
          focusNode: _focusNode,
          mouseCursor: SystemMouseCursors.text,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          onShowHoverHighlight: (value) =>
              value ? hover.enter(id) : hover.leave(id),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _activate,
            child: CustomPaint(
              painter: RegionPainter(
                polygon: widget.polygon,
                selected: selected,
                focused: _focused,
                selectionColor:
                    Theme.of(context).textSelectionTheme.selectionColor ??
                    AppColors.ubuntuOrange.withValues(alpha: 0.30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
