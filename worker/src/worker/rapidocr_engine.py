from __future__ import annotations

from pathlib import Path
from time import perf_counter
from typing import Any, Protocol

from rapidocr import RapidOCR


class OcrEngineError(Exception):
    """A failure reported by the third-party OCR runtime."""


class OcrEngine(Protocol):
    def recognize(
        self, image_path: Path, *, width: int, height: int
    ) -> dict[str, Any]: ...


class RapidOcrEngine:
    """Adapt RapidOCR output to the engine-neutral worker result contract."""

    def __init__(self) -> None:
        self._engine = RapidOCR(params={"Global.log_level": "error"})

    def recognize(self, image_path: Path, *, width: int, height: int) -> dict[str, Any]:
        started = perf_counter()
        try:
            output = self._engine(str(image_path))
        except Exception as error:
            raise OcrEngineError("RapidOCR failed") from error

        boxes = output.boxes
        texts = output.txts
        scores = output.scores
        if boxes is None or texts is None or scores is None:
            return _result(width, height, [], elapsed_ms=_elapsed_ms(started))

        regions: list[dict[str, Any]] = []
        for index, (box, text, score) in enumerate(
            zip(boxes, texts, scores, strict=True)
        ):
            polygon = [
                [
                    min(max(float(point[0]), 0.0), float(width)),
                    min(max(float(point[1]), 0.0), float(height)),
                ]
                for point in box
            ]
            regions.append(
                {
                    "id": f"line-{index + 1}",
                    "level": "line",
                    "text": str(text),
                    "polygon": polygon,
                    "confidence": min(max(float(score), 0.0), 1.0),
                    "reading_order": index,
                }
            )

        return _result(width, height, regions, elapsed_ms=_elapsed_ms(started))


def _elapsed_ms(started: float) -> float:
    return max((perf_counter() - started) * 1000, 0.0)


def _result(
    width: int,
    height: int,
    regions: list[dict[str, Any]],
    *,
    elapsed_ms: float,
) -> dict[str, Any]:
    return {
        "image": {"width": width, "height": height},
        "full_text": "\n".join(region["text"] for region in regions),
        "regions": regions,
        "timings_ms": {"total": elapsed_ms},
    }
