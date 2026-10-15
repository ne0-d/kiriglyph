import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:kiriglyph/diagnostics/timing_log.dart';
import 'package:kiriglyph/export/subject_cutout.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';

typedef SubjectExportClock = DateTime Function();

enum SubjectExportOutcomeKind {
  copied,
  saved,
  cancelled,
  overwriteDeclined,
  clipboardFailure,
  encoderFailure,
  invalidMask,
  unwritableDestination,
}

class SubjectExportOutcome {
  const SubjectExportOutcome(this.kind, {this.savedName});

  final SubjectExportOutcomeKind kind;
  final String? savedName;

  bool get succeeded =>
      kind == SubjectExportOutcomeKind.copied ||
      kind == SubjectExportOutcomeKind.saved;
}

class SaveDestination {
  const SaveDestination._(this.kind, this.path);

  const SaveDestination.selected(String path)
    : this._(SaveDestinationKind.selected, path);
  const SaveDestination.cancelled()
    : this._(SaveDestinationKind.cancelled, null);
  const SaveDestination.overwriteDeclined()
    : this._(SaveDestinationKind.overwriteDeclined, null);

  final SaveDestinationKind kind;
  final String? path;
}

enum SaveDestinationKind { selected, cancelled, overwriteDeclined }

abstract interface class ClipboardImagePort {
  Future<void> copyPng(Uint8List pngBytes);
}

abstract interface class SavePngPort {
  Future<SaveDestination> chooseDestination(String suggestedName);
}

abstract interface class SubjectImageCodec {
  Future<RgbaImageBuffer> decodeRgba(Uint8List encoded);

  Future<Uint8List> encodePng(SubjectCutoutImage image);
}

class PlatformClipboardImagePort implements ClipboardImagePort {
  PlatformClipboardImagePort({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kiriglyph/app');

  final MethodChannel _channel;

  @override
  Future<void> copyPng(Uint8List pngBytes) =>
      _channel.invokeMethod<void>('copyImage', pngBytes);
}

class PlatformSavePngPort implements SavePngPort {
  PlatformSavePngPort({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kiriglyph/app');

  final MethodChannel _channel;

  @override
  Future<SaveDestination> chooseDestination(String suggestedName) async {
    final path = await _channel.invokeMethod<String>('chooseSavePng', {
      'suggestedName': suggestedName,
    });
    if (path == null || path.isEmpty) {
      return const SaveDestination.cancelled();
    }
    return SaveDestination.selected(path);
  }
}

class EngineSubjectImageCodec implements SubjectImageCodec {
  const EngineSubjectImageCodec();

  @override
  Future<RgbaImageBuffer> decodeRgba(Uint8List encoded) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
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
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (data == null) {
            throw StateError('image could not be decoded');
          }
          return RgbaImageBuffer(
            width: image.width,
            height: image.height,
            rgba: Uint8List.fromList(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ),
          );
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

  @override
  Future<Uint8List> encodePng(SubjectCutoutImage image) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      image.rgba,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final uiImage = await completer.future;
    try {
      final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG encoder returned no data');
      }
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      uiImage.dispose();
    }
  }
}

class SubjectExportController {
  const SubjectExportController({
    required this.clipboard,
    required this.savePort,
    required this.codec,
    this.composer = const SubjectCutoutComposer(),
    this.onDiagnostic,
    this.onTimingPhase,
    this.clock = DateTime.now,
    this.picturesDirectory,
  });

  final ClipboardImagePort clipboard;
  final SavePngPort savePort;
  final SubjectImageCodec codec;
  final SubjectCutoutComposer composer;
  final void Function(String message)? onDiagnostic;
  final void Function(TimingPhase phase)? onTimingPhase;
  final SubjectExportClock clock;
  final String Function()? picturesDirectory;

  Future<SubjectExportOutcome> copy({
    required String sourceImagePath,
    required SubjectMaskResult mask,
  }) async {
    final built = await _buildPng(sourceImagePath: sourceImagePath, mask: mask);
    if (!built.ok) {
      return _outcome(built.failure!);
    }
    try {
      await clipboard.copyPng(built.png!);
      onTimingPhase?.call(TimingPhase.clipboard);
      return _outcome(SubjectExportOutcomeKind.copied);
    } catch (_) {
      return _outcome(SubjectExportOutcomeKind.clipboardFailure);
    }
  }

  Future<SubjectExportOutcome> save({
    required String sourceImagePath,
    required SubjectMaskResult mask,
    String? suggestedName,
  }) async {
    final built = await _buildPng(sourceImagePath: sourceImagePath, mask: mask);
    if (!built.ok) {
      return _outcome(built.failure!);
    }
    final directory = Directory(
      (picturesDirectory ?? defaultPicturesDirectory)(),
    );
    try {
      await directory.create(recursive: true);
      final destination = await _uniqueDestination(
        directory,
        suggestedName ?? suggestedSubjectPngName(clock()),
      );
      await _writeAtomically(destination.path, built.png!);
      return _outcome(
        SubjectExportOutcomeKind.saved,
        savedName: destination.uri.pathSegments.last,
      );
    } catch (_) {
      return _saveAsBuilt(built, suggestedName: suggestedName);
    }
  }

  Future<SubjectExportOutcome> saveAs({
    required String sourceImagePath,
    required SubjectMaskResult mask,
    String? suggestedName,
  }) async {
    final built = await _buildPng(sourceImagePath: sourceImagePath, mask: mask);
    if (!built.ok) {
      return _outcome(built.failure!);
    }
    return _saveAsBuilt(built, suggestedName: suggestedName);
  }

  Future<SubjectExportOutcome> _saveAsBuilt(
    _BuildPngResult built, {
    String? suggestedName,
  }) async {
    final destination = await savePort.chooseDestination(
      suggestedName ?? suggestedSubjectPngName(clock()),
    );
    switch (destination.kind) {
      case SaveDestinationKind.cancelled:
        return _outcome(SubjectExportOutcomeKind.cancelled);
      case SaveDestinationKind.overwriteDeclined:
        return _outcome(SubjectExportOutcomeKind.overwriteDeclined);
      case SaveDestinationKind.selected:
        final path = destination.path;
        if (path == null || path.isEmpty) {
          return _outcome(SubjectExportOutcomeKind.cancelled);
        }
        try {
          await _writeAtomically(path, built.png!);
          return _outcome(
            SubjectExportOutcomeKind.saved,
            savedName: File(path).uri.pathSegments.last,
          );
        } catch (_) {
          return _outcome(SubjectExportOutcomeKind.unwritableDestination);
        }
    }
  }

  Future<_BuildPngResult> _buildPng({
    required String sourceImagePath,
    required SubjectMaskResult mask,
  }) async {
    if (mask.stats.outcome != SubjectMaskOutcome.ok) {
      return const _BuildPngResult.failure(
        SubjectExportOutcomeKind.invalidMask,
      );
    }
    final Uint8List sourceBytes;
    final Uint8List maskBytes;
    try {
      sourceBytes = await File(sourceImagePath).readAsBytes();
    } catch (_) {
      return const _BuildPngResult.failure(
        SubjectExportOutcomeKind.encoderFailure,
      );
    }
    try {
      maskBytes = await File(mask.mask.path).readAsBytes();
    } catch (_) {
      return const _BuildPngResult.failure(
        SubjectExportOutcomeKind.invalidMask,
      );
    }
    final RgbaImageBuffer source;
    final RgbaImageBuffer alpha;
    try {
      source = await codec.decodeRgba(sourceBytes);
    } catch (_) {
      return const _BuildPngResult.failure(
        SubjectExportOutcomeKind.encoderFailure,
      );
    }
    try {
      alpha = await codec.decodeRgba(maskBytes);
    } catch (_) {
      return const _BuildPngResult.failure(
        SubjectExportOutcomeKind.invalidMask,
      );
    }
    final SubjectCutoutImage cutout;
    try {
      cutout = composer.compose(source: source, mask: alpha, result: mask);
    } on SubjectCutoutException {
      return const _BuildPngResult.failure(
        SubjectExportOutcomeKind.invalidMask,
      );
    }
    try {
      final png = await codec.encodePng(cutout);
      onTimingPhase?.call(TimingPhase.pngEncode);
      return _BuildPngResult.ok(png);
    } catch (_) {
      return const _BuildPngResult.failure(
        SubjectExportOutcomeKind.encoderFailure,
      );
    }
  }

  Future<void> _writeAtomically(String destination, Uint8List png) async {
    final target = File(destination);
    final directory = target.parent;
    final base = target.uri.pathSegments.isEmpty
        ? 'kiriglyph-subject.png'
        : target.uri.pathSegments.last;
    File? temp;
    for (var attempt = 0; attempt < 100; attempt++) {
      final suffix = attempt == 0 ? '' : '-$attempt';
      final candidate = File('${directory.path}/.$base.kiriglyph$suffix.tmp');
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
        // Best-effort cleanup of a temp export file.
      }
      rethrow;
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

  SubjectExportOutcome _outcome(
    SubjectExportOutcomeKind kind, {
    String? savedName,
  }) {
    onDiagnostic?.call('subject_export_${kind.name}');
    return SubjectExportOutcome(kind, savedName: savedName);
  }
}

String defaultPicturesDirectory() {
  final env = Platform.environment;
  final home = env['HOME'];
  final xdg = env['XDG_PICTURES_DIR'];
  if (xdg != null && xdg.isNotEmpty) {
    return xdg;
  }
  if (home != null && home.isNotEmpty) {
    return '$home/Pictures';
  }
  return Directory.current.path;
}

String suggestedSubjectPngName(DateTime localTime) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${localTime.year.toString().padLeft(4, '0')}'
      '${two(localTime.month)}'
      '${two(localTime.day)}';
  final time =
      '${two(localTime.hour)}${two(localTime.minute)}${two(localTime.second)}';
  return 'kiriglyph-$date-$time.png';
}

class _BuildPngResult {
  const _BuildPngResult.ok(this.png) : failure = null;

  const _BuildPngResult.failure(this.failure) : png = null;

  final Uint8List? png;
  final SubjectExportOutcomeKind? failure;

  bool get ok => png != null;
}
