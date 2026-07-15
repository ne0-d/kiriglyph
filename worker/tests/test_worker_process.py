from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from conftest import (
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
from jsonschema.exceptions import ValidationError

MOCK_LINE_TEXT = "Mock recognized text"


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


def test_recognize_success_matches_schema_and_mock_expectations(
    worker_process,
    schema_store,
    schema_registry,
    mock_expectations,
):
    request_id = "req-success-1"
    write_request(worker_process, recognize_request(request_id, SAMPLE_IMAGE))
    line = read_response_line(worker_process)
    response = parse_response_line(line)
    validate(response, schema_store["response_success"], schema_registry)

    assert response["id"] == request_id
    assert response["ok"] is True
    result = response["result"]
    assert result["image"] == {"width": 64, "height": 32}
    assert result["full_text"] == mock_expectations["line_text"]
    assert result["timings_ms"] == mock_expectations["timings_ms"]
    assert len(result["regions"]) == 1
    region = result["regions"][0]
    assert region["id"] == mock_expectations["region_id"]
    assert region["level"] == mock_expectations["region_level"]
    assert region["reading_order"] == mock_expectations["reading_order"]
    assert region["text"] == mock_expectations["line_text"]
    assert region["confidence"] == mock_expectations["confidence"]
    assert region["polygon"] == mock_expectations["line_polygon_for_64x32"]


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

    write_request(worker_process, recognize_request("after-malformed", SAMPLE_IMAGE))
    recovery = parse_response_line(read_response_line(worker_process))
    validate(recovery, schema_store["response_success"], schema_registry)
    assert recovery["id"] == "after-malformed"
    assert recovery["ok"] is True


def test_invalid_utf8_returns_malformed_json_and_continues(schema_store, schema_registry):
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
    proc.stdin.write(b'{"version":1,"id":"bad-utf8","method":"recognize","params":{"image_path":"\xff"}}\n')
    proc.stdin.flush()

    response = parse_response_line(proc.stdout.readline().decode("utf-8").rstrip("\n"))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] is None
    assert response["error"]["code"] == "malformed_json"
    assert proc.poll() is None

    proc.stdin.write(json.dumps(recognize_request("after-utf8", SAMPLE_IMAGE)).encode("utf-8") + b"\n")
    proc.stdin.flush()
    recovery = parse_response_line(proc.stdout.readline().decode("utf-8").rstrip("\n"))
    validate(recovery, schema_store["response_success"], schema_registry)
    assert recovery["id"] == "after-utf8"

    proc.stdin.close()
    proc.stdin = None
    proc.communicate(timeout=5)
    assert proc.returncode == 0


def test_oversized_line_returns_typed_error_and_continues(worker_process, schema_store, schema_registry):
    assert worker_process.stdin is not None
    worker_process.stdin.write(" " * 2_000_000 + "\n")
    worker_process.stdin.flush()
    response = parse_response_line(read_response_line(worker_process))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] is None
    assert response["error"]["code"] == "malformed_json"

    write_request(worker_process, recognize_request("after-oversized", SAMPLE_IMAGE))
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
    missing = Path("/tmp/live-text-worker-does-not-exist.png")
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
        write_request(proc, recognize_request(request_id, SAMPLE_IMAGE))

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
    assert MOCK_LINE_TEXT not in err
    assert str(SAMPLE_IMAGE) not in err
    assert all(request_id not in err for request_id in request_ids)


def test_installed_console_entry_point_via_uv(schema_store, schema_registry):
    uv = REPO_ROOT / ".tools" / "uv-bin" / "uv"
    proc = subprocess.run(
        [
            str(uv),
            "run",
            "--locked",
            "live-text-worker",
        ],
        input=json.dumps(recognize_request("console-entry", SAMPLE_IMAGE)) + "\n",
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
    assert str(SAMPLE_IMAGE) not in proc.stderr
    assert MOCK_LINE_TEXT not in proc.stderr


def test_unexpected_request_exception_returns_internal_error_and_continues(
    monkeypatch, schema_store, schema_registry
):
    from worker.__main__ import process_request_line
    import worker.__main__ as worker_main

    calls = 0
    real_handle = worker_main.handle_recognize

    def fail_once(request: Any) -> dict[str, Any]:
        nonlocal calls
        calls += 1
        if calls == 1:
            raise RuntimeError("contains sensitive details")
        return real_handle(request)

    monkeypatch.setattr(worker_main, "handle_recognize", fail_once)

    response = process_request_line(json.dumps(recognize_request("raises", SAMPLE_IMAGE)).encode("utf-8"))
    validate(response, schema_store["response_error"], schema_registry)
    assert response["id"] == "raises"
    assert response["error"]["code"] == "internal_error"
    assert "sensitive" not in response["error"]["message"]

    recovery = process_request_line(json.dumps(recognize_request("after-raise", SAMPLE_IMAGE)).encode("utf-8"))
    validate(recovery, schema_store["response_success"], schema_registry)
    assert recovery["id"] == "after-raise"
