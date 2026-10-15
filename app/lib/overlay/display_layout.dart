import 'dart:math' as math;

/// One display in GDK's logical layout: application pixels, after rotation,
/// so a portrait display is already taller than wide.
class LogicalMonitor {
  const LogicalMonitor({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.scaleFactor = 1,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  /// GDK's integer scale factor: the display scale, rounded up when it is
  /// fractional.
  final int scaleFactor;

  int get right => x + width;
  int get bottom => y + height;

  @override
  String toString() =>
      'LogicalMonitor($x, $y, ${width}x$height, @$scaleFactor)';
}

/// Where the native runner placed the overlay window: every display, and the
/// one under the window.
class DisplayPlacement {
  const DisplayPlacement({required this.monitors, required this.targetIndex});

  /// Parses the `showOverlay` reply from the `kiriglyph/app` channel.
  /// Throws [FormatException] for anything else.
  factory DisplayPlacement.fromChannel(Object? value) {
    if (value is! Map) {
      throw const FormatException('placement is not a map');
    }
    final target = value['target'];
    final monitors = value['monitors'];
    if (target is! int || monitors is! List) {
      throw const FormatException('placement is missing fields');
    }
    int field(Map monitor, String name) {
      final number = monitor[name];
      if (number is! int) {
        throw FormatException('monitor $name is not an integer');
      }
      return number;
    }

    return DisplayPlacement(
      targetIndex: target,
      monitors: [
        for (final monitor in monitors)
          if (monitor is Map)
            LogicalMonitor(
              x: field(monitor, 'x'),
              y: field(monitor, 'y'),
              width: field(monitor, 'width'),
              height: field(monitor, 'height'),
              scaleFactor: field(monitor, 'scaleFactor'),
            )
          else
            throw const FormatException('monitor is not a map'),
      ],
    );
  }

  final List<LogicalMonitor> monitors;
  final int targetIndex;
}

/// An integer rectangle in image pixels.
class PixelRect {
  const PixelRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is PixelRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PixelRect($left, $top, ${width}x$height)';
}

/// The part of a spanning capture that shows one display.
class OverlayCrop {
  const OverlayCrop({
    required this.source,
    required this.outputWidth,
    required this.outputHeight,
    required this.imageScale,
  });

  /// The display's pixels inside the spanning capture.
  final PixelRect source;

  /// Size of the cropped frame. Smaller than [source] when GNOME upsampled a
  /// lower-scale display to the capture's scale.
  final int outputWidth;
  final int outputHeight;

  /// Capture pixels per logical pixel: GNOME renders the whole capture at the
  /// largest display scale.
  final double imageScale;

  bool get resamples =>
      outputWidth != source.width || outputHeight != source.height;
}

/// The capture does not match the reported display layout, so no crop can be
/// trusted to show the right pixels.
class DisplayLayoutMismatch implements Exception {
  const DisplayLayoutMismatch(this.reason);

  final String reason;

  @override
  String toString() => 'DisplayLayoutMismatch: $reason';
}

/// Maps the target display of [placement] into a spanning capture of
/// [imageWidth] x [imageHeight] pixels.
///
/// GNOME sizes the capture as the logical bounding box of all displays times
/// the largest display scale, rounded. Image pixels are therefore logical
/// pixels times one image scale, derived here from the image itself. Edges
/// are rounded rather than sizes, so neighbouring displays tile exactly.
OverlayCrop computeOverlayCrop({
  required DisplayPlacement placement,
  required int imageWidth,
  required int imageHeight,
}) {
  final monitors = placement.monitors;
  if (placement.targetIndex < 0 || placement.targetIndex >= monitors.length) {
    throw const DisplayLayoutMismatch('target display is not in the layout');
  }
  if (monitors.any((m) => m.width <= 0 || m.height <= 0)) {
    throw const DisplayLayoutMismatch('a display has an empty size');
  }
  if (imageWidth <= 0 || imageHeight <= 0) {
    throw const DisplayLayoutMismatch('the capture is empty');
  }
  final left = monitors.map((m) => m.x).reduce(math.min);
  final top = monitors.map((m) => m.y).reduce(math.min);
  final stageWidth = monitors.map((m) => m.right).reduce(math.max) - left;
  final stageHeight = monitors.map((m) => m.bottom).reduce(math.max) - top;

  final scaleX = imageWidth / stageWidth;
  final scaleY = imageHeight / stageHeight;
  // Rounding the capture size may move each axis by up to one pixel.
  if ((imageHeight - stageHeight * scaleX).abs() > 1.5 ||
      (imageWidth - stageWidth * scaleY).abs() > 1.5) {
    throw DisplayLayoutMismatch(
      'capture ${imageWidth}x$imageHeight does not match layout '
      '${stageWidth}x$stageHeight',
    );
  }
  if (scaleX < 0.999) {
    throw const DisplayLayoutMismatch('capture is smaller than the layout');
  }

  final target = monitors[placement.targetIndex];
  int edge(int logical, int origin, double scale, int limit) =>
      ((logical - origin) * scale).round().clamp(0, limit);
  final x0 = edge(target.x, left, scaleX, imageWidth);
  final y0 = edge(target.y, top, scaleY, imageHeight);
  final x1 = edge(target.right, left, scaleX, imageWidth);
  final y1 = edge(target.bottom, top, scaleY, imageHeight);
  final source = PixelRect(x0, y0, x1 - x0, y1 - y0);

  // A display below the capture scale was upsampled; return it to its own
  // pixel density. GDK only reports integer scales, so a fractional display
  // keeps the capture density.
  final imageScale = (scaleX + scaleY) / 2;
  final ownScale = target.scaleFactor.toDouble();
  final downscale = ownScale < imageScale - 0.001;
  return OverlayCrop(
    source: source,
    outputWidth: downscale ? target.width * target.scaleFactor : source.width,
    outputHeight: downscale
        ? target.height * target.scaleFactor
        : source.height,
    imageScale: imageScale,
  );
}
