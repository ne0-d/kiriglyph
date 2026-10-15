from __future__ import annotations

import base64
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any, Literal, Protocol


class SegmentationFailureKind(StrEnum):
    CANCELLED = "cancelled"
    TIMEOUT = "timeout"
    MALFORMED_OUTPUT = "malformed_output"
    MODEL_LOAD_FAILED = "model_load_failed"
    MODEL_MISSING = "model_missing"
    PROCESS_DIED = "process_died"
    OUT_OF_MEMORY = "out_of_memory"
    SESSION_CLOSED = "session_closed"


class MaskEncoding(StrEnum):
    ALPHA_PNG_FILE = "alpha_png_file"


class MaskOutcome(StrEnum):
    OK = "ok"
    EMPTY = "empty"
    SUSPECT_FULL_IMAGE = "suspect_full_image"


class SegmentationContractError(Exception):
    def __init__(
        self,
        kind: SegmentationFailureKind,
        message: str,
        *,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.kind = kind
        self.message = message
        self.details = details or {}


@dataclass(frozen=True)
class ImageBytes:
    data: bytes

    def to_json(self) -> dict[str, str]:
        return {"png_base64": base64.b64encode(self.data).decode("ascii")}

    @classmethod
    def from_json(cls, payload: object) -> ImageBytes:
        if not isinstance(payload, dict):
            raise _malformed("image bytes must be an object")
        raw = payload.get("png_base64")
        if not isinstance(raw, str) or not raw:
            raise _malformed("png_base64 must be a non-empty string")
        try:
            return cls(base64.b64decode(raw.encode("ascii"), validate=True))
        except (ValueError, UnicodeEncodeError) as exc:
            raise _malformed("png_base64 is not valid base64") from exc


@dataclass(frozen=True)
class EmbedImageRequest:
    source: Literal["path", "png_bytes"]
    image_path: str | None = None
    png_bytes: ImageBytes | None = None

    @classmethod
    def from_path(cls, image_path: Path | str) -> EmbedImageRequest:
        return cls(source="path", image_path=str(image_path))

    @classmethod
    def from_png_bytes(cls, png_bytes: bytes) -> EmbedImageRequest:
        return cls(source="png_bytes", png_bytes=ImageBytes(png_bytes))

    def to_json(self) -> dict[str, Any]:
        if self.source == "path":
            if not self.image_path:
                raise _malformed("path source requires image_path")
            return {"source": "path", "image_path": self.image_path}
        if self.source == "png_bytes":
            if self.png_bytes is None:
                raise _malformed("png_bytes source requires png_bytes")
            return {"source": "png_bytes", "png_bytes": self.png_bytes.to_json()}
        raise _malformed("unsupported image source")

    @classmethod
    def from_json(cls, payload: object) -> EmbedImageRequest:
        if not isinstance(payload, dict):
            raise _malformed("embed image request must be an object")
        source = payload.get("source")
        if source == "path":
            image_path = payload.get("image_path")
            if not isinstance(image_path, str) or not image_path:
                raise _malformed("image_path must be a non-empty string")
            return cls.from_path(image_path)
        if source == "png_bytes":
            return cls.from_png_bytes(ImageBytes.from_json(payload.get("png_bytes")).data)
        raise _malformed("source must be path or png_bytes")


@dataclass(frozen=True)
class PointPrompt:
    x: float
    y: float
    label: Literal["foreground", "background"] = "foreground"

    def to_json(self) -> dict[str, Any]:
        return {"x": self.x, "y": self.y, "label": self.label}

    @classmethod
    def from_json(cls, payload: object) -> PointPrompt:
        if not isinstance(payload, dict):
            raise _malformed("point prompt must be an object")
        x = _number(payload.get("x"), "point x")
        y = _number(payload.get("y"), "point y")
        label = payload.get("label", "foreground")
        if label not in {"foreground", "background"}:
            raise _malformed("point label must be foreground or background")
        return cls(x=x, y=y, label=label)


@dataclass(frozen=True)
class BoxPrompt:
    x: float
    y: float
    width: float
    height: float

    def to_json(self) -> dict[str, float]:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}

    @classmethod
    def from_json(cls, payload: object) -> BoxPrompt:
        if not isinstance(payload, dict):
            raise _malformed("box prompt must be an object")
        width = _positive_number(payload.get("width"), "box width")
        height = _positive_number(payload.get("height"), "box height")
        return cls(
            x=_number(payload.get("x"), "box x"),
            y=_number(payload.get("y"), "box y"),
            width=width,
            height=height,
        )


@dataclass(frozen=True)
class PolygonPrompt:
    points: tuple[PointPrompt, ...]

    def to_json(self) -> dict[str, Any]:
        return {"points": [point.to_json() for point in self.points]}

    @classmethod
    def from_json(cls, payload: object) -> PolygonPrompt:
        if not isinstance(payload, dict):
            raise _malformed("polygon prompt must be an object")
        raw_points = payload.get("points")
        if not isinstance(raw_points, list) or len(raw_points) < 3:
            raise _malformed("polygon points must contain at least three points")
        points = tuple(PointPrompt.from_json(item) for item in raw_points)
        if any(point.label != "foreground" for point in points):
            raise _malformed("polygon points must be foreground points")
        return cls(points=points)

    def to_box_and_points(self) -> tuple[BoxPrompt, tuple[PointPrompt, ...]]:
        xs = [point.x for point in self.points]
        ys = [point.y for point in self.points]
        left = min(xs)
        top = min(ys)
        right = max(xs)
        bottom = max(ys)
        if right <= left or bottom <= top:
            raise _malformed("polygon prompt must have usable area")
        centroid = PointPrompt(
            x=sum(xs) / len(xs),
            y=sum(ys) / len(ys),
            label="foreground",
        )
        # Deterministic lasso lowering: use the lasso bounds plus three inside
        # samples along its vertex order. The adapter remains model-neutral;
        # model-specific code decides how to encode the resulting box/points.
        stride = max(1, len(self.points) // 3)
        sampled = tuple(self.points[index] for index in range(0, len(self.points), stride))[
            :3
        ]
        return (
            BoxPrompt(x=left, y=top, width=right - left, height=bottom - top),
            (centroid, *sampled),
        )


@dataclass(frozen=True)
class SegmentationPrompt:
    points: tuple[PointPrompt, ...] = ()
    box: BoxPrompt | None = None
    polygon: PolygonPrompt | None = None

    def to_json(self) -> dict[str, Any]:
        return {
            "points": [point.to_json() for point in self.points],
            "box": None if self.box is None else self.box.to_json(),
            "polygon": None if self.polygon is None else self.polygon.to_json(),
        }

    @classmethod
    def from_json(cls, payload: object) -> SegmentationPrompt:
        if not isinstance(payload, dict):
            raise _malformed("segmentation prompt must be an object")
        raw_points = payload.get("points", [])
        if not isinstance(raw_points, list):
            raise _malformed("points must be a list")
        box_payload = payload.get("box")
        polygon_payload = payload.get("polygon")
        return cls(
            points=tuple(PointPrompt.from_json(item) for item in raw_points),
            box=None if box_payload is None else BoxPrompt.from_json(box_payload),
            polygon=None
            if polygon_payload is None
            else PolygonPrompt.from_json(polygon_payload),
        )


@dataclass(frozen=True)
class Rect:
    x: int
    y: int
    width: int
    height: int

    def to_json(self) -> dict[str, int]:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}

    @classmethod
    def from_json(cls, payload: object) -> Rect:
        if not isinstance(payload, dict):
            raise _malformed("bounds must be an object")
        width = _positive_int(payload.get("width"), "bounds width")
        height = _positive_int(payload.get("height"), "bounds height")
        return cls(
            x=_int(payload.get("x"), "bounds x"),
            y=_int(payload.get("y"), "bounds y"),
            width=width,
            height=height,
        )


@dataclass(frozen=True)
class SegmentationTimings:
    load_ms: float | None = None
    embed_ms: float | None = None
    first_mask_ms: float | None = None
    prompt_ms: float | None = None

    def to_json(self) -> dict[str, float]:
        return {
            key: value
            for key, value in {
                "load_ms": self.load_ms,
                "embed_ms": self.embed_ms,
                "first_mask_ms": self.first_mask_ms,
                "prompt_ms": self.prompt_ms,
            }.items()
            if value is not None
        }

    @classmethod
    def from_json(cls, payload: object) -> SegmentationTimings:
        if not isinstance(payload, dict):
            raise _malformed("timings must be an object")
        return cls(
            load_ms=_optional_number(payload.get("load_ms"), "load_ms"),
            embed_ms=_optional_number(payload.get("embed_ms"), "embed_ms"),
            first_mask_ms=_optional_number(payload.get("first_mask_ms"), "first_mask_ms"),
            prompt_ms=_optional_number(payload.get("prompt_ms"), "prompt_ms"),
        )


@dataclass(frozen=True)
class EmbeddedImageHandle:
    handle: str
    image_width: int
    image_height: int
    timings: SegmentationTimings

    def to_json(self) -> dict[str, Any]:
        return {
            "handle": self.handle,
            "image": {"width": self.image_width, "height": self.image_height},
            "timings_ms": self.timings.to_json(),
        }

    @classmethod
    def from_json(cls, payload: object) -> EmbeddedImageHandle:
        if not isinstance(payload, dict):
            raise _malformed("embedded image handle must be an object")
        handle = payload.get("handle")
        image = payload.get("image")
        if not isinstance(handle, str) or not handle:
            raise _malformed("handle must be a non-empty string")
        if not isinstance(image, dict):
            raise _malformed("image must be an object")
        return cls(
            handle=handle,
            image_width=_positive_int(image.get("width"), "image width"),
            image_height=_positive_int(image.get("height"), "image height"),
            timings=SegmentationTimings.from_json(payload.get("timings_ms", {})),
        )


@dataclass(frozen=True)
class MaskReference:
    encoding: MaskEncoding
    path: str
    byte_length: int
    sha256: str

    def to_json(self) -> dict[str, Any]:
        return {
            "encoding": self.encoding.value,
            "path": self.path,
            "byte_length": self.byte_length,
            "sha256": self.sha256,
        }

    @classmethod
    def from_json(cls, payload: object) -> MaskReference:
        if not isinstance(payload, dict):
            raise _malformed("mask reference must be an object")
        encoding = payload.get("encoding")
        if encoding != MaskEncoding.ALPHA_PNG_FILE.value:
            raise _malformed("mask encoding must be alpha_png_file")
        path = payload.get("path")
        sha256 = payload.get("sha256")
        if not isinstance(path, str) or not path:
            raise _malformed("mask path must be a non-empty string")
        if not isinstance(sha256, str) or len(sha256) != 64:
            raise _malformed("mask sha256 must be a hex digest")
        return cls(
            encoding=MaskEncoding.ALPHA_PNG_FILE,
            path=path,
            byte_length=_positive_int(payload.get("byte_length"), "mask byte length"),
            sha256=sha256,
        )


@dataclass(frozen=True)
class EdgeTouches:
    left: bool = False
    top: bool = False
    right: bool = False
    bottom: bool = False

    @property
    def any(self) -> bool:
        return self.left or self.top or self.right or self.bottom

    def to_json(self) -> dict[str, bool]:
        return {
            "left": self.left,
            "top": self.top,
            "right": self.right,
            "bottom": self.bottom,
            "any": self.any,
        }

    @classmethod
    def from_json(cls, payload: object) -> EdgeTouches:
        if not isinstance(payload, dict):
            raise _malformed("touches_edge must be an object")
        return cls(
            left=_bool(payload.get("left"), "touches_edge.left"),
            top=_bool(payload.get("top"), "touches_edge.top"),
            right=_bool(payload.get("right"), "touches_edge.right"),
            bottom=_bool(payload.get("bottom"), "touches_edge.bottom"),
        )


@dataclass(frozen=True)
class ComponentStats:
    count: int
    largest_bounds: Rect | None

    def to_json(self) -> dict[str, Any]:
        return {
            "count": self.count,
            "largest_bounds": None
            if self.largest_bounds is None
            else self.largest_bounds.to_json(),
        }

    @classmethod
    def from_json(cls, payload: object) -> ComponentStats:
        if not isinstance(payload, dict):
            raise _malformed("components must be an object")
        count = _nonnegative_int(payload.get("count"), "components count")
        raw_bounds = payload.get("largest_bounds")
        return cls(
            count=count,
            largest_bounds=None if raw_bounds is None else Rect.from_json(raw_bounds),
        )


@dataclass(frozen=True)
class MaskStats:
    outcome: MaskOutcome
    area_fraction: float
    bounds: Rect | None
    touches_edge: EdgeTouches
    components: ComponentStats

    @property
    def multiple_components(self) -> bool:
        return self.components.count > 1

    def to_json(self) -> dict[str, Any]:
        return {
            "outcome": self.outcome.value,
            "area_fraction": self.area_fraction,
            "bounds": None if self.bounds is None else self.bounds.to_json(),
            "touches_edge": self.touches_edge.to_json(),
            "components": self.components.to_json(),
            "multiple_components": self.multiple_components,
        }

    @classmethod
    def from_json(cls, payload: object) -> MaskStats:
        if not isinstance(payload, dict):
            raise _malformed("mask_stats must be an object")
        raw_outcome = payload.get("outcome")
        try:
            outcome = MaskOutcome(raw_outcome)
        except ValueError as exc:
            raise _malformed("mask_stats outcome is unsupported") from exc
        area_fraction = _optional_unit(payload.get("area_fraction"), "area_fraction")
        if area_fraction is None:
            raise _malformed("area_fraction must be present")
        raw_bounds = payload.get("bounds")
        return cls(
            outcome=outcome,
            area_fraction=area_fraction,
            bounds=None if raw_bounds is None else Rect.from_json(raw_bounds),
            touches_edge=EdgeTouches.from_json(payload.get("touches_edge")),
            components=ComponentStats.from_json(payload.get("components")),
        )


@dataclass(frozen=True)
class SegmentationResult:
    image_width: int
    image_height: int
    mask: MaskReference
    bounds: Rect | None
    mask_stats: MaskStats
    confidence: float | None
    stability_score: float | None
    timings: SegmentationTimings

    def to_json(self) -> dict[str, Any]:
        return {
            "image": {"width": self.image_width, "height": self.image_height},
            "mask": self.mask.to_json(),
            "bounds": None if self.bounds is None else self.bounds.to_json(),
            "mask_stats": self.mask_stats.to_json(),
            "confidence": self.confidence,
            "stability_score": self.stability_score,
            "timings_ms": self.timings.to_json(),
        }

    @classmethod
    def from_json(cls, payload: object) -> SegmentationResult:
        if not isinstance(payload, dict):
            raise _malformed("segmentation result must be an object")
        image = payload.get("image")
        if not isinstance(image, dict):
            raise _malformed("image must be an object")
        confidence = _optional_unit(payload.get("confidence"), "confidence")
        stability = _optional_unit(payload.get("stability_score"), "stability_score")
        return cls(
            image_width=_positive_int(image.get("width"), "image width"),
            image_height=_positive_int(image.get("height"), "image height"),
            mask=MaskReference.from_json(payload.get("mask")),
            bounds=None
            if payload.get("bounds") is None
            else Rect.from_json(payload.get("bounds")),
            mask_stats=MaskStats.from_json(payload.get("mask_stats")),
            confidence=confidence,
            stability_score=stability,
            timings=SegmentationTimings.from_json(payload.get("timings_ms", {})),
        )


class SegmentationAdapter(Protocol):
    def embed_image(self, request: EmbedImageRequest) -> EmbeddedImageHandle: ...

    def prompt(
        self,
        handle: EmbeddedImageHandle,
        prompt: SegmentationPrompt,
    ) -> SegmentationResult: ...

    def close_session(self) -> None: ...


def _malformed(message: str) -> SegmentationContractError:
    return SegmentationContractError(SegmentationFailureKind.MALFORMED_OUTPUT, message)


def _number(value: object, field: str) -> float:
    if type(value) not in {int, float}:
        raise _malformed(f"{field} must be a number")
    return float(value)


def _optional_number(value: object, field: str) -> float | None:
    if value is None:
        return None
    return _number(value, field)


def _optional_unit(value: object, field: str) -> float | None:
    if value is None:
        return None
    number = _number(value, field)
    if not 0 <= number <= 1:
        raise _malformed(f"{field} must be between 0 and 1")
    return number


def _int(value: object, field: str) -> int:
    if type(value) is not int:
        raise _malformed(f"{field} must be an integer")
    return value


def _nonnegative_int(value: object, field: str) -> int:
    integer = _int(value, field)
    if integer < 0:
        raise _malformed(f"{field} must be non-negative")
    return integer


def _positive_int(value: object, field: str) -> int:
    integer = _int(value, field)
    if integer <= 0:
        raise _malformed(f"{field} must be positive")
    return integer


def _positive_number(value: object, field: str) -> float:
    number = _number(value, field)
    if number <= 0:
        raise _malformed(f"{field} must be positive")
    return number


def _bool(value: object, field: str) -> bool:
    if type(value) is not bool:
        raise _malformed(f"{field} must be a boolean")
    return value
