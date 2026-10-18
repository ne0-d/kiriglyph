"""Write contracts/v1/golden NDJSON from the live worker protocol encoders.

Run from the repository root:

    PYTHONPATH=src worker/.venv/bin/python worker/tests/regenerate_golden.py

The script puts worker/src on sys.path itself, so that command works even
though PYTHONPATH=src is the worker-directory form of the same variable.
"""

from __future__ import annotations

import hashlib
import struct
import sys
import tempfile
import zlib
from pathlib import Path

_SRC = Path(__file__).resolve().parents[1] / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from PIL import Image, ImageDraw  # noqa: E402
import qrcode  # noqa: E402

from worker.barcode_decoder import decode_barcodes  # noqa: E402
from worker.efficient_sam_adapter import EfficientSamTiAdapter  # noqa: E402
from worker.protocol import (  # noqa: E402
    ErrorCode,
    RecognizeRequest,
    encode_response,
    handle_decode_codes,
    handle_recognize,
)
from worker.rapidocr_engine import OcrEngineError, RapidOcrEngine  # noqa: E402
from worker.segmentation_contract import (  # noqa: E402
    ComponentStats,
    EdgeTouches,
    EmbeddedImageHandle,
    MaskEncoding,
    MaskOutcome,
    MaskReference,
    MaskStats,
    Rect,
    SegmentationContractError,
    SegmentationResult,
    SegmentationTimings,
)
from worker.segmentation_protocol import (  # noqa: E402
    encode_response as encode_segmentation_response,
)
from worker.segmentation_protocol import (  # noqa: E402
    error_from_contract,
    success_response as segmentation_success_response,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_DIR = REPO_ROOT / "contracts" / "v1" / "golden"
MASK_PNG_NAME = "prompt-ok.png"
MASK_RELATIVE_PATH = f"contracts/v1/golden/masks/{MASK_PNG_NAME}"
# The recognize clock is not part of the contract. Pin it so a fresh run
# matches the checked-in line.
PINNED_RECOGNIZE_TOTAL_MS = 0.0


def mask_png_bytes() -> bytes:
    """1x1 opaque PNG with no timestamp chunk, so the digest stays fixed."""
    return _png(1, 1, b"\x00\x00\x00\xff")


def golden_lines() -> dict[str, str]:
    """Filename to one NDJSON line, including the trailing newline."""
    with tempfile.TemporaryDirectory(prefix="kiriglyph-golden-") as raw:
        root = Path(raw)
        text_image = root / "text.png"
        blank_image = root / "blank.png"
        qr_image = root / "qr.png"
        _write_text_image(text_image, "Hi")
        _write_blank_image(blank_image)
        _write_qr_image(qr_image, "https://example.com/local")
        lines = {
            "recognize-ok.ndjson": _recognize_ok(text_image),
            "recognize-no-text.ndjson": _recognize_no_text(blank_image),
            "recognize-image-unreadable.ndjson": _recognize_image_unreadable(),
            "recognize-ocr-failed.ndjson": _recognize_ocr_failed(blank_image),
            "decode-codes-ok.ndjson": _decode_codes_ok(qr_image),
            "decode-codes-empty.ndjson": _decode_codes_empty(blank_image),
            "segmentation-embed-ok.ndjson": _segmentation_embed_ok(),
            "segmentation-prompt-ok.ndjson": _segmentation_prompt_ok(),
            "segmentation-model-missing.ndjson": _segmentation_model_missing(
                root / "missing-models"
            ),
        }
    for name, line in lines.items():
        if not line.endswith("\n") or "\n" in line[:-1]:
            raise RuntimeError(f"{name} must be a single NDJSON line")
    return lines


def write_goldens() -> None:
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
    mask_dir = GOLDEN_DIR / "masks"
    mask_dir.mkdir(parents=True, exist_ok=True)
    (mask_dir / MASK_PNG_NAME).write_bytes(mask_png_bytes())
    for name, line in golden_lines().items():
        (GOLDEN_DIR / name).write_text(line, encoding="utf-8")


def _recognize_ok(image_path: Path) -> str:
    response = handle_recognize(
        RecognizeRequest(id="recognize-ok", image_path=image_path),
        RapidOcrEngine(),
    )
    if response.get("ok") is not True or not response["result"]["regions"]:
        raise RuntimeError("recognize ok golden did not contain regions")
    response["result"]["timings_ms"]["total"] = PINNED_RECOGNIZE_TOTAL_MS
    return _line(encode_response(response))


def _recognize_no_text(image_path: Path) -> str:
    response = handle_recognize(
        RecognizeRequest(id="recognize-no-text", image_path=image_path),
        RapidOcrEngine(),
    )
    _require_error(response, ErrorCode.NO_TEXT, "recognize-no-text")
    return _line(encode_response(response))


def _recognize_image_unreadable() -> str:
    response = handle_recognize(
        RecognizeRequest(
            id="recognize-image-unreadable",
            image_path=Path("/kiriglyph-golden-missing-image.png"),
        ),
        RapidOcrEngine(),
    )
    _require_error(response, ErrorCode.IMAGE_UNREADABLE, "recognize-image-unreadable")
    return _line(encode_response(response))


def _recognize_ocr_failed(image_path: Path) -> str:
    response = handle_recognize(
        RecognizeRequest(id="recognize-ocr-failed", image_path=image_path),
        _FailingEngine(),
    )
    _require_error(response, ErrorCode.OCR_FAILED, "recognize-ocr-failed")
    return _line(encode_response(response))


def _decode_codes_ok(image_path: Path) -> str:
    codes = decode_barcodes(image_path)
    if codes != [{"format": "QRCode", "text": "https://example.com/local"}]:
        raise RuntimeError(f"unexpected barcode decode: {codes}")
    response = handle_decode_codes(
        RecognizeRequest(
            id="decode-codes-ok",
            image_path=image_path,
            method="decode_codes",
        )
    )
    if response.get("ok") is not True or response["result"]["codes"] != codes:
        raise RuntimeError("decode_codes ok golden did not echo the decoder")
    return _line(encode_response(response))


def _decode_codes_empty(image_path: Path) -> str:
    response = handle_decode_codes(
        RecognizeRequest(
            id="decode-codes-empty",
            image_path=image_path,
            method="decode_codes",
        )
    )
    if response.get("ok") is not True or response["result"]["codes"] != []:
        raise RuntimeError("decode_codes empty golden was not an empty code list")
    return _line(encode_response(response))


def _segmentation_embed_ok() -> str:
    handle = EmbeddedImageHandle(
        handle="embed-1",
        image_width=8,
        image_height=6,
        timings=SegmentationTimings(load_ms=1, embed_ms=2),
    )
    response = segmentation_success_response("segmentation-embed-ok", handle.to_json())
    return _line(encode_segmentation_response(response))


def _segmentation_prompt_ok() -> str:
    data = mask_png_bytes()
    stats = MaskStats(
        outcome=MaskOutcome.OK,
        area_fraction=0.25,
        bounds=Rect(1, 1, 4, 3),
        touches_edge=EdgeTouches(),
        components=ComponentStats(1, Rect(1, 1, 4, 3)),
    )
    result = SegmentationResult(
        image_width=8,
        image_height=6,
        mask=MaskReference(
            encoding=MaskEncoding.ALPHA_PNG_FILE,
            path=MASK_RELATIVE_PATH,
            byte_length=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
        ),
        bounds=stats.bounds,
        mask_stats=stats,
        confidence=0.7,
        stability_score=None,
        timings=SegmentationTimings(prompt_ms=3),
    )
    response = segmentation_success_response(
        "segmentation-prompt-ok",
        result.to_json(),
    )
    return _line(encode_segmentation_response(response))


def _segmentation_model_missing(models_root: Path) -> str:
    try:
        EfficientSamTiAdapter(models_root=models_root)
    except SegmentationContractError as exc:
        response = error_from_contract("segmentation-model-missing", exc)
    else:
        raise RuntimeError("expected the real adapter to report model_missing")
    if response["error"]["code"] != "model_missing":
        raise RuntimeError("segmentation typed error was not model_missing")
    return _line(encode_segmentation_response(response))


def _write_text_image(path: Path, text: str) -> None:
    image = Image.new("RGB", (160, 48), "white")
    ImageDraw.Draw(image).text((8, 8), text, fill="black")
    image.save(path, format="PNG")


def _write_blank_image(path: Path) -> None:
    Image.new("RGB", (160, 48), "white").save(path, format="PNG")


def _write_qr_image(path: Path, text: str) -> None:
    qrcode.make(text).save(path)


class _FailingEngine:
    def recognize(self, image_path: Path, *, width: int, height: int) -> dict:
        raise OcrEngineError("private recognizer detail")


def _require_error(response: dict, code: ErrorCode, label: str) -> None:
    error = response.get("error") or {}
    if response.get("ok") is not False or error.get("code") != code.value:
        raise RuntimeError(f"{label} golden was not {code.value}: {response}")
    if "result" in response:
        raise RuntimeError(f"{label} error golden included a result")


def _line(encoded: str) -> str:
    return encoded + "\n"


def _png(width: int, height: int, rgba: bytes) -> bytes:
    if len(rgba) != width * height * 4:
        raise RuntimeError("PNG pixel buffer has the wrong size")

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = b"".join(
        b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4] for y in range(height)
    )
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    write_goldens()


if __name__ == "__main__":
    main()
