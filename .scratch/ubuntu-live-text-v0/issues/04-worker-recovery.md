# 04: Recover from worker and OCR failures

**What to build:** A user receives clear, recoverable outcomes when recognition is cancelled, times out, returns malformed data, or the Python worker exits, without stale results appearing in a later capture session.

**Blocked by:** 02: Recognize a local image with RapidOCR.

**Status:** ready-for-agent

- [ ] Concurrent protocol responses are correlated by request ID and stale responses cannot mutate the active capture session.
- [ ] User cancellation stops waiting immediately; V0 may restart the worker to cancel in-flight native inference safely.
- [ ] Startup failure, worker exit, timeout, malformed message, OCR failure, no text, and unsupported input are distinct outcomes.
- [ ] The application can restart the worker within a bounded policy and retry from a clean state.
- [ ] Graceful application shutdown closes stdin, waits briefly, and terminates an unresponsive worker without orphaning it.
- [ ] Tests exercise malformed stdout, stderr diagnostics, delayed responses, out-of-order IDs, process death, restart, cancellation, and shutdown.
