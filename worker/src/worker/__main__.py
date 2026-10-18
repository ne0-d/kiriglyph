from __future__ import annotations

import sys

from worker.protocol import (
    MAX_NDJSON_LINE_BYTES,
    ErrorCode,
    DECODE_CODES_METHOD,
    RECOGNIZE_METHOD,
    encode_response,
    error_response,
    handle_decode_codes,
    handle_recognize,
    parse_request_line,
)
from worker.rapidocr_engine import OcrEngine, RapidOcrEngine


def _log_diagnostic(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def _drain_oversized_line() -> None:
    while True:
        chunk = sys.stdin.buffer.readline(MAX_NDJSON_LINE_BYTES)
        if chunk == b"" or chunk.endswith(b"\n"):
            return


def process_request_line(raw_line: bytes, engine: OcrEngine) -> dict:
    if len(raw_line) > MAX_NDJSON_LINE_BYTES:
        return error_response(
            None,
            ErrorCode.MALFORMED_JSON,
            "request line exceeds maximum length",
        )

    try:
        line = raw_line.rstrip(b"\n").decode("utf-8")
    except UnicodeDecodeError:
        return error_response(
            None,
            ErrorCode.MALFORMED_JSON,
            "request line is not valid UTF-8 JSON",
        )

    request, error = parse_request_line(line)
    if error is not None:
        return error

    assert request is not None
    try:
        if request.method == RECOGNIZE_METHOD:
            return handle_recognize(request, engine)
        if request.method == DECODE_CODES_METHOD:
            return handle_decode_codes(request)
        return error_response(
            request.id,
            ErrorCode.UNSUPPORTED_METHOD,
            "unsupported method",
        )
    except Exception:  # noqa: BLE001 - final process boundary maps unknown failures.
        return error_response(request.id, ErrorCode.INTERNAL_ERROR, "request failed")


def run_loop() -> None:
    engine = RapidOcrEngine()
    while True:
        raw_line = sys.stdin.buffer.readline(MAX_NDJSON_LINE_BYTES + 1)
        if raw_line == b"":
            return
        if raw_line == b"\n":
            continue
        if len(raw_line) > MAX_NDJSON_LINE_BYTES and not raw_line.endswith(b"\n"):
            _drain_oversized_line()

        _log_diagnostic("request received")
        response = process_request_line(raw_line, engine)
        if response.get("ok") is True:
            _log_diagnostic("request finished")
        else:
            _log_diagnostic("request failed")
        sys.stdout.write(encode_response(response) + "\n")
        sys.stdout.flush()


def main() -> None:
    try:
        run_loop()
    except BrokenPipeError:
        pass


if __name__ == "__main__":
    main()
