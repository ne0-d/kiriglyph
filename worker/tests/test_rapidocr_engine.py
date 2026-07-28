from __future__ import annotations

import socket
from pathlib import Path
from types import SimpleNamespace

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
        assert "".join(fragment["text"] for fragment in region["ranges"]) == region[
            "text"
        ]
        assert [
            (fragment["start"], fragment["end"])
            for fragment in region["ranges"]
        ] == [
            (offset, offset + 1) for offset in range(len(region["text"]))
        ]
        assert {
            fragment["geometry_kind"] for fragment in region["ranges"]
        } <= {"derived_ctc_polygon", "interpolated_gap"}


def test_invalid_character_geometry_falls_back_only_for_its_line():
    engine = object.__new__(RapidOcrEngine)
    engine._engine = lambda *_args, **_kwargs: SimpleNamespace(
        boxes=[
            [[0, 0], [20, 0], [20, 10], [0, 10]],
            [[0, 20], [20, 20], [20, 30], [0, 30]],
        ],
        txts=["ab", "cd"],
        scores=[1, 1],
        word_results=[
            [
                ("a", 1, [[0, 0], [10, 0], [10, 10], [0, 10]]),
                ("b", 1, [[10, 0], [20, 0], [20, 10], [10, 10]]),
            ],
            [
                ("c", 1, [[-1, 20], [10, 20], [10, 30], [-1, 30]]),
                ("d", 1, [[10, 20], [20, 20], [20, 30], [10, 30]]),
            ],
        ],
    )

    result = engine.recognize(FIXTURE, width=100, height=100)

    assert [len(region["ranges"]) for region in result["regions"]] == [2, 0]
    assert [region["text"] for region in result["regions"]] == ["ab", "cd"]
