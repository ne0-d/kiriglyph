import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/export/subject_cutout.dart';
import 'package:kiriglyph/export/subject_export.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';

void main() {
  late Directory root;
  late File sourceFile;
  late File maskFile;
  late FakeClipboard clipboard;
  late FakeSavePort savePort;
  late FakeCodec codec;
  late List<String> diagnostics;

  setUp(() {
    root = Directory.systemTemp.createTempSync('subject-export-');
    sourceFile = File('${root.path}/source.png')..writeAsBytesSync([1]);
    maskFile = File('${root.path}/mask.png')..writeAsBytesSync([2]);
    clipboard = FakeClipboard();
    savePort = FakeSavePort();
    codec = FakeCodec();
    diagnostics = [];
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  SubjectExportController controller() => SubjectExportController(
    clipboard: clipboard,
    savePort: savePort,
    codec: codec,
    onDiagnostic: diagnostics.add,
    picturesDirectory: () => '${root.path}/Pictures',
  );

  SubjectExportController controllerAt(DateTime now) => SubjectExportController(
    clipboard: clipboard,
    savePort: savePort,
    codec: codec,
    clock: () => now,
    picturesDirectory: () => '${root.path}/Pictures',
  );

  test('copies an encoded PNG payload and logs only an outcome kind', () async {
    final outcome = await controller().copy(
      sourceImagePath: sourceFile.path,
      mask: _maskResult(maskFile.path),
    );

    expect(outcome.kind, SubjectExportOutcomeKind.copied);
    expect(clipboard.payloads.single, FakeCodec.pngBytes);
    expect(codec.encodedCutout!.width, 2);
    expect(diagnostics, ['subject_export_copied']);
    expect(diagnostics.join(' '), isNot(contains(root.path)));
    expect(
      diagnostics.join(' '),
      isNot(contains(FakeCodec.pngBytes.first.toString())),
    );
  });

  test('reports clipboard failure after successful encoding', () async {
    clipboard.fail = true;

    final outcome = await controller().copy(
      sourceImagePath: sourceFile.path,
      mask: _maskResult(maskFile.path),
    );

    expect(outcome.kind, SubjectExportOutcomeKind.clipboardFailure);
    expect(codec.encodedCutout, isNotNull);
  });

  test('reports encoder failure distinctly from invalid masks', () async {
    codec.failEncode = true;

    final outcome = await controller().copy(
      sourceImagePath: sourceFile.path,
      mask: _maskResult(maskFile.path),
    );

    expect(outcome.kind, SubjectExportOutcomeKind.encoderFailure);
  });

  test('rejects suspect masks and mask/source size mismatches', () async {
    final suspect = await controller().copy(
      sourceImagePath: sourceFile.path,
      mask: _maskResult(
        maskFile.path,
        outcome: SubjectMaskOutcome.suspectFullImage,
      ),
    );
    expect(suspect.kind, SubjectExportOutcomeKind.invalidMask);

    codec.mask = RgbaImageBuffer(
      width: 3,
      height: 2,
      rgba: Uint8List(3 * 2 * 4),
    );
    final mismatch = await controller().copy(
      sourceImagePath: sourceFile.path,
      mask: _maskResult(maskFile.path),
    );
    expect(mismatch.kind, SubjectExportOutcomeKind.invalidMask);
  });

  test(
    'save-as cancellation and overwrite decline do not write files',
    () async {
      savePort.next = const SaveDestination.cancelled();
      final cancelled = await controller().saveAs(
        sourceImagePath: sourceFile.path,
        mask: _maskResult(maskFile.path),
      );
      expect(cancelled.kind, SubjectExportOutcomeKind.cancelled);

      savePort.next = const SaveDestination.overwriteDeclined();
      final declined = await controller().saveAs(
        sourceImagePath: sourceFile.path,
        mask: _maskResult(maskFile.path),
      );
      expect(declined.kind, SubjectExportOutcomeKind.overwriteDeclined);

      expect(
        root.listSync().where(
          (entity) => entity.path.contains('kiriglyph.tmp'),
        ),
        isEmpty,
      );
    },
  );

  test('saves through a temp file and overwrites only after success', () async {
    final outcome = await controller().save(
      sourceImagePath: sourceFile.path,
      mask: _maskResult(maskFile.path),
    );

    expect(outcome.kind, SubjectExportOutcomeKind.saved);
    expect(outcome.savedName, startsWith('kiriglyph-'));
    final destination = File('${root.path}/Pictures/${outcome.savedName}');
    expect(destination.readAsBytesSync(), FakeCodec.pngBytes);
    expect(
      root.listSync().where((entity) => entity.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test(
    'suggests timestamped PNG names from the injected local clock',
    () async {
      final outcome = await controllerAt(DateTime(2026, 1, 2, 3, 4, 5)).save(
        sourceImagePath: sourceFile.path,
        mask: _maskResult(maskFile.path),
      );

      expect(outcome.savedName, 'kiriglyph-20260102-030405.png');
    },
  );

  test('adds numeric suffixes for direct saves that already exist', () async {
    final pictures = Directory('${root.path}/Pictures')..createSync();
    File('${pictures.path}/kiriglyph-20260102-030405.png')
        .writeAsBytesSync([0]);

    final outcome = await controllerAt(
      DateTime(2026, 1, 2, 3, 4, 5),
    ).save(sourceImagePath: sourceFile.path, mask: _maskResult(maskFile.path));

    expect(outcome.savedName, 'kiriglyph-20260102-030405-2.png');
  });

  test('timestamped PNG suggestions differ across seconds', () async {
    expect(
      suggestedSubjectPngName(DateTime(2026, 1, 2, 3, 4, 5)),
      isNot(suggestedSubjectPngName(DateTime(2026, 1, 2, 3, 4, 6))),
    );
  });

  test('unwritable destination removes its temp file', () async {
    final destination = Directory('${root.path}/destination')..createSync();
    savePort.next = SaveDestination.selected(destination.path);

    final outcome = await controller().saveAs(
      sourceImagePath: sourceFile.path,
      mask: _maskResult(maskFile.path),
    );

    expect(outcome.kind, SubjectExportOutcomeKind.unwritableDestination);
    expect(
      root.listSync().where((entity) => entity.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  testWidgets('engine codec PNG decodes back to expected RGBA pixels', (
    tester,
  ) async {
    final decoded = (await tester.runAsync(() async {
      const codec = EngineSubjectImageCodec();
      final png = await codec.encodePng(
        SubjectCutoutImage(
          width: 2,
          height: 1,
          sourceBounds: const SubjectRect(x: 0, y: 0, width: 2, height: 1),
          rgba: Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 0]),
        ),
      );
      return codec.decodeRgba(png);
    }))!;

    expect(decoded.width, 2);
    expect(decoded.height, 1);
    expect(decoded.rgba, [255, 0, 0, 255, 0, 0, 0, 0]);
  });
}

class FakeClipboard implements ClipboardImagePort {
  final payloads = <Uint8List>[];
  bool fail = false;

  @override
  Future<void> copyPng(Uint8List pngBytes) async {
    if (fail) {
      throw StateError('clipboard failed');
    }
    payloads.add(Uint8List.fromList(pngBytes));
  }
}

class FakeSavePort implements SavePngPort {
  SaveDestination next = const SaveDestination.cancelled();
  final suggestedNames = <String>[];

  @override
  Future<SaveDestination> chooseDestination(String suggestedName) async {
    suggestedNames.add(suggestedName);
    return next;
  }
}

class FakeCodec implements SubjectImageCodec {
  static final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);

  RgbaImageBuffer source = RgbaImageBuffer(
    width: 2,
    height: 2,
    rgba: Uint8List.fromList([
      10,
      20,
      30,
      255,
      40,
      50,
      60,
      255,
      70,
      80,
      90,
      255,
      100,
      110,
      120,
      255,
    ]),
  );
  RgbaImageBuffer mask = RgbaImageBuffer(
    width: 2,
    height: 2,
    rgba: Uint8List.fromList([
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      0,
      0,
      0,
      255,
      0,
      0,
      0,
      255,
    ]),
  );
  SubjectCutoutImage? encodedCutout;
  bool failEncode = false;

  @override
  Future<RgbaImageBuffer> decodeRgba(Uint8List encoded) async =>
      encoded.single == 1 ? source : mask;

  @override
  Future<Uint8List> encodePng(SubjectCutoutImage image) async {
    if (failEncode) {
      throw StateError('encode failed');
    }
    encodedCutout = image;
    return pngBytes;
  }
}

SubjectMaskResult _maskResult(
  String path, {
  SubjectMaskOutcome outcome = SubjectMaskOutcome.ok,
}) {
  const bounds = SubjectRect(x: 0, y: 0, width: 2, height: 1);
  return SubjectMaskResult(
    imageWidth: 2,
    imageHeight: 2,
    mask: SubjectMaskReference(path: path, byteLength: 1, sha256: '0'),
    bounds: bounds,
    stats: SubjectMaskStats(
      outcome: outcome,
      areaFraction: 0.5,
      bounds: bounds,
      touchesEdge: const SubjectEdgeTouches(
        left: true,
        top: true,
        right: true,
        bottom: false,
      ),
      components: const SubjectComponentStats(count: 1, largestBounds: bounds),
    ),
    timings: const SubjectSegmentationTimings(promptMs: 1),
  );
}
