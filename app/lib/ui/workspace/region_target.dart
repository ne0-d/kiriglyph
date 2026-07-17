import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/selection/region_selection_provider.dart';
import 'package:ubuntu_live_text/ui/workspace/region_painter.dart';

/// One OCR region on the canvas: paints its polygon and owns the pointer,
/// keyboard and accessibility behavior for it.
///
/// The parent positions this widget at the region's hit rectangle and supplies
/// [polygon] relative to it, so painting and hit testing share one geometry.
class RegionTarget extends ConsumerStatefulWidget {
  const RegionTarget({
    super.key,
    required this.region,
    required this.readingIndex,
    required this.polygon,
  });

  final TextRegion region;

  /// Zero-based position in reading order.
  final int readingIndex;

  final List<Offset> polygon;

  @override
  ConsumerState<RegionTarget> createState() => _RegionTargetState();
}

class _RegionTargetState extends ConsumerState<RegionTarget> {
  bool _focused = false;

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
    final hovered = ref.watch(hoveredRegionProvider.select((h) => h == id));
    final hover = ref.read(hoveredRegionProvider.notifier);

    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.readingIndex.toDouble()),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        label: 'Line ${widget.readingIndex + 1}: ${widget.region.text}',
        onTap: _activate,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
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
                hovered: hovered,
                focused: _focused,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
