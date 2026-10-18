import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/segmentation/process_subject_segmenter.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/worker/process_ocr_worker.dart';

import 'support/golden_replies.dart';

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
import sys
from pathlib import Path

golden_dir = Path(sys.argv[1])
mask_path = sys.argv[2]
embed_line = (golden_dir / "segmentation-embed-ok.ndjson").read_text(encoding="utf-8").strip()
prompt_line = (golden_dir / "segmentation-prompt-ok.ndjson").read_text(encoding="utf-8").strip()
Path(mask_path).write_bytes((golden_dir / "masks" / "prompt-ok.png").read_bytes())

def with_request(line, request):
    body = json.loads(line)
    updated = line.replace('"id":"' + body["id"] + '"', '"id":"' + request["id"] + '"', 1)
    if request["method"] == "prompt":
        recorded = body["result"]["mask"]["path"]
        updated = updated.replace('"path":"' + recorded + '"', '"path":"' + mask_path + '"', 1)
    return updated

for raw in sys.stdin.buffer:
    request = json.loads(raw)
    if request["method"] == "close":
        sys.stdout.write(json.dumps({"version": 1, "id": request["id"], "ok": True, "result": {"closed": True}}) + "\n")
        sys.stdout.flush()
        break
    source = embed_line if request["method"] == "embed" else prompt_line
    sys.stdout.write(with_request(source, request) + "\n")
    sys.stdout.flush()
''';

const _tamperedMaskWorker = r'''
import json
import sys
from pathlib import Path

mask_path = sys.argv[1]
embed_line = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
Path(mask_path).write_bytes(b"tampered")

for raw in sys.stdin.buffer:
    request = json.loads(raw)
    if request["method"] == "embed":
        body = json.loads(embed_line)
        line = embed_line.replace('"id":"' + body["id"] + '"', '"id":"' + request["id"] + '"', 1)
    else:
        # Golden prompt shape, with a digest that does not match the bytes above.
        recorded = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
        result = recorded["result"]
        result["mask"]["path"] = mask_path
        result["mask"]["byte_length"] = 4
        result["mask"]["sha256"] = "48bf9b4f142ab45cac6f33cf99415bca6ca8e07608a031237aa76560fec2204b"
        line = json.dumps({"version": 1, "id": request["id"], "ok": True, "result": result}, separators=(",", ":"))
    sys.stdout.write(line + "\n")
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
from pathlib import Path

line = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
request = json.loads(sys.stdin.buffer.readline())
body = json.loads(line)
sys.stdout.write(line.replace('"id":"' + body["id"] + '"', '"id":"' + request["id"] + '"', 1) + "\n")
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
        arguments: ['-u', '-c', _promptWorker, goldenDirectory.path, mask.path],
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

  test('rejects a mask whose bytes do not match the manifest', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kiriglyph-mask-tamper-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final mask = File('${directory.path}/mask.png');
    final segmenter = ProcessSubjectSegmenter(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: [
          '-u',
          '-c',
          _tamperedMaskWorker,
          mask.path,
          '${goldenDirectory.path}/segmentation-embed-ok.ndjson',
          '${goldenDirectory.path}/segmentation-prompt-ok.ndjson',
        ],
        environment: Platform.environment,
      ),
    );
    addTearDown(segmenter.close);

    final embedding = await segmenter.embed('/tmp/image.png');

    await expectLater(
      segmenter.prompt(
        embedding,
        const SubjectPrompt(points: [SubjectPoint(4, 3)]),
      ),
      throwsA(
        isA<SubjectSegmentationException>()
            .having(
              (error) => error.kind,
              'kind',
              SubjectFailureKind.malformedOutput,
            )
            .having(
              (error) => error.message,
              'message',
              'Subject mask integrity check failed. Try again.',
            ),
      ),
    );
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
        arguments: [
          '-u',
          '-c',
          _modelMissingWorker,
          '${goldenDirectory.path}/segmentation-model-missing.ndjson',
        ],
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
