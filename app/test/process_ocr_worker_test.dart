import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_live_text/worker/process_ocr_worker.dart';

const _splitUtf8Responder = r'''
import json
import sys
import time

for line in sys.stdin.buffer:
    request = json.loads(line)
    response = {
        "version": 1,
        "id": request["id"],
        "ok": True,
        "result": {
            "image": {"width": 1, "height": 1},
            "full_text": "café",
            "regions": [],
            "timings_ms": {"total": 0},
        },
    }
    payload = (json.dumps(response, ensure_ascii=False) + "\n").encode("utf-8")
    split_at = payload.index("é".encode("utf-8")) + 1
    sys.stdout.buffer.write(payload[:split_at])
    sys.stdout.buffer.flush()
    time.sleep(0.1)
    sys.stdout.buffer.write(payload[split_at:])
    sys.stdout.buffer.flush()
''';

const _singleResponseWorker = r'''
import json
import os
import sys

request = json.loads(sys.stdin.buffer.readline())
response = {
    "version": 1,
    "id": request["id"],
    "ok": True,
    "result": {
        "image": {"width": 1, "height": 1},
        "full_text": str(os.getpid()),
        "regions": [],
        "timings_ms": {"total": 0},
    },
}
sys.stdout.write(json.dumps(response) + "\n")
sys.stdout.flush()
''';

void main() {
  test('recognize accepts UTF-8 split across stdout chunks', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _splitUtf8Responder],
        environment: Platform.environment,
      ),
    );
    addTearDown(worker.close);

    final result = await worker
        .recognize('/tmp/not-read-by-test-worker.png')
        .timeout(const Duration(seconds: 3));

    expect(result.fullText, 'café');
  });

  test('recognize restarts a worker that exited between requests', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _singleResponseWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(worker.close);

    final first = await worker.recognize('/tmp/first.png');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final second = await worker
        .recognize('/tmp/second.png')
        .timeout(const Duration(seconds: 3));

    expect(second.fullText, isNot(first.fullText));
  });
}
