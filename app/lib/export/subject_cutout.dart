import 'dart:collection';
import 'dart:typed_data';

import 'package:kiriglyph/segmentation/subject_segmenter.dart';

enum SubjectCutoutFailureKind { invalidMask, sizeMismatch, emptyMask }

class SubjectCutoutException implements Exception {
  const SubjectCutoutException({required this.kind, required this.message});

  final SubjectCutoutFailureKind kind;
  final String message;

  @override
  String toString() => 'SubjectCutoutException(${kind.name}): $message';
}

class RgbaImageBuffer {
  const RgbaImageBuffer({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  void validate(String label) {
    if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
      throw SubjectCutoutException(
        kind: SubjectCutoutFailureKind.sizeMismatch,
        message: '$label dimensions do not match its RGBA buffer',
      );
    }
  }
}

class SubjectCutoutImage {
  const SubjectCutoutImage({
    required this.width,
    required this.height,
    required this.rgba,
    required this.sourceBounds,
  });

  final int width;
  final int height;
  final Uint8List rgba;
  final SubjectRect sourceBounds;
}

/// Applies the validated segmentation mask to the source crop.
///
/// The output never grows the mask: only fully opaque mask pixels retain alpha.
/// Any partially-transparent fringe is made transparent, then its RGB is filled
/// from the nearest fully-opaque interior pixel so PNG consumers that blend
/// against alpha at edges do not reveal background-coloured halos.
class SubjectCutoutComposer {
  const SubjectCutoutComposer({this.padding = 0});

  final int padding;

  SubjectCutoutImage compose({
    required RgbaImageBuffer source,
    required RgbaImageBuffer mask,
    required SubjectMaskResult result,
  }) {
    source.validate('source');
    mask.validate('mask');
    if (source.width != mask.width || source.height != mask.height) {
      throw const SubjectCutoutException(
        kind: SubjectCutoutFailureKind.sizeMismatch,
        message: 'source and mask dimensions differ',
      );
    }
    if (result.stats.outcome != SubjectMaskOutcome.ok) {
      throw const SubjectCutoutException(
        kind: SubjectCutoutFailureKind.invalidMask,
        message: 'subject mask is not exportable',
      );
    }
    final bounds = result.stats.bounds ?? result.bounds;
    if (bounds == null) {
      throw const SubjectCutoutException(
        kind: SubjectCutoutFailureKind.emptyMask,
        message: 'subject mask has no bounds',
      );
    }
    final crop = _padded(bounds, source.width, source.height);
    final count = crop.width * crop.height;
    final opaqueSeed = Uint8List(count);
    final nearestRed = Uint8List(count);
    final nearestGreen = Uint8List(count);
    final nearestBlue = Uint8List(count);
    final queue = Queue<int>();

    for (var y = 0; y < crop.height; y++) {
      for (var x = 0; x < crop.width; x++) {
        final sourceIndex = _offset(source.width, crop.x + x, crop.y + y);
        final local = y * crop.width + x;
        if (subjectMaskCoverage(mask.rgba, sourceIndex) == 255) {
          opaqueSeed[local] = 1;
          nearestRed[local] = source.rgba[sourceIndex];
          nearestGreen[local] = source.rgba[sourceIndex + 1];
          nearestBlue[local] = source.rgba[sourceIndex + 2];
          queue.add(local);
        }
      }
    }
    if (queue.isEmpty) {
      throw const SubjectCutoutException(
        kind: SubjectCutoutFailureKind.emptyMask,
        message: 'subject mask has no opaque pixels',
      );
    }
    _spreadInteriorColors(
      queue,
      opaqueSeed,
      nearestRed,
      nearestGreen,
      nearestBlue,
      crop.width,
      crop.height,
    );

    final out = Uint8List(count * 4);
    for (var y = 0; y < crop.height; y++) {
      for (var x = 0; x < crop.width; x++) {
        final sourceIndex = _offset(source.width, crop.x + x, crop.y + y);
        final local = y * crop.width + x;
        final outIndex = local * 4;
        final visible = subjectMaskCoverage(mask.rgba, sourceIndex) == 255;
        if (visible) {
          out[outIndex] = source.rgba[sourceIndex];
          out[outIndex + 1] = source.rgba[sourceIndex + 1];
          out[outIndex + 2] = source.rgba[sourceIndex + 2];
          out[outIndex + 3] = 255;
        } else {
          out[outIndex] = nearestRed[local];
          out[outIndex + 1] = nearestGreen[local];
          out[outIndex + 2] = nearestBlue[local];
          out[outIndex + 3] = 0;
        }
      }
    }

    return SubjectCutoutImage(
      width: crop.width,
      height: crop.height,
      rgba: out,
      sourceBounds: crop,
    );
  }

  SubjectRect _padded(SubjectRect bounds, int width, int height) {
    final safePadding = padding < 0 ? 0 : padding;
    final left = (bounds.x - safePadding).clamp(0, width);
    final top = (bounds.y - safePadding).clamp(0, height);
    final right = (bounds.x + bounds.width + safePadding).clamp(0, width);
    final bottom = (bounds.y + bounds.height + safePadding).clamp(0, height);
    if (right <= left || bottom <= top) {
      throw const SubjectCutoutException(
        kind: SubjectCutoutFailureKind.emptyMask,
        message: 'subject mask bounds are empty',
      );
    }
    return SubjectRect(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }
}

int _offset(int width, int x, int y) => (y * width + x) * 4;

int subjectMaskCoverage(Uint8List rgba, int index) {
  final alpha = rgba[index + 3];
  if (alpha != 255) {
    return alpha;
  }
  final red = rgba[index];
  final green = rgba[index + 1];
  final blue = rgba[index + 2];
  if (red == green && green == blue) {
    return red;
  }
  return alpha;
}

void _spreadInteriorColors(
  Queue<int> queue,
  Uint8List seen,
  Uint8List red,
  Uint8List green,
  Uint8List blue,
  int width,
  int height,
) {
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    final x = current % width;
    final y = current ~/ width;
    void visit(int nx, int ny) {
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
        return;
      }
      final next = ny * width + nx;
      if (seen[next] != 0) {
        return;
      }
      seen[next] = 1;
      red[next] = red[current];
      green[next] = green[current];
      blue[next] = blue[current];
      queue.add(next);
    }

    visit(x + 1, y);
    visit(x - 1, y);
    visit(x, y + 1);
    visit(x, y - 1);
  }
}
