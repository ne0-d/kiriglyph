# 04: Recover from worker and OCR failures

**What to build:** A user receives clear, recoverable outcomes when recognition is cancelled, times out, returns malformed data, or the Python worker exits, without stale results appearing in a later capture session.

**Blocked by:** 02: Recognize a local image with RapidOCR.

**Status:** resolved

- [x] Concurrent protocol responses are correlated by request ID and stale responses cannot mutate the active capture session.
- [x] User cancellation stops waiting immediately; V0 may restart the worker to cancel in-flight native inference safely.
- [x] Startup failure, worker exit, timeout, malformed message, OCR failure, no text, and unsupported input are distinct outcomes.
- [x] The application can restart the worker within a bounded policy and retry from a clean state.
- [x] Graceful application shutdown closes stdin, waits briefly, and terminates an unresponsive worker without orphaning it.
- [x] Tests exercise malformed stdout, stderr diagnostics, delayed responses, out-of-order IDs, process death, restart, cancellation, and shutdown.

## Approved design

- Keep process supervision inside `ProcessOcrWorker`; UI and Riverpod state do
  not launch, kill, or inspect Python processes.
- Extend the `OcrWorker` boundary with explicit cancellation and restart
  operations. Cancelling completes active waits immediately, terminates the
  current worker, and leaves lazy startup to the next recognition request.
- Correlate responses by request ID and give each capture operation a
  monotonically increasing token. Unknown, late, or superseded responses
  cannot mutate the active capture session.
- Apply a bounded recognition timeout. Distinguish startup failure, worker
  exit, timeout, malformed protocol, cancellation, OCR failure, no text, and
  unreadable or unsupported input.
- Retry the same image only after a clean worker restart. User cancellation
  returns to the empty Open image state.
- Close stdin during shutdown, wait briefly for a clean exit, then terminate
  an unresponsive child so the application does not leave an orphan process.
- Keep stderr as redacted developer diagnostics only; never expose raw
  diagnostics as user-facing errors.

## Approved test seams

- Test `OcrWorker` through its public API for request correlation, malformed
  stdout, timeout, cancellation, restart, process death, stderr diagnostics,
  and graceful or forced shutdown.
- Test `captureSessionProvider` for stale-result rejection, cancel-to-idle,
  retry, and distinct user-visible outcomes.
- Add a focused widget test for Cancel and Retry controls. Do not test private
  process-supervisor or Riverpod implementation details.

## Verification

- Flutter analyzer reports no issues.
- All 91 Flutter tests pass.
- All 37 Python worker tests pass.
- The Linux debug desktop bundle builds successfully.
- Process tests cover concurrent out-of-order responses, malformed JSON and
  missing IDs, startup failure, process exit, timeout, cancellation, explicit
  restart, redacted diagnostics, graceful EOF shutdown, and forced shutdown
  without an orphan process.
