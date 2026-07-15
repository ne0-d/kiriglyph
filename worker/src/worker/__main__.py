from __future__ import annotations

import sys

from worker.protocol import (
    MAX_NDJSON_LINE_BYTES,
    encode_response,
    error_response,
    handle_recognize,
    parse_request_line,
)


def _log_diagnostic(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def _drain_oversized_line() -> None:
    while True:
        chunk = sys.stdin.buffer.readline(MAX_NDJSON_LINE_BYTES)
        if chunk == b"" or chunk.endswith(b"\n"):
            return


def process_request_line(raw_line: bytes) -> dict:
    if len(raw_line) > MAX_NDJSON_LINE_BYTES:
        return error_response(None, "malformed_json", "request line exceeds maximum length")

    try:
        line = raw_line.rstrip(b"\n").decode("utf-8")
    except UnicodeDecodeError:
        return error_response(None, "malformed_json", "request line is not valid UTF-8 JSON")

    request, error = parse_request_line(line)
    if error is not None:
        return error

    assert request is not None
    try:
        return handle_recognize(request)
    except Exception:
        return error_response(request.id, "internal_error", "request failed")


def run_loop() -> None:
    while True:
        raw_line = sys.stdin.buffer.readline(MAX_NDJSON_LINE_BYTES + 1)
        if raw_line == b"":
            return
        if raw_line == b"\n":
            continue
        if len(raw_line) > MAX_NDJSON_LINE_BYTES and not raw_line.endswith(b"\n"):
            _drain_oversized_line()

        _log_diagnostic("request received")
        response = process_request_line(raw_line)
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
