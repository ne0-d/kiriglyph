from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image, ImageDraw, ImageFont

Point = tuple[float, float]
Polygon = list[Point]
PolygonTransform = Callable[[Polygon], Polygon]


@dataclass(frozen=True)
class FixtureSpec:
    name: str
    text: str
    font_size: int
    font_kind: str = "proportional"
    transform: str = "none"


SPECS = (
    FixtureSpec("proportional", "Variable width: iii WWW", 34),
    FixtureSpec("code", "result = parse(value_2)", 28, font_kind="monospace"),
    FixtureSpec("punctuation-url", "https://example.org/a?q=1.5", 27),
    FixtureSpec("repeated-spaces", "alpha   beta", 34),
    FixtureSpec("small-text", "Small text 123", 14),
    FixtureSpec("rotated", "Rotated text", 36, transform="rotate"),
    FixtureSpec("perspective", "Perspective text", 36, transform="perspective"),
)

_MONOSPACE_FONT = Path(
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
)


def build_character_geometry_fixtures(output_directory: Path) -> None:
    output_directory.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        image, annotation = _build_fixture(spec)
        image.save(output_directory / f"{spec.name}.png", optimize=False)
        (output_directory / f"{spec.name}.json").write_text(
            json.dumps(annotation, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )


def _build_fixture(spec: FixtureSpec) -> tuple[Image.Image, dict]:
    size = (720, 220)
    origin = (54.0, 76.0)
    font = _load_font(spec)
    image = Image.new("RGB", size, "white")
    draw = ImageDraw.Draw(image)
    draw.text(origin, spec.text, fill="black", font=font, anchor="lt")

    text_box = draw.textbbox(origin, spec.text, font=font, anchor="lt")
    top = float(text_box[1])
    bottom = float(text_box[3])
    characters = []
    for index, character in enumerate(spec.text):
        left = origin[0] + float(font.getlength(spec.text[:index]))
        right = origin[0] + float(font.getlength(spec.text[: index + 1]))
        characters.append(
            {
                "start": index,
                "end": index + 1,
                "text": character,
                "geometry_kind": (
                    "logical_gap" if character.isspace() else "advance_cell"
                ),
                "polygon": _polygon(left, top, right, bottom),
            }
        )

    line_polygon = _polygon(
        float(text_box[0]),
        top,
        float(text_box[2]),
        bottom,
    )
    transform: PolygonTransform = _identity
    transform_metadata: dict[str, object] = {"kind": "none"}

    if spec.transform == "rotate":
        angle = 12.0
        image = image.rotate(
            angle,
            resample=Image.Resampling.BICUBIC,
            expand=False,
            fillcolor="white",
        )
        transform = lambda polygon: _rotate_polygon(
            polygon,
            angle_degrees=angle,
            center=(size[0] / 2, size[1] / 2),
        )
        transform_metadata = {"kind": "rotation", "degrees": angle}
    elif spec.transform == "perspective":
        source = [
            (0.0, 0.0),
            (float(size[0]), 0.0),
            (float(size[0]), float(size[1])),
            (0.0, float(size[1])),
        ]
        destination = [
            (24.0, 30.0),
            (696.0, 10.0),
            (674.0, 210.0),
            (46.0, 188.0),
        ]
        inverse = _homography(destination, source)
        forward = _homography(source, destination)
        image = image.transform(
            size,
            Image.Transform.PERSPECTIVE,
            data=tuple(inverse.flat[:8]),
            resample=Image.Resampling.BICUBIC,
            fillcolor="white",
        )
        transform = lambda polygon: [
            _apply_homography(forward, point) for point in polygon
        ]
        transform_metadata = {
            "kind": "perspective",
            "destination": [_round_point(point) for point in destination],
        }

    transformed_line = [_round_point(point) for point in transform(line_polygon)]
    transformed_characters = [
        {
            **item,
            "polygon": [
                _round_point(point)
                for point in transform(
                    [(float(x), float(y)) for x, y in item["polygon"]]
                )
            ],
        }
        for item in characters
    ]

    return image, {
        "category": spec.name,
        "image": {"width": size[0], "height": size[1]},
        "text": spec.text,
        "line_polygon": transformed_line,
        "characters": transformed_characters,
        "transform": transform_metadata,
    }


def _load_font(spec: FixtureSpec) -> ImageFont.FreeTypeFont:
    if spec.font_kind == "monospace":
        if not _MONOSPACE_FONT.is_file():
            raise RuntimeError(f"required fixture font is missing: {_MONOSPACE_FONT}")
        return ImageFont.truetype(str(_MONOSPACE_FONT), spec.font_size)
    return ImageFont.load_default(size=spec.font_size)


def _polygon(left: float, top: float, right: float, bottom: float) -> Polygon:
    return [(left, top), (right, top), (right, bottom), (left, bottom)]


def _identity(polygon: Polygon) -> Polygon:
    return polygon


def _rotate_polygon(
    polygon: Polygon,
    *,
    angle_degrees: float,
    center: Point,
) -> Polygon:
    angle = math.radians(angle_degrees)
    cosine = math.cos(angle)
    sine = math.sin(angle)
    cx, cy = center
    return [
        (
            cosine * (x - cx) + sine * (y - cy) + cx,
            -sine * (x - cx) + cosine * (y - cy) + cy,
        )
        for x, y in polygon
    ]


def _homography(source: list[Point], destination: list[Point]) -> np.ndarray:
    rows = []
    values = []
    for (x, y), (u, v) in zip(source, destination, strict=True):
        rows.extend(
            [
                [x, y, 1, 0, 0, 0, -u * x, -u * y],
                [0, 0, 0, x, y, 1, -v * x, -v * y],
            ]
        )
        values.extend([u, v])
    coefficients = np.linalg.solve(
        np.asarray(rows, dtype=np.float64),
        np.asarray(values, dtype=np.float64),
    )
    return np.asarray([*coefficients, 1.0], dtype=np.float64).reshape(3, 3)


def _apply_homography(matrix: np.ndarray, point: Point) -> Point:
    projected = matrix @ np.asarray([point[0], point[1], 1.0])
    return (
        float(projected[0] / projected[2]),
        float(projected[1] / projected[2]),
    )


def _round_point(point: Point) -> list[float]:
    return [round(point[0], 4), round(point[1], 4)]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: character_geometry_fixture_factory.py OUTPUT_DIR")
    build_character_geometry_fixtures(Path(sys.argv[1]))
