from __future__ import annotations

import hashlib
from pathlib import Path

import pytest
from PIL import Image

from worker.segmentation_contract import (
    BoxPrompt,
    ComponentStats,
    EdgeTouches,
    EmbedImageRequest,
    EmbeddedImageHandle,
    MaskEncoding,
    MaskOutcome,
    MaskReference,
    MaskStats,
    PointPrompt,
    PolygonPrompt,
    Rect,
    SegmentationContractError,
    SegmentationFailureKind,
    SegmentationPrompt,
    SegmentationResult,
    SegmentationTimings,
)


class FakeSegmentationAdapter:
    def __init__(
        self,
        tmp_path: Path,
        *,
        cancel: bool = False,
        timeout: bool = False,
    ) -> None:
        self._tmp_path = tmp_path
        self._handles: dict[str, tuple[int, int]] = {}
        self._next_id = 0
        self._closed = False
        self._cancel = cancel
        self._timeout = timeout

    @property
    def retained_handle_count(self) -> int:
        return len(self._handles)

    def embed_image(self, request: EmbedImageRequest) -> EmbeddedImageHandle:
        if self._cancel:
            raise SegmentationContractError(
                SegmentationFailureKind.CANCELLED,
                "segmentation request was cancelled",
            )
        if self._timeout:
            raise SegmentationContractError(
                SegmentationFailureKind.TIMEOUT,
                "segmentation request timed out",
            )
        if self._closed:
            raise SegmentationContractError(
                SegmentationFailureKind.PROCESS_DIED,
                "segmentation session is closed",
            )

        if request.source == "path":
            assert request.image_path is not None
            with Image.open(request.image_path) as image:
                width, height = image.size
        else:
            width, height = 8, 8

        self._next_id += 1
        handle = f"fake-{self._next_id}"
        self._handles[handle] = (width, height)
        return EmbeddedImageHandle(
            handle=handle,
            image_width=width,
            image_height=height,
            timings=SegmentationTimings(load_ms=1, embed_ms=2),
        )

    def prompt(
        self,
        handle: EmbeddedImageHandle,
        prompt: SegmentationPrompt,
    ) -> SegmentationResult:
        if self._closed or handle.handle not in self._handles:
            raise SegmentationContractError(
                SegmentationFailureKind.PROCESS_DIED,
                "embedding handle is no longer valid",
            )
        width, height = self._handles[handle.handle]
        mask_path = self._tmp_path / "mask.png"
        Image.new("L", (width, height), 255).save(mask_path)
        data = mask_path.read_bytes()
        return SegmentationResult(
            image_width=width,
            image_height=height,
            mask=MaskReference(
                encoding=MaskEncoding.ALPHA_PNG_FILE,
                path=str(mask_path),
                byte_length=len(data),
                sha256=hashlib.sha256(data).hexdigest(),
            ),
            bounds=Rect(x=0, y=0, width=width, height=height),
            mask_stats=MaskStats(
                outcome=MaskOutcome.SUSPECT_FULL_IMAGE,
                area_fraction=1,
                bounds=Rect(x=0, y=0, width=width, height=height),
                touches_edge=EdgeTouches(left=True, top=True, right=True, bottom=True),
                components=ComponentStats(
                    count=1,
                    largest_bounds=Rect(x=0, y=0, width=width, height=height),
                ),
            ),
            confidence=0.75,
            stability_score=0.8,
            timings=SegmentationTimings(first_mask_ms=3, prompt_ms=4),
        )

    def close_session(self) -> None:
        self._closed = True
        self._handles.clear()


def test_segmentation_result_round_trip_serialization(tmp_path: Path):
    adapter = FakeSegmentationAdapter(tmp_path)
    image_path = tmp_path / "image.png"
    Image.new("RGB", (12, 10), "white").save(image_path)

    handle = adapter.embed_image(EmbedImageRequest.from_path(image_path))
    prompt = SegmentationPrompt(
        points=(PointPrompt(x=6, y=5), PointPrompt(x=0, y=0, label="background")),
        box=BoxPrompt(x=2, y=1, width=8, height=8),
    )
    result = adapter.prompt(handle, prompt)

    assert EmbedImageRequest.from_json(EmbedImageRequest.from_path(image_path).to_json())
    assert SegmentationPrompt.from_json(prompt.to_json()) == prompt
    assert EmbeddedImageHandle.from_json(handle.to_json()) == handle
    assert SegmentationResult.from_json(result.to_json()) == result


def test_segmentation_result_rejects_malformed_output():
    payload = {
        "image": {"width": 10, "height": 10},
        "mask": {
            "encoding": "inline_bytes",
            "path": "/tmp/mask.png",
            "byte_length": 1,
            "sha256": "0" * 64,
        },
        "bounds": {"x": 0, "y": 0, "width": 10, "height": 10},
        "mask_stats": {
            "outcome": "ok",
            "area_fraction": 0.5,
            "bounds": {"x": 0, "y": 0, "width": 10, "height": 10},
            "touches_edge": {
                "left": False,
                "top": False,
                "right": False,
                "bottom": False,
                "any": False,
            },
            "components": {
                "count": 1,
                "largest_bounds": {"x": 0, "y": 0, "width": 10, "height": 10},
            },
            "multiple_components": False,
        },
        "confidence": 1.5,
        "stability_score": 0.5,
        "timings_ms": {},
    }

    with pytest.raises(SegmentationContractError) as raised:
        SegmentationResult.from_json(payload)

    assert raised.value.kind == SegmentationFailureKind.MALFORMED_OUTPUT


def test_fake_adapter_discards_embeddings_after_session_close(tmp_path: Path):
    adapter = FakeSegmentationAdapter(tmp_path)
    image_path = tmp_path / "image.png"
    Image.new("RGB", (5, 4), "white").save(image_path)
    handle = adapter.embed_image(EmbedImageRequest.from_path(image_path))

    assert adapter.retained_handle_count == 1
    adapter.close_session()

    assert adapter.retained_handle_count == 0
    with pytest.raises(SegmentationContractError) as raised:
        adapter.prompt(handle, SegmentationPrompt(points=(PointPrompt(1, 1),)))
    assert raised.value.kind == SegmentationFailureKind.PROCESS_DIED


@pytest.mark.parametrize(
    ("flag", "kind"),
    [
        ("cancel", SegmentationFailureKind.CANCELLED),
        ("timeout", SegmentationFailureKind.TIMEOUT),
    ],
)
def test_fake_adapter_cancellation_and_timeout(
    tmp_path: Path,
    flag: str,
    kind: SegmentationFailureKind,
):
    adapter = FakeSegmentationAdapter(tmp_path, **{flag: True})

    with pytest.raises(SegmentationContractError) as raised:
        adapter.embed_image(EmbedImageRequest.from_png_bytes(b"\x89PNG\r\n\x1a\n"))

    assert raised.value.kind == kind


def test_polygon_prompt_lowers_to_box_and_inside_points():
    polygon = PolygonPrompt(
        points=(
            PointPrompt(2, 1),
            PointPrompt(8, 1),
            PointPrompt(8, 7),
            PointPrompt(2, 7),
        )
    )

    box, points = polygon.to_box_and_points()

    assert box == BoxPrompt(x=2, y=1, width=6, height=6)
    assert points[0] == PointPrompt(x=5, y=4)
    assert len(points) == 4
