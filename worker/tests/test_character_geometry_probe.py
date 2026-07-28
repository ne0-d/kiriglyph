from __future__ import annotations

import socket
from pathlib import Path

import pytest

from worker.character_geometry_probe import (
    GeometryKind,
    Point,
    map_character_fragments,
    probe_character_geometry,
)

FIXTURES = (
    Path(__file__).resolve().parents[2]
    / "fixtures"
    / "worker"
    / "character-geometry"
)


@pytest.mark.parametrize(
    ("fixture_name", "expected_text"),
    [
        ("proportional", "Variable width: iii WWW"),
        ("code", "result = parse(value_2)"),
        ("punctuation-url", "https://example.org/a?q=1.5"),
    ],
)
def test_probe_emits_ordered_ranges_for_recognized_text_without_network(
    monkeypatch,
    fixture_name: str,
    expected_text: str,
):
    def reject_network(*_args, **_kwargs):
        raise AssertionError("character geometry probe attempted network access")

    monkeypatch.setattr(socket.socket, "connect", reject_network)

    result = probe_character_geometry(FIXTURES / f"{fixture_name}.png")

    assert len(result.lines) == 1
    line = result.lines[0]
    assert line.text == expected_text
    assert line.invalid_reason is None
    assert "".join(fragment.text for fragment in line.fragments) == expected_text
    assert [
        (fragment.start, fragment.end)
        for fragment in line.fragments
    ] == [
        (index, index + 1) for index in range(len(expected_text))
    ]
    assert all(
        fragment.geometry_kind is GeometryKind.DERIVED_CTC_POLYGON
        for fragment in line.fragments
        if not fragment.text.isspace()
    )


def test_probe_represents_recognized_whitespace_as_an_interpolated_gap():
    result = probe_character_geometry(FIXTURES / "repeated-spaces.png")

    line = result.lines[0]
    assert line.text == "alpha beta"
    spaces = [fragment for fragment in line.fragments if fragment.text.isspace()]
    assert len(spaces) == 1
    assert spaces[0].geometry_kind is GeometryKind.INTERPOLATED_GAP
    assert len(spaces[0].polygon) == 4


def test_rotated_fixture_is_not_rejected_by_axis_aligned_overlap():
    result = probe_character_geometry(FIXTURES / "rotated.png")

    line = result.lines[0]
    assert line.text == "Rotated text"
    assert line.invalid_reason is None
    assert "".join(fragment.text for fragment in line.fragments) == line.text


def test_touching_character_boxes_get_a_minimal_valid_whitespace_gap():
    fragments, invalid_reason = map_character_fragments(
        text="a b",
        line_polygon=(
            Point(0, 0),
            Point(20, 0),
            Point(20, 10),
            Point(0, 10),
        ),
        character_results=[
            ("a", 1, [[0, 0], [10, 0], [10, 10], [0, 10]]),
            ("b", 1, [[10, 0], [20, 0], [20, 10], [10, 10]]),
        ],
        image_width=20,
        image_height=10,
    )

    assert invalid_reason is None
    assert "".join(fragment.text for fragment in fragments) == "a b"
    whitespace = fragments[1]
    assert whitespace.geometry_kind is GeometryKind.INTERPOLATED_GAP
    assert whitespace.polygon[1].x - whitespace.polygon[0].x == pytest.approx(1)


@pytest.mark.parametrize(
    ("text", "character_results", "reason"),
    [
        (
            "a",
            [("a", 0.9, [[-1, 0], [10, 0], [10, 10], [-1, 10]])],
            "outside the source image",
        ),
        (
            "a",
            [("b", 0.9, [[0, 0], [10, 0], [10, 10], [0, 10]])],
            "did not match recognized line text",
        ),
        (
            "a",
            [("a", 0.9, [[0, 0], [0, 0], [0, 0], [0, 0]])],
            "no usable area",
        ),
        (
            "ab",
            [
                ("a", 0.9, [[0, 0], [10, 0], [10, 10], [0, 10]]),
                ("b", 0.9, [[5, 0], [15, 0], [15, 10], [5, 10]]),
            ],
            "overlapped",
        ),
    ],
)
def test_invalid_character_geometry_disables_only_that_line(
    text,
    character_results,
    reason,
):
    fragments, invalid_reason = map_character_fragments(
        text=text,
        line_polygon=(
            Point(0, 0),
            Point(100, 0),
            Point(100, 20),
            Point(0, 20),
        ),
        character_results=character_results,
        image_width=100,
        image_height=20,
    )

    assert fragments == ()
    assert reason in invalid_reason
