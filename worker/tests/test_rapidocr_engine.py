from __future__ import annotations

import socket
from pathlib import Path

from worker.rapidocr_engine import RapidOcrEngine

FIXTURE = (
    Path(__file__).resolve().parents[2]
    / "fixtures"
    / "worker"
    / "images"
    / "hello-ubuntu.png"
)


def test_real_fixture_returns_ordered_engine_neutral_lines_without_network(
    monkeypatch,
):
    def reject_network(*_args, **_kwargs):
        raise AssertionError("OCR attempted to open a network socket")

    monkeypatch.setattr(socket.socket, "connect", reject_network)
    result = RapidOcrEngine().recognize(FIXTURE, width=1000, height=260)

    assert result["image"] == {"width": 1000, "height": 260}
    assert result["full_text"] == "HELLO\nUBUNTU"
    assert result["timings_ms"]["total"] >= 0
    assert [region["text"] for region in result["regions"]] == ["HELLO", "UBUNTU"]

    for index, region in enumerate(result["regions"], start=1):
        assert region["id"] == f"line-{index}"
        assert region["level"] == "line"
        assert region["reading_order"] == index - 1
        assert 0 <= region["confidence"] <= 1
        assert len(region["polygon"]) == 4
        assert all(0 <= x <= 1000 and 0 <= y <= 260 for x, y in region["polygon"])
