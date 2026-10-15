import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/segmentation/process_subject_segmenter.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/worker/process_ocr_worker.dart';

const _reverseWorker = r'''
import json
import sys

requests = [json.loads(sys.stdin.buffer.readline()), json.loads(sys.stdin.buffer.readline())]
for request in reversed(requests):
    response = {
        "version": 1,
        "id": request["id"],
        "ok": True,
        "result": {
            "handle": request["params"]["image_path"],
            "image": {"width": 8, "height": 6},
            "timings_ms": {"load_ms": 1, "embed_ms": 2},
        },
    }
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
''';

const _promptWorker = r'''
import json
import os
import sys

mask_path = sys.argv[1]
with open(mask_path, "wb") as handle:
    handle.write(b"mask")
os.chmod(mask_path, 0o600)

for line in sys.stdin.buffer:
    request = json.loads(line)
    if request["method"] == "close":
        sys.stdout.write(json.dumps({"version": 1, "id": request["id"], "ok": True, "result": {"closed": True}}) + "\n")
        sys.stdout.flush()
        break
    if request["method"] == "embed":
        result = {
            "handle": "handle-1",
            "image": {"width": 8, "height": 6},
            "timings_ms": {"load_ms": 1, "embed_ms": 2},
        }
    else:
        result = {
            "image": {"width": 8, "height": 6},
            "mask": {"encoding": "alpha_png_file", "path": mask_path, "byte_length": 4, "sha256": "0" * 64},
            "bounds": {"x": 1, "y": 1, "width": 4, "height": 3},
            "mask_stats": {
                "outcome": "ok",
                "area_fraction": 0.25,
                "bounds": {"x": 1, "y": 1, "width": 4, "height": 3},
                "touches_edge": {"left": False, "top": False, "right": False, "bottom": False, "any": False},
                "components": {"count": 1, "largest_bounds": {"x": 1, "y": 1, "width": 4, "height": 3}},
                "multiple_components": False,
            },
            "confidence": 0.7,
            "stability_score": None,
            "timings_ms": {"prompt_ms": 3},
        }
    sys.stdout.write(json.dumps({"version": 1, "id": request["id"], "ok": True, "result": result}) + "\n")
    sys.stdout.flush()
''';

const _malformedWorker = r'''
import sys
sys.stdin.buffer.readline()
sys.stdout.write("{not json\n")
sys.stdout.flush()
''';

const _blockedWorker = r'''
import time
import sys
for _ in sys.stdin.buffer:
    time.sleep(10)
''';

const _exitingWorker = r'''
import sys
sys.stdin.buffer.readline()
sys.exit(7)
''';

const _modelMissingWorker = r'''
import json
import sys
request = json.loads(sys.stdin.buffer.readline())
response = {
    "version": 1,
    "id": request["id"],
    "ok": False,
    "error": {
        "code": "model_missing",
        "message": "EfficientSAM-Ti model files are not installed",
        "details": {"command": "kiriglyph-fetch-models"},
    },
}
sys.stdout.write(json.dumps(response) + "\n")
sys.stdout.flush()
''';

const _pidWorker = r'''
import os
import signal
import sys
import time

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write(str(os.getpid()))
signal.signal(signal.SIGTERM, lambda *_: None)
for _ in sys.stdin.buffer:
    time.sleep(10)
''';

void main() {
  test('correlates out-of-order embed responses by ID', () async {
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _reverseWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(segmenter.close);

    final results = await Future.wait([
      segmenter.embed('/tmp/first.png'),
      segmenter.embed('/tmp/second.png'),
    ]).timeout(const Duration(seconds: 2));

    expect(results[0].handle, '/tmp/first.png');
    expect(results[1].handle, '/tmp/second.png');
  });

  test('parses prompt results and deletes mask files on close', () async {
    final directory = await Directory.systemTemp.createTemp('kiriglyph-mask-');
    addTearDown(() => directory.delete(recursive: true));
    final mask = File('${directory.path}/mask.png');
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: ['-u', '-c', _promptWorker, mask.path],
        environment: Platform.environment,
      ),
    );

    final embedding = await segmenter.embed('/tmp/image.png');
    final result = await segmenter.prompt(
      embedding,
      const SubjectPrompt(points: [SubjectPoint(4, 3)]),
    );

    expect(result.stats.outcome, SubjectMaskOutcome.ok);
    expect(result.stats.components.count, 1);
    expect(mask.existsSync(), isTrue);

    await segmenter.close();

    expect(mask.existsSync(), isFalse);
  });

  test('reports malformed worker stdout as typed failure', () async {
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _malformedWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(segmenter.close);

    await expectLater(
      segmenter.embed('/tmp/malformed.png'),
      throwsA(
        isA<SubjectSegmentationException>().having(
          (error) => error.kind,
          'kind',
          SubjectFailureKind.malformedOutput,
        ),
      ),
    );
  });

  test('times out an unresponsive segmentation request', () async {
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _blockedWorker],
        environment: Platform.environment,
      ),
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(segmenter.close);

    await expectLater(
      segmenter.embed('/tmp/blocked.png'),
      throwsA(
        isA<SubjectSegmentationException>().having(
          (error) => error.kind,
          'kind',
          SubjectFailureKind.timeout,
        ),
      ),
    );
  });

  test('reports process death as typed failure', () async {
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _exitingWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(segmenter.close);

    await expectLater(
      segmenter.embed('/tmp/exited.png'),
      throwsA(
        isA<SubjectSegmentationException>().having(
          (error) => error.kind,
          'kind',
          SubjectFailureKind.processDied,
        ),
      ),
    );
  });

  test('cancelActive completes pending requests as cancelled', () async {
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _blockedWorker],
        environment: Platform.environment,
      ),
      requestTimeout: const Duration(seconds: 5),
    );
    addTearDown(segmenter.close);

    final pending = segmenter.embed('/tmp/cancel.png');
    final expectation = expectLater(
      pending,
      throwsA(
        isA<SubjectSegmentationException>().having(
          (error) => error.kind,
          'kind',
          SubjectFailureKind.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await segmenter.cancelActive().timeout(const Duration(seconds: 1));
    await expectation;
  });

  test('typed model_missing exposes fetch command', () async {
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _modelMissingWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(segmenter.close);

    await expectLater(
      segmenter.embed('/tmp/image.png'),
      throwsA(
        isA<SubjectSegmentationException>()
            .having(
              (error) => error.kind,
              'kind',
              SubjectFailureKind.modelMissing,
            )
            .having(
              (error) => error.command,
              'command',
              'kiriglyph-fetch-models',
            ),
      ),
    );
  });

  test('close force kills an unresponsive segmentation worker', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kiriglyph-seg-pid-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final pidFile = File('${directory.path}/pid');
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: ['-u', '-c', _pidWorker, pidFile.path],
        environment: Platform.environment,
      ),
      requestTimeout: const Duration(seconds: 5),
      shutdownTimeout: const Duration(milliseconds: 100),
      forceKillTimeout: const Duration(milliseconds: 500),
    );

    final pending = segmenter.embed('/tmp/shutdown.png');
    final closed = expectLater(
      pending,
      throwsA(isA<SubjectSegmentationException>()),
    );
    for (var attempt = 0; attempt < 20 && !pidFile.existsSync(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    final pid = int.parse(await pidFile.readAsString());

    await segmenter.close().timeout(const Duration(seconds: 1));
    await closed;

    expect(Directory('/proc/$pid').existsSync(), isFalse);
  });
}
