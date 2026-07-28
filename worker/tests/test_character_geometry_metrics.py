from __future__ import annotations

import pytest

from worker.character_geometry_metrics import (
    AnnotatedCharacter,
    AnnotatedFixture,
    CharacterGeometryScore,
    V0_CHARACTER_GEOMETRY_POLICY,
    evaluate_character_geometry,
    score_character_geometry,
)
from worker.character_geometry_probe import (
    CharacterFragment,
    CharacterGeometryLine,
    CharacterGeometryProbeResult,
    GeometryKind,
    Point,
)


def _polygon(left: float, top: float, right: float, bottom: float):
    return (
        Point(left, top),
        Point(right, top),
        Point(right, bottom),
        Point(left, bottom),
    )


def _fixture(*characters: AnnotatedCharacter) -> AnnotatedFixture:
    return AnnotatedFixture(
        category="worked-example",
        image_width=100,
        image_height=40,
        text="".join(character.text for character in characters),
        line_polygon=_polygon(0, 0, 100, 40),
        characters=characters,
    )


def _actual(*fragments: CharacterFragment) -> CharacterGeometryProbeResult:
    text = "".join(fragment.text for fragment in fragments)
    return CharacterGeometryProbeResult(
        image_width=100,
        image_height=40,
        lines=(
            CharacterGeometryLine(
                id="line-1",
                text=text,
                polygon=_polygon(0, 0, 100, 40),
                confidence=1,
                fragments=fragments,
            ),
        ),
        total_ms=1,
    )


def test_identical_geometry_has_perfect_literal_scores():
    expected = _fixture(
        AnnotatedCharacter(0, 1, "a", _polygon(0, 0, 10, 10)),
    )
    actual = _actual(
        CharacterFragment(
            0,
            1,
            "a",
            _polygon(0, 0, 10, 10),
            GeometryKind.DERIVED_CTC_POLYGON,
            1,
        )
    )

    score = score_character_geometry(expected, actual)

    assert score.transcript_matches is True
    assert score.token_coverage == 1
    assert score.center_hit_rate == 1
    assert score.mean_normalized_corner_error == 0
    assert score.ordering_violations == 0
    assert score.baseline_direction_error_degrees == 0


def test_shifted_geometry_uses_expected_center_and_diagonal():
    expected = _fixture(
        AnnotatedCharacter(0, 1, "a", _polygon(0, 0, 10, 10)),
    )
    actual = _actual(
        CharacterFragment(
            0,
            1,
            "a",
            _polygon(5, 0, 15, 10),
            GeometryKind.DERIVED_CTC_POLYGON,
            1,
        )
    )

    score = score_character_geometry(expected, actual)

    assert score.center_hit_rate == 1
    assert score.mean_normalized_corner_error == pytest.approx(
        5 / (10**2 + 10**2) ** 0.5
    )


def test_missing_and_reordered_tokens_reduce_independent_metrics():
    expected = _fixture(
        AnnotatedCharacter(0, 1, "a", _polygon(0, 0, 10, 10)),
        AnnotatedCharacter(1, 2, "b", _polygon(10, 0, 20, 10)),
    )
    actual = _actual(
        CharacterFragment(
            1,
            2,
            "b",
            _polygon(10, 0, 20, 10),
            GeometryKind.DERIVED_CTC_POLYGON,
            1,
        ),
        CharacterFragment(
            0,
            1,
            "a",
            _polygon(0, 0, 10, 10),
            GeometryKind.DERIVED_CTC_POLYGON,
            1,
        ),
    )

    score = score_character_geometry(expected, actual)

    assert score.transcript_matches is False
    assert score.token_coverage == 1
    assert score.ordering_violations == 1


def test_spatial_order_and_baseline_direction_are_measured():
    expected = _fixture(
        AnnotatedCharacter(0, 1, "a", _polygon(0, 0, 10, 10)),
        AnnotatedCharacter(1, 2, "b", _polygon(10, 0, 20, 10)),
    )
    actual = CharacterGeometryProbeResult(
        image_width=100,
        image_height=40,
        lines=(
            CharacterGeometryLine(
                id="line-1",
                text="ab",
                polygon=(
                    Point(0, 0),
                    Point(0, 40),
                    Point(-10, 40),
                    Point(-10, 0),
                ),
                confidence=1,
                fragments=(
                    CharacterFragment(
                        0,
                        1,
                        "a",
                        _polygon(0, 10, 10, 20),
                        GeometryKind.DERIVED_CTC_POLYGON,
                        1,
                    ),
                    CharacterFragment(
                        1,
                        2,
                        "b",
                        _polygon(0, 0, 10, 10),
                        GeometryKind.DERIVED_CTC_POLYGON,
                        1,
                    ),
                ),
            ),
        ),
        total_ms=1,
    )

    score = score_character_geometry(expected, actual)

    assert score.ordering_violations == 1
    assert score.baseline_direction_error_degrees == pytest.approx(90)


def _score(
    category: str,
    *,
    transcript_matches: bool = True,
    token_coverage: float = 1,
    center_hit_rate: float = 1,
    ordering_violations: int = 0,
    invalid_lines: int = 0,
) -> CharacterGeometryScore:
    return CharacterGeometryScore(
        category=category,
        transcript_matches=transcript_matches,
        token_coverage=token_coverage,
        center_hit_rate=center_hit_rate,
        mean_normalized_corner_error=0,
        ordering_violations=ordering_violations,
        invalid_lines=invalid_lines,
        baseline_direction_error_degrees=0,
    )


def test_v0_policy_keeps_transforms_diagnostic_and_enforces_horizontal_gates():
    scores = (
        _score("proportional"),
        _score("code"),
        _score("punctuation-url"),
        _score("small-text"),
        _score("repeated-spaces", transcript_matches=False),
        _score("rotated", center_hit_rate=0),
        _score("perspective", invalid_lines=1),
    )

    result = evaluate_character_geometry(
        scores,
        whitespace_policy_consistent=True,
    )

    assert result.passed is True
    assert result.failures == ()
    assert result.diagnostic_categories == ("perspective", "rotated")

    failed = evaluate_character_geometry(
        (*scores[:3], _score("small-text", center_hit_rate=0.94), *scores[4:]),
        whitespace_policy_consistent=True,
    )
    assert failed.passed is False
    assert failed.failures == (
        "small-text center-hit rate 0.9400 is below 0.9500",
    )
    assert V0_CHARACTER_GEOMETRY_POLICY.minimum_center_hit_rate == 0.95
