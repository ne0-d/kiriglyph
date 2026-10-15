from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np
import pytest
from PIL import Image

from worker.efficient_sam_adapter import EfficientSamTiAdapter
from worker.segmentation_contract import (
    ComponentStats,
    EdgeTouches,
    EmbedImageRequest,
    EmbeddedImageHandle,
    MaskEncoding,
    MaskOutcome,
    MaskReference,
    MaskStats,
    PointPrompt,
    Rect,
    SegmentationContractError,
    SegmentationFailureKind,
    SegmentationPrompt,
    SegmentationResult,
    SegmentationTimings,
)
from worker.segmentation_models import model_paths
from worker.segmentation_protocol import encode_response
from worker.segmentation_worker import SegmentationWorker, process_request_line


def _request(request_id: str, method: str, params: dict[str, Any]) -> bytes:
    return (
        json.dumps(
            {"version": 1, "id": request_id, "method": method, "params": params},
            separators=(",", ":"),
        )
        + "\n"
    ).encode()


class _FakeAdapter:
    def __init__(self, tmp_path: Path, *, delay: float = 0) -> None:
        self.tmp_path = tmp_path
        self.delay = delay
        self.closed = False

    def embed_image(self, request: EmbedImageRequest) -> EmbeddedImageHandle:
        if self.delay:
            time.sleep(self.delay)
        if self.closed:
            raise SegmentationContractError(
                SegmentationFailureKind.SESSION_CLOSED,
                "session is closed",
            )
        return EmbeddedImageHandle(
            handle="fake-handle",
            image_width=8,
            image_height=6,
            timings=SegmentationTimings(load_ms=1, embed_ms=2),
        )

    def prompt(
        self,
        handle: EmbeddedImageHandle,
        prompt: SegmentationPrompt,
    ) -> SegmentationResult:
        mask_path = self.tmp_path / "mask.png"
        Image.new("L", (8, 6), 255).save(mask_path)
        data = mask_path.read_bytes()
        stats = MaskStats(
            outcome=MaskOutcome.SUSPECT_FULL_IMAGE,
            area_fraction=1,
            bounds=Rect(0, 0, 8, 6),
            touches_edge=EdgeTouches(True, True, True, True),
            components=ComponentStats(1, Rect(0, 0, 8, 6)),
        )
        return SegmentationResult(
            image_width=8,
            image_height=6,
            mask=MaskReference(
                encoding=MaskEncoding.ALPHA_PNG_FILE,
                path=str(mask_path),
                byte_length=len(data),
                sha256="0" * 64,
            ),
            bounds=stats.bounds,
            mask_stats=stats,
            confidence=0.7,
            stability_score=None,
            timings=SegmentationTimings(prompt_ms=3),
        )

    def close_session(self) -> None:
        self.closed = True


def _read_stdout(capture: io.StringIO, expected_lines: int, timeout: float = 1) -> list[dict]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        lines = capture.getvalue().splitlines()
        if len(lines) >= expected_lines:
            return [json.loads(line) for line in lines]
        time.sleep(0.01)
    raise AssertionError(f"timed out waiting for {expected_lines} response lines")


def test_embed_and_prompt_round_trip(monkeypatch, tmp_path: Path):
    capture = io.StringIO()
    monkeypatch.setattr(sys, "stdout", capture)
    worker = SegmentationWorker(lambda: _FakeAdapter(tmp_path))
    try:
        process_request_line(
            _request("embed-1", "embed", EmbedImageRequest.from_path("/tmp/a.png").to_json()),
            worker,
        )
        embed = _read_stdout(capture, 1)[0]
        handle = embed["result"]

        process_request_line(
            _request(
                "prompt-1",
                "prompt",
                {
                    "handle": handle,
                    "prompt": SegmentationPrompt(
                        points=(PointPrompt(4, 3),),
                    ).to_json(),
                },
            ),
            worker,
        )
        prompt = _read_stdout(capture, 2)[1]
    finally:
        worker.shutdown()

    assert embed["ok"] is True
    assert prompt["ok"] is True
    assert prompt["result"]["mask_stats"]["outcome"] == "suspect_full_image"


def test_malformed_request_returns_typed_failure(monkeypatch):
    capture = io.StringIO()
    monkeypatch.setattr(sys, "stdout", capture)
    worker = SegmentationWorker(lambda: _FakeAdapter(Path("/tmp")))
    try:
        process_request_line(b"{not-json\n", worker)
    finally:
        worker.shutdown()

    response = json.loads(capture.getvalue())
    assert response["ok"] is False
    assert response["error"]["code"] == "malformed_json"


def test_model_missing_reports_install_command():
    proc = subprocess.run(
        [sys.executable, "-m", "worker.segmentation_worker"],
        input=json.dumps(
            {
                "version": 1,
                "id": "embed-missing",
                "method": "embed",
                "params": {"source": "path", "image_path": "/tmp/nope.png"},
            },
            separators=(",", ":"),
        )
        + "\n",
        cwd=Path(__file__).resolve().parents[1],
        env={**os.environ, "PYTHONPATH": "src", "KIRIGLYPH_MODELS_DIR": "/tmp/kiriglyph-missing-models"},
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )

    response = json.loads(proc.stdout.splitlines()[0])
    assert response["ok"] is False
    assert response["error"]["code"] == "model_missing"
    assert response["error"]["details"]["command"] == "kiriglyph-fetch-models"


def test_session_closed_after_close(monkeypatch, tmp_path: Path):
    capture = io.StringIO()
    monkeypatch.setattr(sys, "stdout", capture)
    worker = SegmentationWorker(lambda: _FakeAdapter(tmp_path))
    try:
        keep_running = process_request_line(_request("close-1", "close", {}), worker)
        process_request_line(
            _request("embed-after-close", "embed", EmbedImageRequest.from_path("/tmp/a.png").to_json()),
            worker,
        )
    finally:
        worker.shutdown()

    responses = _read_stdout(capture, 2)
    assert keep_running is False
    assert responses[1]["error"]["code"] == "session_closed"


def test_cancel_discards_delayed_result(monkeypatch, tmp_path: Path):
    capture = io.StringIO()
    monkeypatch.setattr(sys, "stdout", capture)
    worker = SegmentationWorker(lambda: _FakeAdapter(tmp_path, delay=0.2))
    try:
        process_request_line(
            _request("embed-slow", "embed", EmbedImageRequest.from_path("/tmp/a.png").to_json()),
            worker,
        )
        process_request_line(
            _request("cancel-1", "cancel", {"request_id": "embed-slow"}),
            worker,
        )
        responses = _read_stdout(capture, 2)
    finally:
        worker.shutdown()

    assert responses[0]["id"] == "cancel-1"
    assert responses[0]["ok"] is True
    assert responses[1]["id"] == "embed-slow"
    assert responses[1]["error"]["code"] == "cancelled"


def _real_models_available() -> bool:
    return all(path.exists() for path in model_paths().values())


@pytest.mark.skipif(not _real_models_available(), reason="EfficientSAM-Ti files are not installed")
def test_real_efficient_sam_adapter_fixture(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    fixture = (
        Path(__file__).resolve().parents[1]
        / "benchmarks"
        / "segmentation"
        / "fixtures"
        / "person.png"
    )
    adapter = EfficientSamTiAdapter(mask_store=None, threads=2)
    try:
        handle = adapter.embed_image(EmbedImageRequest.from_path(fixture))
        result = adapter.prompt(handle, SegmentationPrompt(points=(PointPrompt(320, 170),)))
    finally:
        adapter.close_session()

    assert result.mask_stats.outcome in {MaskOutcome.OK, MaskOutcome.SUSPECT_FULL_IMAGE}
    assert result.mask.byte_length > 0
    assert result.timings.embed_ms is not None
    assert result.timings.prompt_ms is not None
    assert np.isfinite(result.timings.prompt_ms)
