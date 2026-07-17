import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/selection/region_selection_provider.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';
import 'package:ubuntu_live_text/ui/app_header.dart' show fileNameOf;
import 'package:ubuntu_live_text/ui/workspace/capture_image.dart';
import 'package:ubuntu_live_text/ui/workspace/fitted_image_geometry.dart';
import 'package:ubuntu_live_text/ui/workspace/region_target.dart';

const _canvasPadding = 24.0;
const _minZoom = 1.0;
const _maxZoom = 4.0;
const _zoomStep = 0.25;

/// Dark inspection canvas: the image fitted with `BoxFit.contain`, with OCR
/// regions painted and hit-tested from the same fitted rectangle.
class CaptureCanvas extends ConsumerStatefulWidget {
  const CaptureCanvas({
    super.key,
    required this.imagePath,
    required this.ocrResult,
  });

  final String imagePath;
  final OcrResult ocrResult;

  @override
  ConsumerState<CaptureCanvas> createState() => _CaptureCanvasState();
}

class _CaptureCanvasState extends ConsumerState<CaptureCanvas> {
  final TransformationController _transformation = TransformationController();
  double _zoom = _minZoom;

  @override
  void initState() {
    super.initState();
    _transformation.addListener(_updateZoom);
  }

  @override
  void dispose() {
    _transformation
      ..removeListener(_updateZoom)
      ..dispose();
    super.dispose();
  }

  void _updateZoom() {
    final next = _transformation.value.getMaxScaleOnAxis();
    if ((next - _zoom).abs() > 0.001) {
      setState(() => _zoom = next);
    }
  }

  void _setZoom(double value) {
    final next = value.clamp(_minZoom, _maxZoom);
    _transformation.value = Matrix4.diagonal3Values(next, next, 1);
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(regionSelectionProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final padding = math.min(
          _canvasPadding,
          math.min(size.width, size.height) / 4,
        );
        final geometry = FittedImageGeometry.contain(
          bounds: Rect.fromLTWH(
            padding,
            padding,
            math.max(0, size.width - 2 * padding),
            math.max(0, size.height - 2 * padding),
          ),
          imageSize: Size(
            widget.ocrResult.imageWidth.toDouble(),
            widget.ocrResult.imageHeight.toDouble(),
          ),
        );

        // Larger boxes first so smaller ones stay on top and win overlaps.
        final targets = [...selection.regions]
          ..sort(
            (a, b) =>
                _area(geometry.hitRect(b))
                    .compareTo(_area(geometry.hitRect(a))),
          );

        return ColoredBox(
          key: const Key('capture-canvas'),
          color: AppColors.canvas,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _transformation,
                minScale: _minZoom,
                maxScale: _maxZoom,
                panEnabled: _zoom > _minZoom,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: ref.read(regionSelectionProvider.notifier).clear,
                  excludeFromSemantics: true,
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!geometry.destination.isEmpty)
                          Positioned.fromRect(
                            rect: geometry.destination,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x66000000),
                                    blurRadius: 16,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: CaptureImage(
                                key: const Key('capture-image'),
                                imagePath: widget.imagePath,
                                label: 'Image ${fileNameOf(widget.imagePath)}',
                              ),
                            ),
                          ),
                        if (!geometry.destination.isEmpty)
                          for (final region in targets)
                            Positioned.fromRect(
                              key: Key('ocr-region-${region.id}'),
                              rect: geometry.hitRect(region),
                              child: RegionTarget(
                                region: region,
                                readingIndex: selection.indexOf(region.id) ?? 0,
                                polygon: [
                                  for (final point in geometry.regionPolygon(
                                    region,
                                  ))
                                    point - geometry.hitRect(region).topLeft,
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _ZoomControls(
                  zoom: _zoom,
                  onZoomOut: _zoom > _minZoom
                      ? () => _setZoom(_zoom - _zoomStep)
                      : null,
                  onReset: _zoom > _minZoom ? () => _setZoom(_minZoom) : null,
                  onZoomIn: _zoom < _maxZoom
                      ? () => _setZoom(_zoom + _zoomStep)
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static double _area(Rect rect) => rect.width * rect.height;
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.zoom,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final double zoom;
  final VoidCallback? onZoomOut;
  final VoidCallback? onReset;
  final VoidCallback? onZoomIn;

  @override
  Widget build(BuildContext context) {
    const iconConstraints = BoxConstraints.tightFor(width: 36, height: 36);
    const iconPadding = EdgeInsets.zero;

    return Material(
      color: AppColors.aubergine.withValues(alpha: 0.94),
      elevation: 2,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('zoom-out'),
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            constraints: iconConstraints,
            padding: iconPadding,
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.remove, size: 18),
          ),
          TextButton(
            key: const Key('zoom-reset'),
            onPressed: onReset,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white70,
              minimumSize: const Size(54, 36),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              shape: const RoundedRectangleBorder(),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text('${(zoom * 100).round()}%'),
          ),
          IconButton(
            key: const Key('zoom-in'),
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            constraints: iconConstraints,
            padding: iconPadding,
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}
