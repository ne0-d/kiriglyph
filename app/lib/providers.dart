import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/picker/file_selector_picker.dart';
import 'package:ubuntu_live_text/picker/image_picker_port.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';
import 'package:ubuntu_live_text/worker/process_ocr_worker.dart';

WorkerLaunchConfig defaultWorkerLaunchConfig() {
  final envRoot = Platform.environment['LIVE_TEXT_WORKER_ROOT'];
  final workerRoot = envRoot ?? '${Directory.current.parent.path}/worker';
  final srcPath = '$workerRoot/src';
  return WorkerLaunchConfig(
    executable: Platform.environment['LIVE_TEXT_WORKER_PYTHON'] ?? 'python3',
    arguments: const ['-m', 'worker'],
    workingDirectory: workerRoot,
    environment: {...Platform.environment, 'PYTHONPATH': srcPath},
  );
}

final imagePickerProvider = Provider<ImagePickerPort>(
  (ref) => FileSelectorImagePicker(),
);

final ocrWorkerProvider = Provider<OcrWorker>((ref) {
  final worker = ProcessOcrWorker(defaultWorkerLaunchConfig());
  ref.onDispose(() {
    worker.close();
  });
  return worker;
});
