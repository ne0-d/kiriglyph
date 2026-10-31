import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_identity.dart';
import 'package:kiriglyph/capture/portal_helper_capture.dart';
import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/diagnostics/timing_log.dart';
import 'package:kiriglyph/export/screenshot_export.dart';
import 'package:kiriglyph/export/subject_export.dart';
import 'package:kiriglyph/segmentation/process_subject_segmenter.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/settings/app_settings.dart';
import 'package:kiriglyph/web/link_opener.dart';
import 'package:kiriglyph/web/web_search_launcher.dart';
import 'package:kiriglyph/worker/ocr_worker.dart';
import 'package:kiriglyph/worker/process_ocr_worker.dart';

WorkerLaunchConfig defaultWorkerLaunchConfig({
  String module = 'worker',
  List<String> extraArguments = const [],
}) {
  final envRoot = Platform.environment['KIRIGLYPH_WORKER_ROOT'];
  final workerRoot = envRoot ?? '${Directory.current.parent.path}/worker';
  final srcPath = '$workerRoot/src';
  return WorkerLaunchConfig(
    executable: Platform.environment['KIRIGLYPH_WORKER_PYTHON'] ?? 'python3',
    arguments: ['-m', module, ...extraArguments],
    workingDirectory: workerRoot,
    environment: {...Platform.environment, 'PYTHONPATH': srcPath},
  );
}

/// Non-interactive capture of every display, registered under the app ID.
WorkerLaunchConfig silentCaptureLaunchConfig() => defaultWorkerLaunchConfig(
  module: 'worker.portal_capture',
  extraArguments: const ['--silent', '--app-id', kiriglyphAppId],
);

final screenCaptureProvider = Provider<ScreenCapturePort>((ref) {
  final capture = PortalHelperScreenCapture(
    defaultWorkerLaunchConfig(module: 'worker.portal_capture'),
  );
  ref.onDispose(capture.cancel);
  return capture;
});

final silentScreenCaptureProvider = Provider<ScreenCapturePort>((ref) {
  final capture = PortalHelperScreenCapture(silentCaptureLaunchConfig());
  ref.onDispose(capture.cancel);
  return capture;
});

final sessionImageStoreProvider = Provider<SessionImageStore>((ref) {
  final store = SessionImageStore();
  ref.onDispose(store.dispose);
  return store;
});

final ocrWorkerProvider = Provider<OcrWorker>((ref) {
  final worker = ProcessOcrWorker(defaultWorkerLaunchConfig());
  ref.onDispose(() {
    worker.close();
  });
  return worker;
});

final subjectSegmenterProvider = Provider<SubjectSegmenter>((ref) {
  final segmenter = ProcessSubjectSegmenter(
    defaultWorkerLaunchConfig(module: 'worker.segmentation_worker'),
  );
  ref.onDispose(() {
    unawaited(segmenter.close().catchError((_) {}));
  });
  return segmenter;
});

final clipboardImagePortProvider = Provider<ClipboardImagePort>(
  (ref) => PlatformClipboardImagePort(),
);

final savePngPortProvider = Provider<SavePngPort>(
  (ref) => PlatformSavePngPort(folder: () => ref.read(saveDirectoryProvider)),
);

final subjectImageCodecProvider = Provider<SubjectImageCodec>(
  (ref) => const EngineSubjectImageCodec(),
);

final screenshotClipboardPortProvider = Provider<ScreenshotClipboardPort>(
  (ref) => PlatformScreenshotClipboardPort(),
);

final screenshotImageCodecProvider = Provider<ScreenshotImageCodec>(
  (ref) => const EngineScreenshotImageCodec(),
);

final screenshotExportControllerProvider = Provider<ScreenshotExportController>(
  (ref) => ScreenshotExportController(
    clipboard: ref.watch(screenshotClipboardPortProvider),
    codec: ref.watch(screenshotImageCodecProvider),
    picturesDirectory: () => ref.read(saveDirectoryProvider),
  ),
);

final linkOpenerProvider = Provider<LinkOpener>((ref) => const LinkOpener());

final webSearchLauncherProvider = Provider<WebSearchLauncher>(
  (ref) => const WebSearchLauncher(),
);

final subjectExportControllerProvider = Provider<SubjectExportController>(
  (ref) => SubjectExportController(
    clipboard: ref.watch(clipboardImagePortProvider),
    savePort: ref.watch(savePngPortProvider),
    codec: ref.watch(subjectImageCodecProvider),
    onTimingPhase: ref.watch(timingLogProvider).mark,
    picturesDirectory: () => ref.read(saveDirectoryProvider),
  ),
);
