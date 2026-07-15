import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/protocol/protocol_error.dart';
import 'package:ubuntu_live_text/protocol/worker_protocol.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';

class WorkerLaunchConfig {
  const WorkerLaunchConfig({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
}

class ProcessOcrWorker implements OcrWorker {
  ProcessOcrWorker(this._launchConfig);

  final WorkerLaunchConfig _launchConfig;
  int _requestCounter = 0;

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  final _pending =
      <String, Completer<({OcrResult? result, WorkerError? error})>>{};

  Future<void> _ensureStarted() async {
    if (_process != null) {
      return;
    }

    final process = await Process.start(
      _launchConfig.executable,
      _launchConfig.arguments,
      workingDirectory: _launchConfig.workingDirectory,
      environment: _launchConfig.environment,
    );
    _process = process;

    _stdoutSubscription = process.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen(
          _dispatchLine,
          onError: (Object _) {
            _failAll(ProtocolError('worker stdout stream failed'));
          },
          onDone: () {
            if (identical(_process, process)) {
              _process = null;
              _stdoutSubscription = null;
            }
            _failAll(ProtocolError('worker process exited unexpectedly'));
          },
        );

    process.stderr.listen((_) {
      // Diagnostics only; never mixed into protocol parsing.
    });
  }

  void _dispatchLine(String line) {
    String? responseId;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map && decoded['id'] is String) {
        responseId = decoded['id'] as String;
      }
    } catch (_) {
      _failAll(ProtocolError('worker sent malformed JSON'));
      return;
    }

    if (responseId == null || !_pending.containsKey(responseId)) {
      return;
    }

    final completer = _pending.remove(responseId)!;
    try {
      final parsed = parseResponseLine(line, expectedId: responseId);
      completer.complete(parsed);
    } on ProtocolError catch (error) {
      completer.completeError(error);
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  @override
  Future<OcrResult> recognize(String imagePath) async {
    await _ensureStarted();
    final id =
        'req-${++_requestCounter}-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<({OcrResult? result, WorkerError? error})>();
    _pending[id] = completer;

    final requestLine =
        '${encodeRecognizeRequest(id: id, imagePath: imagePath)}\n';
    _process!.stdin.add(utf8.encode(requestLine));
    await _process!.stdin.flush();

    final response = await completer.future;
    final workerError = response.error;
    if (workerError != null) {
      throw workerError;
    }
    final result = response.result;
    if (result == null) {
      throw ProtocolError('successful response missing result');
    }
    return result;
  }

  @override
  Future<void> close() async {
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _failAll(ProtocolError('worker closed'));
    final process = _process;
    _process = null;
    if (process != null) {
      process.stdin.close();
      if (_pending.isEmpty) {
        await process.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
      } else {
        process.kill();
      }
    }
  }
}
