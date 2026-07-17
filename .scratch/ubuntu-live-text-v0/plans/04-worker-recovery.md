# Worker Recovery Implementation Plan

> **For agentic workers:** implement each task as an independent red-green
> slice. Do not run open-ended test or debugging loops.

**Goal:** Make local OCR cancellation, timeout, protocol failure, process death,
retry, and shutdown deterministic and recoverable without stale capture state.

**Architecture:** `ProcessOcrWorker` owns the Python child-process lifecycle and
exposes recognition, cancellation, restart, and shutdown through `OcrWorker`.
`CaptureSessionController` owns a monotonically increasing operation token so
only the active capture may update UI state. Widgets consume typed capture
outcomes and never manipulate processes.

**Tech stack:** Dart async/process APIs, Riverpod, Flutter widget tests, Python
fixture subprocesses.

## Global constraints

- Keep one reusable Python worker during normal operation.
- Keep protocol stdout separate from redacted stderr diagnostics.
- Never expose raw image paths, recognized text, or raw stderr to users.
- Cancellation returns immediately to the empty Open image state.
- Retry uses the same image only after a clean worker restart.
- Use public `OcrWorker` and `captureSessionProvider` test seams.
- Run every targeted command with a 60-second timeout and the final suite with
  a 120-second timeout.
- Do not create commits; the user owns commits.

---

### Task 1: Typed worker lifecycle

**Files:**
- Modify: `app/lib/worker/ocr_worker.dart`
- Modify: `app/lib/protocol/protocol_error.dart`
- Modify: `app/lib/worker/process_ocr_worker.dart`
- Test: `app/test/process_ocr_worker_test.dart`

**Interfaces:**
- `OcrWorker.recognize(String imagePath) -> Future<OcrResult>`
- `OcrWorker.cancelActive() -> Future<void>`
- `OcrWorker.restart() -> Future<void>`
- `OcrWorker.close() -> Future<void>`
- `WorkerProcessError.kind -> WorkerFailureKind`

- [ ] Add a failing public-API test in
  `app/test/process_ocr_worker_test.dart` proving two concurrent requests are
  completed by matching response IDs even when responses arrive in reverse
  order.
- [ ] Run:
  `timeout 60s ../.tools/flutter/bin/flutter test test/process_ocr_worker_test.dart --plain-name "correlates out-of-order responses by request ID" -r expanded`
  and confirm the test fails because the fixture or lifecycle behavior is not
  yet supported.
- [ ] Add only the request-correlation synchronization required to pass, then
  rerun the exact command and confirm it passes.
- [ ] Add one failing test for each externally visible process behavior:
  malformed stdout produces `WorkerFailureKind.malformedResponse`; process
  death produces `WorkerFailureKind.exited`; request timeout produces
  `WorkerFailureKind.timeout`; startup failure produces
  `WorkerFailureKind.startup`.
- [ ] Implement `WorkerFailureKind` and `WorkerProcessError`, add configurable
  recognition and shutdown durations to `ProcessOcrWorker`, and invalidate the
  current process after fatal stream, exit, or timeout failures.
- [ ] Run the targeted process-worker file after each slice.
- [ ] Add a failing cancellation test proving `cancelActive()` completes the
  waiting recognition with `WorkerFailureKind.cancelled` before a deliberately
  blocked Python fixture returns.
- [ ] Implement cancellation by completing pending requests first, detaching
  the current process generation, and terminating that child. Leave startup
  lazy until the next `recognize`.
- [ ] Add a failing restart test proving `restart()` replaces the process and a
  subsequent request succeeds with a different PID.
- [ ] Implement one bounded explicit restart: terminate the current generation,
  start one clean worker, and propagate startup failure without an automatic
  retry loop.
- [ ] Add shutdown tests for a cooperative worker and one that ignores stdin
  EOF/termination. Assert `close()` finishes within its configured bound.
- [ ] Implement graceful shutdown by closing stdin and waiting briefly, then
  terminate and finally force-kill an unresponsive process.
- [ ] Add a diagnostic callback test asserting a stderr event is reported but
  its raw text is not forwarded. Implement a redacted diagnostic notification
  containing no stderr content.
- [ ] Run:
  `timeout 60s ../.tools/flutter/bin/flutter test test/process_ocr_worker_test.dart -r expanded`
  and confirm all process-worker tests pass.

### Task 2: Active capture operation and outcome mapping

**Files:**
- Modify: `app/lib/capture/capture_session.dart`
- Modify: `app/test/capture_session_test.dart`
- Modify test fakes implementing `OcrWorker` under `app/test/`

**Interfaces:**
- `CaptureSessionController.openImage() -> Future<void>`
- `CaptureSessionController.cancelRecognition() -> Future<void>`
- `CaptureSessionController.retry() -> Future<void>`
- `CaptureSessionState.failure -> CaptureFailure?`

- [ ] Add a controllable fake worker to `capture_session_test.dart` and a
  failing test where request A starts, request B becomes active, and A
  completes last. Assert only B can set the ready result.
- [ ] Add an operation counter to `CaptureSessionController`; capture its value
  for every picker/recognition operation and check it before every state write.
- [ ] Add a failing cancellation test proving state becomes idle immediately,
  the worker receives `cancelActive`, and a later completion cannot restore a
  result.
- [ ] Implement `cancelRecognition()` by invalidating the active operation,
  setting the default idle state before awaiting worker cancellation, and
  ignoring cancellation errors.
- [ ] Add parameterized failing tests for startup, exit, timeout, malformed
  response, OCR failure, no text, and unreadable input. Assert distinct
  `CaptureFailure` values and stable user-safe messages.
- [ ] Implement typed mapping in one private mapper. Preserve the selected image
  path in error state so retry can reuse it.
- [ ] Add a failing retry test proving `restart()` happens before recognizing
  the same image and the successful result replaces the error.
- [ ] Implement `retry()` as one explicit restart followed by one recognition;
  do not add automatic retry/backoff.
- [ ] Update every test fake that implements `OcrWorker` with deterministic
  `cancelActive` and `restart` behavior.
- [ ] Run:
  `timeout 60s ../.tools/flutter/bin/flutter test test/capture_session_test.dart test/region_selection_session_test.dart -r expanded`.

### Task 3: Recoverable UI controls

**Files:**
- Modify: `app/lib/ui/app_header.dart`
- Modify: `app/lib/ui/status_views.dart`
- Modify: `app/test/result_workspace_test.dart`

**Interfaces:**
- Button key `cancel-recognition`
- Button key `retry-recognition`

- [ ] Add a failing widget test with a pending worker. While recognizing,
  assert a Cancel control exists; activate it and assert the empty state
  appears without waiting for worker completion.
- [ ] Add responsive Cancel controls to `AppHeader`: text on normal widths and
  an icon with tooltip on compact widths.
- [ ] Add a failing widget test where recognition fails. Assert the typed
  message and Retry control appear; activate Retry and assert the same image
  reaches the ready workspace after a clean restart.
- [ ] Add responsive Retry controls and keep Open image available for choosing a
  different file.
- [ ] Verify 360×640 and 640×300 recognizing/error layouts do not overflow.
- [ ] Run:
  `timeout 60s ../.tools/flutter/bin/flutter test test/result_workspace_test.dart -r expanded`.

### Task 4: Verification and ticket closure

**Files:**
- Modify: `.scratch/ubuntu-live-text-v0/issues/04-worker-recovery.md`

- [ ] Format changed Dart files:
  `timeout 60s ../.tools/flutter/bin/dart format lib test`.
- [ ] Analyze:
  `timeout 60s ../.tools/flutter/bin/flutter analyze`.
- [ ] Run the complete Flutter suite:
  `timeout 120s ../.tools/flutter/bin/flutter test -r expanded`.
- [ ] Run the existing Python suite because worker protocol behavior remains an
  integration dependency:
  `timeout 120s ../.tools/uv-bin/uv run --project worker pytest worker/tests -q`.
- [ ] Build Linux debug:
  `timeout 120s ../.tools/flutter/bin/flutter build linux --debug`.
- [ ] Check IDE diagnostics and `git diff --check`.
- [ ] Mark issue 04 resolved only when every acceptance item has corresponding
  passing evidence.
