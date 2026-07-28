from __future__ import annotations

import json
import math
from pathlib import Path

from character_geometry_fixture_factory import build_character_geometry_fixtures


EXPECTED_FIXTURES = {
    "proportional",
    "code",
    "punctuation-url",
    "repeated-spaces",
    "small-text",
    "rotated",
    "perspective",
}


def test_fixture_factory_is_deterministic_and_covers_required_categories(
    tmp_path: Path,
):
    first = tmp_path / "first"
    second = tmp_path / "second"

    build_character_geometry_fixtures(first)
    build_character_geometry_fixtures(second)

    first_files = {
        path.relative_to(first): path.read_bytes()
        for path in first.rglob("*")
        if path.is_file()
    }
    second_files = {
        path.relative_to(second): path.read_bytes()
        for path in second.rglob("*")
        if path.is_file()
    }
    assert first_files == second_files
    assert {path.stem for path in first.glob("*.png")} == EXPECTED_FIXTURES
    assert {path.stem for path in first.glob("*.json")} == EXPECTED_FIXTURES


def test_fixture_annotations_have_valid_ordered_source_geometry(tmp_path: Path):
    build_character_geometry_fixtures(tmp_path)

    for annotation_path in sorted(tmp_path.glob("*.json")):
        annotation = json.loads(annotation_path.read_text(encoding="utf-8"))
        width = annotation["image"]["width"]
        height = annotation["image"]["height"]
        text = annotation["text"]
        characters = annotation["characters"]

        assert width > 0
        assert height > 0
        assert annotation["category"] in EXPECTED_FIXTURES
        assert len(annotation["line_polygon"]) == 4
        assert len(characters) == len(text)
        assert [item["start"] for item in characters] == list(range(len(text)))
        assert [item["end"] for item in characters] == list(
            range(1, len(text) + 1)
        )

        for index, item in enumerate(characters):
            assert item["text"] == text[index]
            assert item["geometry_kind"] == (
                "logical_gap" if item["text"].isspace() else "advance_cell"
            )
            polygon = item["polygon"]
            assert len(polygon) == 4
            for x, y in polygon:
                assert math.isfinite(x)
                assert math.isfinite(y)
                assert 0 <= x <= width
                assert 0 <= y <= height
