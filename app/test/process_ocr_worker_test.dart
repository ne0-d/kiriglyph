import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/protocol/protocol_error.dart';
import 'package:kiriglyph/worker/process_ocr_worker.dart';

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

const _persistentPidWorker = r'''
import json
import os
import sys

for line in sys.stdin.buffer:
    request = json.loads(line)
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

const _reverseResponseWorker = r'''
import json
import sys

requests = [
    json.loads(sys.stdin.buffer.readline()),
    json.loads(sys.stdin.buffer.readline()),
]
for request in reversed(requests):
    response = {
        "version": 1,
        "id": request["id"],
        "ok": True,
        "result": {
            "image": {"width": 1, "height": 1},
            "full_text": request["params"]["image_path"],
            "regions": [],
            "timings_ms": {"total": 0},
        },
    }
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
''';

const _blockedWorker = r'''
import sys
import time

for _ in sys.stdin.buffer:
    time.sleep(10)
''';

const _ignoresShutdownWorker = r'''
import os
import signal
import sys
import time

with open(sys.argv[1], "w", encoding="utf-8") as pid_file:
    pid_file.write(str(os.getpid()))
signal.signal(signal.SIGTERM, lambda *_: None)
for _ in sys.stdin.buffer:
    time.sleep(10)
''';

const _cooperativeShutdownWorker = r'''
import json
import sys

for line in sys.stdin.buffer:
    request = json.loads(line)
    response = {
        "version": 1,
        "id": request["id"],
        "ok": True,
        "result": {
            "image": {"width": 1, "height": 1},
            "full_text": "ok",
            "regions": [],
            "timings_ms": {"total": 0},
        },
    }
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
with open(sys.argv[1], "w", encoding="utf-8") as marker:
    marker.write("stdin closed")
''';

const _malformedResponseWorker = r'''
import sys

sys.stdin.buffer.readline()
sys.stdout.write("{not json\n")
sys.stdout.flush()
''';

const _missingResponseIdWorker = r'''
import json
import sys

sys.stdin.buffer.readline()
sys.stdout.write(json.dumps({"version": 1, "ok": True, "result": {}}) + "\n")
sys.stdout.flush()
''';

const _exitingWorker = r'''
import sys

sys.stdin.buffer.readline()
sys.exit(7)
''';

const _diagnosticWorker = r'''
import json
import sys

request = json.loads(sys.stdin.buffer.readline())
print("private image path and recognized words", file=sys.stderr, flush=True)
response = {
    "version": 1,
    "id": request["id"],
    "ok": True,
    "result": {
        "image": {"width": 1, "height": 1},
        "full_text": "ok",
        "regions": [],
        "timings_ms": {"total": 0},
    },
}
sys.stdout.write(json.dumps(response) + "\n")
sys.stdout.flush()
''';

void main() {
  test('correlates out-of-order responses by request ID', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _reverseResponseWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(worker.close);

    final results = await Future.wait([
      worker.recognize('/tmp/first.png'),
      worker.recognize('/tmp/second.png'),
    ]).timeout(const Duration(seconds: 2));

    expect(results[0].fullText, '/tmp/first.png');
    expect(results[1].fullText, '/tmp/second.png');
  });

  test('times out an unresponsive recognition request', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _blockedWorker],
        environment: Platform.environment,
      ),
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(worker.close);

    await expectLater(
      worker.recognize('/tmp/blocked.png'),
      throwsA(
        isA<WorkerProcessError>().having(
          (error) => error.kind,
          'kind',
          WorkerFailureKind.timeout,
        ),
      ),
    );
  });

  test('reports malformed worker stdout as a typed failure', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _malformedResponseWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(worker.close);

    await expectLater(
      worker.recognize('/tmp/malformed.png'),
      throwsA(
        isA<WorkerProcessError>().having(
          (error) => error.kind,
          'kind',
          WorkerFailureKind.malformedResponse,
        ),
      ),
    );
  });

  test('reports a response without an ID as malformed', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _missingResponseIdWorker],
        environment: Platform.environment,
      ),
      requestTimeout: const Duration(seconds: 2),
    );
    addTearDown(worker.close);

    await expectLater(
      worker.recognize('/tmp/missing-id.png'),
      throwsA(
        isA<WorkerProcessError>().having(
          (error) => error.kind,
          'kind',
          WorkerFailureKind.malformedResponse,
        ),
      ),
    );
  });

  test('reports worker startup failure as a typed failure', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: '/definitely/missing/kiriglyph-worker',
        arguments: const [],
        environment: Platform.environment,
      ),
    );
    addTearDown(worker.close);

    await expectLater(
      worker.recognize('/tmp/startup.png'),
      throwsA(
        isA<WorkerProcessError>().having(
          (error) => error.kind,
          'kind',
          WorkerFailureKind.startup,
        ),
      ),
    );
  });

  test('reports worker exit while recognizing as a typed failure', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _exitingWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(worker.close);

    await expectLater(
      worker.recognize('/tmp/exited.png'),
      throwsA(
        isA<WorkerProcessError>().having(
          (error) => error.kind,
          'kind',
          WorkerFailureKind.exited,
        ),
      ),
    );
  });

  test('cancellation immediately stops waiting for recognition', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _blockedWorker],
        environment: Platform.environment,
      ),
      requestTimeout: const Duration(seconds: 5),
    );
    addTearDown(worker.close);

    final recognition = worker.recognize('/tmp/cancel.png');
    final expectation = expectLater(
      recognition,
      throwsA(
        isA<WorkerProcessError>().having(
          (error) => error.kind,
          'kind',
          WorkerFailureKind.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await worker.cancelActive().timeout(const Duration(seconds: 1));
    await expectation;
  });

  test('restart replaces the worker before the next recognition', () async {
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _persistentPidWorker],
        environment: Platform.environment,
      ),
    );
    addTearDown(worker.close);

    final first = await worker.recognize('/tmp/first.png');
    await worker.restart();
    final second = await worker.recognize('/tmp/second.png');

    expect(second.fullText, isNot(first.fullText));
  });

  test(
    'close force-terminates an unresponsive worker without orphaning it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kiriglyph-worker-close-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final pidFile = File('${directory.path}/pid');
      final worker = ProcessOcrWorker(
        WorkerLaunchConfig(
          executable: 'python3',
          arguments: ['-u', '-c', _ignoresShutdownWorker, pidFile.path],
          environment: Platform.environment,
        ),
        requestTimeout: const Duration(seconds: 5),
        shutdownTimeout: const Duration(milliseconds: 100),
        forceKillTimeout: const Duration(milliseconds: 500),
      );

      final recognition = worker.recognize('/tmp/shutdown.png');
      final recognitionClosed = expectLater(
        recognition,
        throwsA(
          isA<WorkerProcessError>().having(
            (error) => error.kind,
            'kind',
            WorkerFailureKind.closed,
          ),
        ),
      );
      for (var attempt = 0; attempt < 20 && !pidFile.existsSync(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(pidFile.existsSync(), isTrue);
      final pid = int.parse(await pidFile.readAsString());

      await worker.close().timeout(const Duration(seconds: 1));
      await recognitionClosed;

      expect(Directory('/proc/$pid').existsSync(), isFalse);
    },
  );

  test('close shuts down a cooperative worker through stdin EOF', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kiriglyph-worker-eof-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final marker = File('${directory.path}/closed');
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: ['-u', '-c', _cooperativeShutdownWorker, marker.path],
        environment: Platform.environment,
      ),
    );

    await worker.recognize('/tmp/shutdown.png');
    await worker.close();

    expect(await marker.readAsString(), 'stdin closed');
  });

  test('stderr reports only a redacted diagnostic event', () async {
    final diagnostics = <String>[];
    final worker = ProcessOcrWorker(
      WorkerLaunchConfig(
        executable: 'python3',
        arguments: const ['-u', '-c', _diagnosticWorker],
        environment: Platform.environment,
      ),
      onDiagnostic: diagnostics.add,
    );
    addTearDown(worker.close);

    await worker.recognize('/tmp/private-image.png');
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(diagnostics, ['worker diagnostic received']);
    expect(diagnostics.join(), isNot(contains('private')));
    expect(diagnostics.join(), isNot(contains('/tmp/')));
  });

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
