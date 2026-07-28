from __future__ import annotations

import math
from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from time import perf_counter
from typing import Any, Iterable

from rapidocr import RapidOCR

from worker.image_size import read_image_size


class GeometryKind(StrEnum):
    DERIVED_CTC_POLYGON = "derived_ctc_polygon"
    INTERPOLATED_GAP = "interpolated_gap"


@dataclass(frozen=True)
class Point:
    x: float
    y: float


Polygon = tuple[Point, Point, Point, Point]


@dataclass(frozen=True)
class CharacterFragment:
    start: int
    end: int
    text: str
    polygon: Polygon
    geometry_kind: GeometryKind
    confidence: float | None


@dataclass(frozen=True)
class CharacterGeometryLine:
    id: str
    text: str
    polygon: Polygon
    confidence: float
    fragments: tuple[CharacterFragment, ...]
    invalid_reason: str | None = None


@dataclass(frozen=True)
class CharacterGeometryProbeResult:
    image_width: int
    image_height: int
    lines: tuple[CharacterGeometryLine, ...]
    total_ms: float


@lru_cache(maxsize=1)
def _engine() -> RapidOCR:
    return RapidOCR(params={"Global.log_level": "error"})


def probe_character_geometry(
    image_path: Path,
) -> CharacterGeometryProbeResult:
    width, height = read_image_size(image_path)
    started = perf_counter()
    output = _engine()(
        str(image_path),
        return_word_box=True,
        return_single_char_box=True,
    )
    if (
        output.boxes is None
        or output.txts is None
        or output.scores is None
        or output.word_results is None
    ):
        return CharacterGeometryProbeResult(
            image_width=width,
            image_height=height,
            lines=(),
            total_ms=_elapsed_ms(started),
        )

    lines = []
    for index, (line_box, text, score, character_results) in enumerate(
        zip(
            output.boxes,
            output.txts,
            output.scores,
            output.word_results,
            strict=True,
        )
    ):
        line_polygon = _as_polygon(line_box)
        fragments, invalid_reason = map_character_fragments(
            text=str(text),
            line_polygon=line_polygon,
            character_results=character_results,
            image_width=width,
            image_height=height,
        )
        lines.append(
            CharacterGeometryLine(
                id=f"line-{index + 1}",
                text=str(text),
                polygon=line_polygon,
                confidence=min(max(float(score), 0.0), 1.0),
                fragments=fragments if invalid_reason is None else (),
                invalid_reason=invalid_reason,
            )
        )

    return CharacterGeometryProbeResult(
        image_width=width,
        image_height=height,
        lines=tuple(lines),
        total_ms=_elapsed_ms(started),
    )


def map_character_fragments(
    *,
    text: str,
    line_polygon: Polygon,
    character_results: Iterable[tuple[Any, Any, Any]],
    image_width: int,
    image_height: int,
) -> tuple[tuple[CharacterFragment, ...], str | None]:
    mapped: list[CharacterFragment] = []
    cursor = 0
    previous_polygon: Polygon | None = None

    for raw_token, raw_confidence, raw_polygon in character_results:
        token = str(raw_token)
        if len(token) != 1 or token.isspace():
            return (), "single-character output contained a non-character token"

        polygon = _as_polygon(raw_polygon)
        geometry_error = _validate_polygon(
            polygon,
            image_width=image_width,
            image_height=image_height,
        )
        if geometry_error is not None:
            return (), geometry_error

        position = text.find(token, cursor)
        if position < 0:
            return (), "character output did not match recognized line text"
        gap = text[cursor:position]
        if gap and not gap.isspace():
            return (), "character output skipped non-whitespace text"
        if gap:
            if previous_polygon is None:
                return (), "leading whitespace has no bounded visual geometry"
            whitespace = _interpolate_whitespace(
                start=cursor,
                text=gap,
                left=previous_polygon,
                right=polygon,
            )
            previous_orientation = _signed_area(previous_polygon)
            if any(
                _validate_polygon(
                    fragment.polygon,
                    image_width=image_width,
                    image_height=image_height,
                )
                is not None
                or _signed_area(fragment.polygon) * previous_orientation <= 0
                for fragment in whitespace
            ):
                return (), "interpolated whitespace had no usable visual gap"
            mapped.extend(whitespace)

        confidence = float(raw_confidence)
        if not math.isfinite(confidence):
            return (), "character confidence was not finite"
        mapped.append(
            CharacterFragment(
                start=position,
                end=position + 1,
                text=token,
                polygon=polygon,
                geometry_kind=GeometryKind.DERIVED_CTC_POLYGON,
                confidence=min(max(confidence, 0.0), 1.0),
            )
        )
        cursor = position + 1
        previous_polygon = polygon

    if cursor != len(text):
        return (), "character output did not cover the complete recognized text"
    if "".join(fragment.text for fragment in mapped) != text:
        return (), "mapped character fragments did not reconstruct line text"
    if not _ranges_are_contiguous(mapped):
        return (), "mapped character ranges were not contiguous"
    if _has_excessive_overlap(mapped):
        return (), "adjacent character polygons overlapped excessively"
    if not _inside_line_bounds(mapped, line_polygon):
        return (), "character geometry fell outside its source line"
    return tuple(mapped), None


def _interpolate_whitespace(
    *,
    start: int,
    text: str,
    left: Polygon,
    right: Polygon,
) -> list[CharacterFragment]:
    fragments = []
    count = len(text)
    top_left, top_right = _usable_gap_edge(
        left[1],
        right[0],
        direction_start=left[0],
        direction_end=left[1],
        minimum_width=float(count),
    )
    bottom_left, bottom_right = _usable_gap_edge(
        left[2],
        right[3],
        direction_start=left[3],
        direction_end=left[2],
        minimum_width=float(count),
    )
    for index, character in enumerate(text):
        first = index / count
        second = (index + 1) / count
        polygon = (
            _lerp(top_left, top_right, first),
            _lerp(top_left, top_right, second),
            _lerp(bottom_left, bottom_right, second),
            _lerp(bottom_left, bottom_right, first),
        )
        fragments.append(
            CharacterFragment(
                start=start + index,
                end=start + index + 1,
                text=character,
                polygon=polygon,
                geometry_kind=GeometryKind.INTERPOLATED_GAP,
                confidence=None,
            )
        )
    return fragments


def _usable_gap_edge(
    start: Point,
    end: Point,
    *,
    direction_start: Point,
    direction_end: Point,
    minimum_width: float,
) -> tuple[Point, Point]:
    direction_x = direction_end.x - direction_start.x
    direction_y = direction_end.y - direction_start.y
    length = math.hypot(direction_x, direction_y)
    if length == 0:
        return start, end
    unit_x = direction_x / length
    unit_y = direction_y / length
    projected_gap = (end.x - start.x) * unit_x + (end.y - start.y) * unit_y
    if projected_gap >= minimum_width or projected_gap < -2:
        return start, end
    midpoint = Point(x=(start.x + end.x) / 2, y=(start.y + end.y) / 2)
    half = minimum_width / 2
    return (
        Point(x=midpoint.x - unit_x * half, y=midpoint.y - unit_y * half),
        Point(x=midpoint.x + unit_x * half, y=midpoint.y + unit_y * half),
    )


def _as_polygon(raw_polygon: Any) -> Polygon:
    points = tuple(
        Point(x=float(raw_point[0]), y=float(raw_point[1]))
        for raw_point in raw_polygon
    )
    if len(points) != 4:
        raise ValueError("character geometry polygon must have four points")
    return points  # type: ignore[return-value]


def _validate_polygon(
    polygon: Polygon,
    *,
    image_width: int,
    image_height: int,
) -> str | None:
    if any(
        not math.isfinite(point.x)
        or not math.isfinite(point.y)
        or point.x < 0
        or point.x > image_width
        or point.y < 0
        or point.y > image_height
        for point in polygon
    ):
        return "character geometry was outside the source image"
    if abs(_signed_area(polygon)) < 1:
        return "character geometry polygon had no usable area"
    return None


def _ranges_are_contiguous(fragments: list[CharacterFragment]) -> bool:
    return all(
        fragment.start == index and fragment.end == index + 1
        for index, fragment in enumerate(fragments)
    )


def _has_excessive_overlap(fragments: list[CharacterFragment]) -> bool:
    visual = [
        fragment
        for fragment in fragments
        if fragment.geometry_kind is GeometryKind.DERIVED_CTC_POLYGON
    ]
    return any(
        _polygon_overlap_ratio(first.polygon, second.polygon) > 0.25
        for first, second in zip(visual, visual[1:])
    )


def _polygon_overlap_ratio(first: Polygon, second: Polygon) -> float:
    intersection = _clip_convex_polygon(first, second)
    overlap = abs(_area(intersection))
    smaller = min(abs(_signed_area(first)), abs(_signed_area(second)))
    return overlap / smaller if smaller > 0 else 1.0


def _clip_convex_polygon(subject: Polygon, clip: Polygon) -> list[Point]:
    output = list(subject)
    orientation = 1.0 if _signed_area(clip) >= 0 else -1.0
    for clip_start, clip_end in zip(
        clip,
        (*clip[1:], clip[0]),
        strict=True,
    ):
        input_points = output
        output = []
        if not input_points:
            break
        previous = input_points[-1]
        previous_inside = _inside_edge(
            previous,
            clip_start,
            clip_end,
            orientation,
        )
        for current in input_points:
            current_inside = _inside_edge(
                current,
                clip_start,
                clip_end,
                orientation,
            )
            if current_inside:
                if not previous_inside:
                    output.append(
                        _line_intersection(
                            previous,
                            current,
                            clip_start,
                            clip_end,
                        )
                    )
                output.append(current)
            elif previous_inside:
                output.append(
                    _line_intersection(
                        previous,
                        current,
                        clip_start,
                        clip_end,
                    )
                )
            previous = current
            previous_inside = current_inside
    return output


def _inside_edge(
    point: Point,
    edge_start: Point,
    edge_end: Point,
    orientation: float,
) -> bool:
    cross = (edge_end.x - edge_start.x) * (point.y - edge_start.y) - (
        edge_end.y - edge_start.y
    ) * (point.x - edge_start.x)
    return cross * orientation >= -1e-9


def _line_intersection(
    segment_start: Point,
    segment_end: Point,
    line_start: Point,
    line_end: Point,
) -> Point:
    segment_x = segment_end.x - segment_start.x
    segment_y = segment_end.y - segment_start.y
    line_x = line_end.x - line_start.x
    line_y = line_end.y - line_start.y
    denominator = segment_x * line_y - segment_y * line_x
    if abs(denominator) < 1e-9:
        return segment_end
    offset_x = line_start.x - segment_start.x
    offset_y = line_start.y - segment_start.y
    amount = (offset_x * line_y - offset_y * line_x) / denominator
    return Point(
        x=segment_start.x + amount * segment_x,
        y=segment_start.y + amount * segment_y,
    )


def _area(points: list[Point]) -> float:
    if len(points) < 3:
        return 0.0
    return sum(
        first.x * second.y - second.x * first.y
        for first, second in zip(points, (*points[1:], points[0]), strict=True)
    ) / 2


def _inside_line_bounds(
    fragments: list[CharacterFragment],
    line_polygon: Polygon,
) -> bool:
    min_x = min(point.x for point in line_polygon) - 2
    max_x = max(point.x for point in line_polygon) + 2
    min_y = min(point.y for point in line_polygon) - 2
    max_y = max(point.y for point in line_polygon) + 2
    return all(
        min_x <= point.x <= max_x and min_y <= point.y <= max_y
        for fragment in fragments
        for point in fragment.polygon
    )


def _signed_area(polygon: Polygon) -> float:
    return sum(
        first.x * second.y - second.x * first.y
        for first, second in zip(polygon, (*polygon[1:], polygon[0]), strict=True)
    ) / 2


def _lerp(first: Point, second: Point, amount: float) -> Point:
    return Point(
        x=first.x + (second.x - first.x) * amount,
        y=first.y + (second.y - first.y) * amount,
    )


def _elapsed_ms(started: float) -> float:
    return max((perf_counter() - started) * 1000, 0.0)
