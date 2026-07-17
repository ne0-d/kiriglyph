# 01: Run a mock OCR result end to end

**What to build:** A contributor can bootstrap and launch the Flutter application and Python worker, choose a fixture image, send a versioned request through the local NDJSON process interface, and see a mock text region rendered over the image with synchronized text.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] Flutter and Python dependencies are reproducibly locked and developer bootstrap/run instructions work on Ubuntu 24.04.
- [x] Flutter launches one long-lived Python worker and performs a versioned request/response exchange with request IDs.
- [x] Protocol envelopes and the OCR result are validated against shared JSON schemas.
- [x] Selecting a fixture image produces a visible mock text region and synchronized selectable text.
- [x] Worker diagnostics use stderr; stdout contains protocol messages only.
- [x] Contract, Flutter state, and basic widget tests cover the successful vertical slice.

## Answer

The mock vertical slice is implemented and user-verified on Ubuntu. Flutter opens
an image, communicates with one local Python worker through the versioned NDJSON
contract, and renders a schema-valid region with synchronized selectable text.
