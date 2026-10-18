import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/protocol/protocol_error.dart';
import 'package:kiriglyph/protocol/worker_protocol.dart';
import 'package:kiriglyph/segmentation/process_subject_segmenter.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/worker/process_ocr_worker.dart';

import 'support/golden_replies.dart';

/// Replies with one checked-in golden line, swapping in the request id.
const _goldenResponder = r'''
import json
import sys
from pathlib import Path

line = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
old_id = json.loads(line)["id"]
for raw in sys.stdin.buffer:
    request = json.loads(raw)
    if request.get("method") == "close":
        closed = {
            "version": 1,
            "id": request["id"],
            "ok": True,
            "result": {"closed": True},
        }
        sys.stdout.write(json.dumps(closed, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        break
    updated = line.replace(
        '"id":"' + old_id + '"',
        '"id":"' + request["id"] + '"',
        1,
    )
    sys.stdout.write(updated + "\n")
    sys.stdout.flush()
''';

void main() {
  test('every checked-in golden has a parser case', () {
    expect(goldenNdjsonNames(), [
      'decode-codes-empty.ndjson',
      'decode-codes-ok.ndjson',
      'recognize-image-unreadable.ndjson',
      'recognize-no-text.ndjson',
      'recognize-ocr-failed.ndjson',
      'recognize-ok.ndjson',
      'segmentation-embed-ok.ndjson',
      'segmentation-model-missing.ndjson',
      'segmentation-prompt-ok.ndjson',
    ]);
  });

  test('recognize ok decodes regions from the golden reply', () {
    final line = loadGoldenReply('recognize-ok.ndjson');
    final envelope = jsonDecode(line) as Map;
    final parsed = parseResponseLine(
      line,
      expectedId: envelope['id'] as String,
    );
    final result = parsed.result;

    expect(parsed.error, isNull);
    expect(result, isNotNull);
    expect(result!.regions, isNotEmpty);
    expect(result.fullText, envelope['result']['full_text']);
    expect(result.imageWidth, envelope['result']['image']['width']);
    expect(result.imageHeight, envelope['result']['image']['height']);
    expect(result.timingsMs.total, envelope['result']['timings_ms']['total']);

    final region = result.regions.single;
    final regionJson = (envelope['result']['regions'] as List).single as Map;
    expect(region.text, regionJson['text']);
    expect(region.level, TextRegionLevel.line);
    expect(region.ranges, hasLength((regionJson['ranges'] as List).length));
    expect(
      region.ranges.first.geometryKind,
      CharacterGeometryKind.derivedCtcPolygon,
    );
    expect(region.ranges.map((range) => range.text).join(), region.text);
  });

  test('no_text surfaces as WorkerError and not an empty result', () {
    final line = loadGoldenReply('recognize-no-text.ndjson');
    final envelope = jsonDecode(line) as Map;
    final parsed = parseResponseLine(
      line,
      expectedId: envelope['id'] as String,
    );

    expect(parsed.result, isNull);
    expect(parsed.error, isA<WorkerError>());
    expect(parsed.error!.code, 'no_text');
    expect(parsed.error!.message, envelope['error']['message']);
  });

  test('image_unreadable and ocr_failed decode as WorkerError', () {
    for (final name in [
      'recognize-image-unreadable.ndjson',
      'recognize-ocr-failed.ndjson',
    ]) {
      final line = loadGoldenReply(name);
      final envelope = jsonDecode(line) as Map;
      final parsed = parseResponseLine(
        line,
        expectedId: envelope['id'] as String,
      );

      expect(parsed.result, isNull, reason: name);
      expect(parsed.error, isA<WorkerError>(), reason: name);
      expect(parsed.error!.code, envelope['error']['code'], reason: name);
      expect(parsed.error!.message, envelope['error']['message'], reason: name);
    }
  });

  test('decode_codes ok and empty decode as code lists', () {
    final found = loadGoldenReply('decode-codes-ok.ndjson');
    final foundEnvelope = jsonDecode(found) as Map;
    final codes = parseDecodeCodesResponseLine(
      found,
      expectedId: foundEnvelope['id'] as String,
    );
    final expected = (foundEnvelope['result']['codes'] as List).single as Map;

    expect(codes, hasLength(1));
    expect(codes.single.format, expected['format']);
    expect(codes.single.text, expected['text']);

    final empty = loadGoldenReply('decode-codes-empty.ndjson');
    final emptyEnvelope = jsonDecode(empty) as Map;
    expect(
      parseDecodeCodesResponseLine(
        empty,
        expectedId: emptyEnvelope['id'] as String,
      ),
      isEmpty,
    );
  });

  test('embed ok decodes through the segmentation parser', () async {
    final line = loadGoldenReply('segmentation-embed-ok.ndjson');
    final envelope = jsonDecode(line) as Map;
    final segmenter = _segmenter(line);
    addTearDown(segmenter.close);

    final embedding = await segmenter.embed('/tmp/golden.png');
    final image = envelope['result']['image'] as Map;
    final timings = envelope['result']['timings_ms'] as Map;

    expect(embedding.handle, envelope['result']['handle']);
    expect(embedding.imageWidth, image['width']);
    expect(embedding.imageHeight, image['height']);
    expect(embedding.timings.loadMs, (timings['load_ms'] as num).toDouble());
    expect(embedding.timings.embedMs, (timings['embed_ms'] as num).toDouble());
  });

  test('prompt ok decodes through the segmentation parser', () async {
    final line = loadGoldenReply('segmentation-prompt-ok.ndjson');
    final envelope = jsonDecode(line) as Map;
    final mask = envelope['result']['mask'] as Map;
    expect(mask['path'], 'contracts/v1/golden/masks/prompt-ok.png');

    // The parser checks the mask file, and close() deletes that path.
    // Serve a copy so the checked-in fixture stays in place.
    final directory = await Directory.systemTemp.createTemp(
      'kiriglyph-golden-mask-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final copy = File('${directory.path}/prompt-ok.png');
    await copy.writeAsBytes(
      await File('${repoRoot().path}/${mask['path']}').readAsBytes(),
    );
    final served = line.replaceFirst(
      '"path":"${mask['path']}"',
      '"path":"${copy.path}"',
    );

    final segmenter = _segmenter(served);
    addTearDown(segmenter.close);
    final result = await segmenter.prompt(
      SubjectEmbedding(
        handle: 'embed-1',
        imageWidth: 8,
        imageHeight: 6,
        timings: const SubjectSegmentationTimings(loadMs: 1, embedMs: 2),
      ),
      const SubjectPrompt(points: [SubjectPoint(4, 3)]),
    );
    final image = envelope['result']['image'] as Map;
    final stats = envelope['result']['mask_stats'] as Map;

    expect(result.imageWidth, image['width']);
    expect(result.imageHeight, image['height']);
    expect(result.mask.path, copy.path);
    expect(result.mask.byteLength, mask['byte_length']);
    expect(result.mask.sha256, mask['sha256']);
    expect(result.stats.outcome, SubjectMaskOutcome.ok);
    expect(
      result.stats.areaFraction,
      (stats['area_fraction'] as num).toDouble(),
    );
    expect(result.stats.components.count, stats['components']['count']);
    expect(
      result.confidence,
      (envelope['result']['confidence'] as num).toDouble(),
    );
    expect(result.stabilityScore, isNull);
    expect(
      result.timings.promptMs,
      (envelope['result']['timings_ms']['prompt_ms'] as num).toDouble(),
    );
  });

  test('segmentation model_missing decodes as a typed error', () async {
    final line = loadGoldenReply('segmentation-model-missing.ndjson');
    final envelope = jsonDecode(line) as Map;
    final segmenter = _segmenter(line);
    addTearDown(segmenter.close);

    await expectLater(
      segmenter.embed('/tmp/golden.png'),
      throwsA(
        isA<SubjectSegmentationException>()
            .having(
              (error) => error.kind,
              'kind',
              SubjectFailureKind.modelMissing,
            )
            .having(
              (error) => error.message,
              'message',
              envelope['error']['message'],
            )
            .having(
              (error) => error.command,
              'command',
              envelope['error']['details']['command'],
            ),
      ),
    );
  });
}

ProcessSubjectSegmenter _segmenter(String goldenLine) {
  final file = File(
    '${Directory.systemTemp.path}/kiriglyph-golden-reply.ndjson',
  )..writeAsStringSync('$goldenLine\n');
  addTearDown(file.delete);
  return ProcessSubjectSegmenter(
    WorkerLaunchConfig(
      executable: 'python3',
      arguments: ['-u', '-c', _goldenResponder, file.path],
      environment: Platform.environment,
    ),
  );
}
