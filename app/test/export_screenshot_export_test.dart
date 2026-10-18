import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/export/screenshot_export.dart';

void main() {
  test('suggests kiriglyph timestamp names and suffixes collisions', () async {
    final root = Directory.systemTemp.createTempSync('screenshot-export-');
    addTearDown(() => root.deleteSync(recursive: true));
    final controller = ScreenshotExportController(
      clipboard: _Clipboard(),
      codec: _Codec(),
      clock: () => DateTime(2026, 1, 2, 3, 4, 5),
      picturesDirectory: () => root.path,
    );

    await File('${root.path}/kiriglyph-20260102-030405.png').writeAsBytes([1]);
    final outcome = await controller.save(Uint8List.fromList([9]));

    expect(
      suggestedScreenshotPngName(DateTime(2026, 1, 2, 3, 4, 5)),
      'kiriglyph-20260102-030405.png',
    );
    expect(outcome.savedName, 'kiriglyph-20260102-030405-2.png');
    expect(File('${root.path}/${outcome.savedName}').readAsBytesSync(), [9]);
  });
}

class _Clipboard implements ScreenshotClipboardPort {
  @override
  Future<void> copyPng(Uint8List pngBytes) async {}
}

class _Codec implements ScreenshotImageCodec {
  @override
  Future<Uint8List> cropPng(Uint8List encodedPng, ScreenshotCrop crop) async =>
      Uint8List.fromList([crop.left, crop.top, crop.width, crop.height]);
}
