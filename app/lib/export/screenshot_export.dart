import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:kiriglyph/export/subject_export.dart';

typedef ScreenshotExportClock = DateTime Function();

enum ScreenshotExportOutcomeKind {
  copied,
  saved,
  clipboardFailure,
  encoderFailure,
  unwritableDestination,
}

class ScreenshotExportOutcome {
  const ScreenshotExportOutcome(this.kind, {this.savedName});

  final ScreenshotExportOutcomeKind kind;
  final String? savedName;
}

class ScreenshotCrop {
  const ScreenshotCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

abstract interface class ScreenshotClipboardPort {
  Future<void> copyPng(Uint8List pngBytes);
}

abstract interface class ScreenshotImageCodec {
  Future<Uint8List> cropPng(Uint8List encodedPng, ScreenshotCrop crop);
}

class PlatformScreenshotClipboardPort implements ScreenshotClipboardPort {
  PlatformScreenshotClipboardPort({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kiriglyph/app');

  final MethodChannel _channel;

  @override
  Future<void> copyPng(Uint8List pngBytes) =>
      _channel.invokeMethod<void>('copyImage', pngBytes);
}

class EngineScreenshotImageCodec implements ScreenshotImageCodec {
  const EngineScreenshotImageCodec();

  @override
  Future<Uint8List> cropPng(Uint8List encodedPng, ScreenshotCrop crop) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encodedPng);
    final ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } finally {
      buffer.dispose();
    }
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          final destination = ui.Rect.fromLTWH(
            0,
            0,
            crop.width.toDouble(),
            crop.height.toDouble(),
          );
          canvas.drawImageRect(
            image,
            ui.Rect.fromLTWH(
              crop.left.toDouble(),
              crop.top.toDouble(),
              crop.width.toDouble(),
              crop.height.toDouble(),
            ),
            destination,
            ui.Paint(),
          );
          final picture = recorder.endRecording();
          final cropped = await picture.toImage(crop.width, crop.height);
          try {
            final bytes = await cropped.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes == null) {
              throw StateError('PNG encoder returned no data');
            }
            return Uint8List.fromList(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            cropped.dispose();
            picture.dispose();
          }
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  }
}

class ScreenshotExportController {
  const ScreenshotExportController({
    required this.clipboard,
    required this.codec,
    this.clock = DateTime.now,
    this.picturesDirectory,
  });

  final ScreenshotClipboardPort clipboard;
  final ScreenshotImageCodec codec;
  final ScreenshotExportClock clock;
  final String Function()? picturesDirectory;

  Future<ScreenshotExportOutcome> copy(Uint8List pngBytes) async {
    try {
      await clipboard.copyPng(pngBytes);
      return const ScreenshotExportOutcome(ScreenshotExportOutcomeKind.copied);
    } catch (_) {
      return const ScreenshotExportOutcome(
        ScreenshotExportOutcomeKind.clipboardFailure,
      );
    }
  }

  Future<ScreenshotExportOutcome> copyCrop({
    required Uint8List encodedPng,
    required ScreenshotCrop crop,
  }) async {
    try {
      return await copy(await codec.cropPng(encodedPng, crop));
    } catch (_) {
      return const ScreenshotExportOutcome(
        ScreenshotExportOutcomeKind.encoderFailure,
      );
    }
  }

  Future<ScreenshotExportOutcome> save(Uint8List pngBytes) async {
    final directory = Directory(
      (picturesDirectory ?? defaultPicturesDirectory)(),
    );
    try {
      await directory.create(recursive: true);
      final destination = await _uniqueDestination(
        directory,
        suggestedScreenshotPngName(clock()),
      );
      await _writeAtomically(destination.path, pngBytes);
      return ScreenshotExportOutcome(
        ScreenshotExportOutcomeKind.saved,
        savedName: destination.uri.pathSegments.last,
      );
    } catch (_) {
      return const ScreenshotExportOutcome(
        ScreenshotExportOutcomeKind.unwritableDestination,
      );
    }
  }

  Future<ScreenshotExportOutcome> saveCrop({
    required Uint8List encodedPng,
    required ScreenshotCrop crop,
  }) async {
    try {
      return await save(await codec.cropPng(encodedPng, crop));
    } catch (_) {
      return const ScreenshotExportOutcome(
        ScreenshotExportOutcomeKind.encoderFailure,
      );
    }
  }

  Future<File> _uniqueDestination(Directory directory, String name) async {
    final dot = name.toLowerCase().endsWith('.png')
        ? name.length - '.png'.length
        : name.length;
    final base = name.substring(0, dot);
    final ext = dot == name.length ? '.png' : name.substring(dot);
    for (var attempt = 1; attempt < 1000; attempt++) {
      final suffix = attempt == 1 ? '' : '-$attempt';
      final candidate = File('${directory.path}/$base$suffix$ext');
      if (!await candidate.exists()) {
        return candidate;
      }
    }
    throw const FileSystemException('could not choose unique PNG name');
  }

  Future<void> _writeAtomically(String destination, Uint8List png) async {
    final target = File(destination);
    File? temp;
    for (var attempt = 0; attempt < 100; attempt++) {
      final suffix = attempt == 0 ? '' : '-$attempt';
      final candidate = File(
        '${target.parent.path}/.${target.uri.pathSegments.last}.kiriglyph$suffix.tmp',
      );
      try {
        temp = await candidate.create(exclusive: true);
        break;
      } on FileSystemException {
        continue;
      }
    }
    if (temp == null) {
      throw const FileSystemException('could not create temporary file');
    }
    try {
      await temp.writeAsBytes(png, flush: true);
      await temp.rename(target.path);
    } catch (_) {
      try {
        if (await temp.exists()) {
          await temp.delete();
        }
      } on FileSystemException {
        // Best effort cleanup.
      }
      rethrow;
    }
  }
}

String suggestedScreenshotPngName(DateTime localTime) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${localTime.year.toString().padLeft(4, '0')}'
      '${two(localTime.month)}'
      '${two(localTime.day)}';
  final time =
      '${two(localTime.hour)}${two(localTime.minute)}${two(localTime.second)}';
  return 'kiriglyph-$date-$time.png';
}
