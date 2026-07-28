from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

from worker.character_geometry_probe import (
    CharacterFragment,
    CharacterGeometryLine,
    CharacterGeometryProbeResult,
    Point,
    Polygon,
)


@dataclass(frozen=True)
class AnnotatedCharacter:
    start: int
    end: int
    text: str
    polygon: Polygon


@dataclass(frozen=True)
class AnnotatedFixture:
    category: str
    image_width: int
    image_height: int
    text: str
    line_polygon: Polygon
    characters: tuple[AnnotatedCharacter, ...]


@dataclass(frozen=True)
class CharacterGeometryScore:
    category: str
    transcript_matches: bool
    token_coverage: float
    center_hit_rate: float
    mean_normalized_corner_error: float
    ordering_violations: int
    invalid_lines: int
    baseline_direction_error_degrees: float


@dataclass(frozen=True)
class CharacterGeometryPolicy:
    required_horizontal_categories: tuple[str, ...]
    diagnostic_categories: tuple[str, ...]
    minimum_token_coverage: float
    minimum_center_hit_rate: float


@dataclass(frozen=True)
class CharacterGeometryEvaluation:
    passed: bool
    failures: tuple[str, ...]
    diagnostic_categories: tuple[str, ...]


V0_CHARACTER_GEOMETRY_POLICY = CharacterGeometryPolicy(
    required_horizontal_categories=(
        "code",
        "proportional",
        "punctuation-url",
        "small-text",
    ),
    diagnostic_categories=("perspective", "rotated"),
    minimum_token_coverage=0.95,
    minimum_center_hit_rate=0.95,
)


def load_annotated_fixture(path: Path) -> AnnotatedFixture:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return AnnotatedFixture(
        category=str(raw["category"]),
        image_width=int(raw["image"]["width"]),
        image_height=int(raw["image"]["height"]),
        text=str(raw["text"]),
        line_polygon=_polygon(raw["line_polygon"]),
        characters=tuple(
            AnnotatedCharacter(
                start=int(item["start"]),
                end=int(item["end"]),
                text=str(item["text"]),
                polygon=_polygon(item["polygon"]),
            )
            for item in raw["characters"]
        ),
    )


def score_character_geometry(
    expected: AnnotatedFixture,
    actual: CharacterGeometryProbeResult,
) -> CharacterGeometryScore:
    fragments = tuple(
        fragment for line in actual.lines for fragment in line.fragments
    )
    actual_text = "\n".join(line.text for line in actual.lines)
    expected_visual = tuple(
        character for character in expected.characters if not character.text.isspace()
    )
    actual_by_range = {
        (fragment.start, fragment.end, fragment.text): fragment
        for fragment in fragments
        if not fragment.text.isspace()
    }
    matched = [
        (character, actual_by_range.get(_key(character)))
        for character in expected_visual
    ]
    matched = [
        (character, fragment)
        for character, fragment in matched
        if fragment is not None
    ]

    token_coverage = (
        len(matched) / len(expected_visual) if expected_visual else 1.0
    )
    center_hits = [
        _point_in_polygon(_center(character.polygon), fragment.polygon)
        for character, fragment in matched
    ]
    center_hit_rate = (
        sum(center_hits) / len(expected_visual) if expected_visual else 1.0
    )
    errors = [
        _normalized_corner_error(character.polygon, fragment.polygon)
        for character, fragment in matched
    ]
    mean_error = sum(errors) / len(errors) if errors else math.inf
    ordering_violations = sum(
        _line_ordering_violations(line) for line in actual.lines
    )
    baseline_direction_error = (
        _direction_error_degrees(
            expected.line_polygon,
            actual.lines[0].polygon,
        )
        if actual.lines
        else math.inf
    )

    return CharacterGeometryScore(
        category=expected.category,
        transcript_matches=actual_text == expected.text,
        token_coverage=token_coverage,
        center_hit_rate=center_hit_rate,
        mean_normalized_corner_error=mean_error,
        ordering_violations=ordering_violations,
        invalid_lines=sum(line.invalid_reason is not None for line in actual.lines),
        baseline_direction_error_degrees=baseline_direction_error,
    )


def evaluate_character_geometry(
    scores: tuple[CharacterGeometryScore, ...],
    *,
    whitespace_policy_consistent: bool,
    policy: CharacterGeometryPolicy = V0_CHARACTER_GEOMETRY_POLICY,
) -> CharacterGeometryEvaluation:
    scores_by_category = {score.category: score for score in scores}
    failures: list[str] = []
    for category in policy.required_horizontal_categories:
        score = scores_by_category.get(category)
        if score is None:
            failures.append(f"{category} evidence is missing")
            continue
        if not score.transcript_matches:
            failures.append(f"{category} transcript did not match")
        if score.token_coverage < policy.minimum_token_coverage:
            failures.append(
                f"{category} token coverage {score.token_coverage:.4f} is below "
                f"{policy.minimum_token_coverage:.4f}"
            )
        if score.center_hit_rate < policy.minimum_center_hit_rate:
            failures.append(
                f"{category} center-hit rate {score.center_hit_rate:.4f} is below "
                f"{policy.minimum_center_hit_rate:.4f}"
            )
        if score.ordering_violations:
            failures.append(
                f"{category} has {score.ordering_violations} ordering violations"
            )
        if score.invalid_lines:
            failures.append(f"{category} has {score.invalid_lines} invalid lines")
    if not whitespace_policy_consistent:
        failures.append("whitespace range and provenance policy was inconsistent")
    return CharacterGeometryEvaluation(
        passed=not failures,
        failures=tuple(failures),
        diagnostic_categories=policy.diagnostic_categories,
    )


def _key(character: AnnotatedCharacter) -> tuple[int, int, str]:
    return character.start, character.end, character.text


def _line_ordering_violations(line: CharacterGeometryLine) -> int:
    direction_x = line.polygon[1].x - line.polygon[0].x
    direction_y = line.polygon[1].y - line.polygon[0].y
    violations = 0
    for previous, current in zip(
        line.fragments,
        line.fragments[1:],
    ):
        previous_center = _center(previous.polygon)
        current_center = _center(current.polygon)
        previous_projection = (
            previous_center.x * direction_x + previous_center.y * direction_y
        )
        current_projection = (
            current_center.x * direction_x + current_center.y * direction_y
        )
        if (
            current.start < previous.end
            or current_projection < previous_projection - 1e-9
        ):
            violations += 1
    return violations


def _direction_error_degrees(expected: Polygon, actual: Polygon) -> float:
    expected_x = expected[1].x - expected[0].x
    expected_y = expected[1].y - expected[0].y
    actual_x = actual[1].x - actual[0].x
    actual_y = actual[1].y - actual[0].y
    denominator = math.hypot(expected_x, expected_y) * math.hypot(
        actual_x,
        actual_y,
    )
    if denominator == 0:
        return math.inf
    cosine = (expected_x * actual_x + expected_y * actual_y) / denominator
    return math.degrees(math.acos(min(max(cosine, -1), 1)))


def _polygon(raw: list[list[float]]) -> Polygon:
    points = tuple(Point(float(x), float(y)) for x, y in raw)
    if len(points) != 4:
        raise ValueError("annotated polygon must contain four points")
    return points  # type: ignore[return-value]


def _center(polygon: Polygon) -> Point:
    return Point(
        sum(point.x for point in polygon) / len(polygon),
        sum(point.y for point in polygon) / len(polygon),
    )


def _point_in_polygon(point: Point, polygon: Polygon) -> bool:
    signs = []
    for first, second in zip(polygon, (*polygon[1:], polygon[0]), strict=True):
        cross = (second.x - first.x) * (point.y - first.y) - (
            second.y - first.y
        ) * (point.x - first.x)
        if abs(cross) > 1e-9:
            signs.append(cross > 0)
    return not signs or all(sign == signs[0] for sign in signs)


def _normalized_corner_error(expected: Polygon, actual: Polygon) -> float:
    min_x = min(point.x for point in expected)
    max_x = max(point.x for point in expected)
    min_y = min(point.y for point in expected)
    max_y = max(point.y for point in expected)
    diagonal = math.hypot(max_x - min_x, max_y - min_y)
    if diagonal == 0:
        return math.inf
    distances = [
        math.hypot(expected_point.x - actual_point.x, expected_point.y - actual_point.y)
        for expected_point, actual_point in zip(expected, actual, strict=True)
    ]
    return sum(distances) / len(distances) / diagonal
