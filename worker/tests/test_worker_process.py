from __future__ import annotations

import io
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from conftest import (
    REAL_OCR_IMAGE,
    REPO_ROOT,
    SAMPLE_IMAGE,
    WORKER_ROOT,
    parse_response_line,
    read_response_line,
    recognize_request,
    validate,
    worker_env,
    write_request,
)
from worker.rapidocr_engine import OcrEngineError

FIXTURE_TEXT = "HELLO UBUNTU"


class _StubEngine:
    def recognize(self, image_path: Path, *, width: int, height: int) -> dict:
        return {
            "image": {"width": width, "height": height},
            "full_text": "stub",
            "regions": [
                {
                    "id": "line-1",
                    "level": "line",
                    "text": "stub",
                    "polygon": [[0, 0], [width, 0], [width, height], [0, height]],
                    "confidence": 1,
                    "reading_order": 0,
                    "ranges": [],
                }
            ],
            "timings_ms": {"total": 0},
        }


def test_eof_exits_cleanly():
    proc = subprocess.run(
        [sys.executable, "-m", "worker"],
        input="",
        cwd=WORKER_ROOT,
        env=worker_env(),
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0
    assert proc.stdout == ""


def test_run_loop_constructs_one_engine_for_multiple_requests(monkeypatch):
    import worker.__main__ as worker_main

    created = 0

    class CountingEngine(_StubEngine):
        def __init__(self):
            nonlocal created
            created += 1

    requests = [
        recognize_request("reuse-1", SAMPLE_IMAGE),
        recognize_request("reuse-2", SAMPLE_IMAGE),
    ]
    input_bytes = "".join(
        json.dumps(request, separators=(",", ":")) + "\n" for request in requests
    ).encode()
    fake_stdin = type("FakeStdin", (), {"buffer": io.BytesIO(input_bytes)})()
    fake_stdout = io.StringIO()

    monkeypatch.setattr(worker_main, "RapidOcrEngine", CountingEngine)
    monkeypatch.setattr(worker_main.sys, "stdin", fake_stdin)
    monkeypatch.setattr(worker_main.sys, "stdout", fake_stdout)

    worker_main.run_loop()

    assert created == 1
    responses = [json.loads(line) for line in fake_stdout.getvalue().splitlines()]
    assert [response["id"] for response in responses] == ["reuse-1", "reuse-2"]


def test_empty_image_returns_typed_no_text_outcome(
    worker_process,
    schema_store,
    schema_registry,
):
    request_id = "req-success-1"
    write_request(worker_process, recognize_request(request_id, SAMPLE_IMAGE))
    line = read_response_line(worker_process)
    response = parse_response_line(line)
    validate(response, schema_store["response_error"], schema_registry)

    assert response["id"] == request_id
    assert response["ok"] is False
    assert response["error"]["code"] == "no_text"


def test_recognize_real_fixture_matches_schema_and_transcript(
    worker_process,
    schema_store,
    schema_registry,
):
    write_request(
        worker_process,
        recognize_request("real-ocr", REAL_OCR_IMAGE),
    )
    response = parse_response_line(read_response_line(worker_process))

    validate(response, schema_store["response_success"], schema_registry)
    assert response["id"] == "real-ocr"
    assert response["result"]["image"] == {"width": 1000, "height": 260}
    assert response["result"]["full_text"] == "HELLO\nUBUNTU"
    assert [region["text"] for region in response["result"]["regions"]] == [
        "HELLO",
        "UBUNTU",
    ]
    for index, region in enumerate(response["result"]["regions"]):
        assert region["reading_order"] == index
        assert 0 <= region["confidence"] <= 1
        assert len(region["polygon"]) == 4
        assert all(0 <= x <= 1000 and 0 <= y <= 260 for x, y in region["polygon"])


def test_malformed_json_returns_typed_error_and_continues(
    worker_process, schema_store, schema_registry
):
    assert worker_process.stdin is not None
    worker_process.stdin.write("{not json\n")
    worker_process.stdin.flush()
    line = read_response_line(worker_process)
    response = parse_response_line(line)
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] is None
    assert response["ok"] is False
    assert response["error"]["code"] == "malformed_json"

    write_request(worker_process, recognize_request("after-malformed", REAL_OCR_IMAGE))
    recovery = parse_response_line(read_response_line(worker_process))
    validate(recovery, schema_store["response_success"], schema_registry)
    assert recovery["id"] == "after-malformed"
    assert recovery["ok"] is True


def test_invalid_utf8_returns_malformed_json_and_continues(
    schema_store, schema_registry
):
    proc = subprocess.Popen(
        [sys.executable, "-m", "worker"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=WORKER_ROOT,
        env=worker_env(),
    )
    assert proc.stdin is not None
    assert proc.stdout is not None
    proc.stdin.write(
        b'{"version":1,"id":"bad-utf8","method":"recognize","params":{"image_path":"\xff"}}\n'
    )
    proc.stdin.flush()

    response = parse_response_line(proc.stdout.readline().decode("utf-8").rstrip("\n"))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] is None
    assert response["error"]["code"] == "malformed_json"
    assert proc.poll() is None

    proc.stdin.write(
        json.dumps(recognize_request("after-utf8", REAL_OCR_IMAGE)).encode("utf-8")
        + b"\n"
    )
    proc.stdin.flush()
    recovery = parse_response_line(proc.stdout.readline().decode("utf-8").rstrip("\n"))
    validate(recovery, schema_store["response_success"], schema_registry)
    assert recovery["id"] == "after-utf8"

    proc.stdin.close()
    proc.stdin = None
    proc.communicate(timeout=5)
    assert proc.returncode == 0


def test_oversized_line_returns_typed_error_and_continues(
    worker_process, schema_store, schema_registry
):
    assert worker_process.stdin is not None
    worker_process.stdin.write(" " * 2_000_000 + "\n")
    worker_process.stdin.flush()
    response = parse_response_line(read_response_line(worker_process))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] is None
    assert response["error"]["code"] == "malformed_json"

    write_request(worker_process, recognize_request("after-oversized", REAL_OCR_IMAGE))
    recovery = parse_response_line(read_response_line(worker_process))
    validate(recovery, schema_store["response_success"], schema_registry)
    assert recovery["id"] == "after-oversized"


def test_invalid_envelope_returns_typed_error(
    worker_process, schema_store, schema_registry
):
    write_request(
        worker_process,
        {
            "version": 2,
            "id": "bad-version",
            "method": "recognize",
            "params": {"image_path": "/x"},
        },
    )
    response = parse_response_line(read_response_line(worker_process))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "bad-version"
    assert response["ok"] is False
    assert response["error"]["code"] == "invalid_envelope"


def test_extra_params_field_returns_invalid_envelope(
    worker_process, schema_store, schema_registry
):
    write_request(
        worker_process,
        {
            "version": 1,
            "id": "extra-param",
            "method": "recognize",
            "params": {"image_path": str(SAMPLE_IMAGE), "extra": True},
        },
    )
    response = parse_response_line(read_response_line(worker_process))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "extra-param"
    assert response["error"]["code"] == "invalid_envelope"


def test_unsupported_method_returns_typed_error(
    worker_process, schema_store, schema_registry
):
    write_request(
        worker_process,
        {
            "version": 1,
            "id": "bad-method",
            "method": "shutdown",
            "params": {"image_path": str(SAMPLE_IMAGE)},
        },
    )
    response = parse_response_line(read_response_line(worker_process))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "bad-method"
    assert response["ok"] is False
    assert response["error"]["code"] == "unsupported_method"


def test_missing_image_returns_image_unreadable(
    worker_process, schema_store, schema_registry
):
    missing = Path("/tmp/kiriglyph-worker-does-not-exist.png")
    write_request(worker_process, recognize_request("missing-image", missing))
    response = parse_response_line(read_response_line(worker_process))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "missing-image"
    assert response["ok"] is False
    assert response["error"]["code"] == "image_unreadable"


def test_unreadable_image_returns_image_unreadable(
    worker_process, schema_store, schema_registry, tmp_path: Path
):
    garbage = tmp_path / "not-an-image.bin"
    garbage.write_bytes(b"not a real image file")
    write_request(worker_process, recognize_request("garbage-image", garbage))
    response = parse_response_line(read_response_line(worker_process))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "garbage-image"
    assert response["error"]["code"] == "image_unreadable"


def test_ocr_failure_returns_typed_error_without_sensitive_details(
    schema_store,
    schema_registry,
):
    from worker import protocol

    class FailingEngine:
        def recognize(self, image_path: Path, *, width: int, height: int) -> dict:
            raise OcrEngineError("recognized private text")

    response = protocol.handle_recognize(
        protocol.RecognizeRequest(id="ocr-failure", image_path=SAMPLE_IMAGE),
        FailingEngine(),
    )

    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "ocr-failure"
    assert response["error"]["code"] == "ocr_failed"
    assert "private" not in response["error"]["message"]


def test_multiple_sequential_requests_have_exact_ndjson_stdout_and_clean_eof(
    schema_store, schema_registry
):
    proc = subprocess.Popen(
        [sys.executable, "-m", "worker"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=WORKER_ROOT,
        env=worker_env(),
        text=True,
        bufsize=1,
    )
    request_ids = ["seq-1", "seq-2", "seq-3"]
    for request_id in request_ids:
        write_request(proc, recognize_request(request_id, REAL_OCR_IMAGE))

    responses = [parse_response_line(read_response_line(proc)) for _ in request_ids]
    for request_id, response in zip(request_ids, responses, strict=True):
        validate(response, schema_store["response_success"], schema_registry)
        assert response["id"] == request_id
        assert response["ok"] is True

    assert proc.stdin is not None
    proc.stdin.close()
    proc.stdin = None
    remaining_stdout, err = proc.communicate(timeout=5)
    assert proc.returncode == 0
    assert remaining_stdout == ""
    assert FIXTURE_TEXT not in err
    assert str(SAMPLE_IMAGE) not in err
    assert all(request_id not in err for request_id in request_ids)


def test_installed_console_entry_point_via_uv(schema_store, schema_registry):
    uv = REPO_ROOT / ".tools" / "uv-bin" / "uv"
    proc = subprocess.run(
        [
            str(uv),
            "run",
            "--locked",
            "kiriglyph-worker",
        ],
        input=json.dumps(recognize_request("console-entry", REAL_OCR_IMAGE)) + "\n",
        cwd=WORKER_ROOT,
        env=worker_env(),
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0
    stdout_lines = proc.stdout.splitlines()
    assert len(stdout_lines) == 1
    response = parse_response_line(stdout_lines[0])
    validate(response, schema_store["response_success"], schema_registry)
    assert response["id"] == "console-entry"
    assert response["result"]["full_text"] == "HELLO\nUBUNTU"
    assert str(REAL_OCR_IMAGE) not in proc.stderr
    assert "HELLO" not in proc.stderr
    assert "UBUNTU" not in proc.stderr


def test_unexpected_request_exception_returns_internal_error_and_continues(
    monkeypatch, schema_store, schema_registry
):
    import worker.__main__ as worker_main
    from worker.__main__ import process_request_line

    calls = 0
    real_handle = worker_main.handle_recognize

    def fail_once(request: Any, engine: Any) -> dict[str, Any]:
        nonlocal calls
        calls += 1
        if calls == 1:
            raise RuntimeError("contains sensitive details")
        return real_handle(request, engine)

    monkeypatch.setattr(worker_main, "handle_recognize", fail_once)

    engine = _StubEngine()
    response = process_request_line(
        json.dumps(recognize_request("raises", SAMPLE_IMAGE)).encode("utf-8"),
        engine,
    )
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "raises"
    assert response["error"]["code"] == "internal_error"
    assert "sensitive" not in response["error"]["message"]

    recovery = process_request_line(
        json.dumps(recognize_request("after-raise", SAMPLE_IMAGE)).encode("utf-8"),
        engine,
    )
    validate(recovery, schema_store["response_success"], schema_registry)
    assert recovery["id"] == "after-raise"
