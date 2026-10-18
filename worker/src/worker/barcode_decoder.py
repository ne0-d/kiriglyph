from __future__ import annotations

from pathlib import Path
from typing import Any

from PIL import Image, UnidentifiedImageError
import zxingcpp


class BarcodeDecodeError(Exception):
    pass


def decode_barcodes(path: Path) -> list[dict[str, str]]:
    try:
        image = Image.open(path)
        image.load()
    except (OSError, UnidentifiedImageError) as exc:
        raise BarcodeDecodeError("image is not readable") from exc

    try:
        results = zxingcpp.read_barcodes(image)
    except Exception as exc:  # noqa: BLE001 - third-party decoder boundary.
        raise BarcodeDecodeError("barcode decoding failed") from exc

    codes: list[dict[str, str]] = []
    for result in results:
        text = getattr(result, "text", "")
        if not isinstance(text, str) or not text:
            continue
        codes.append(
            {"format": _format_name(getattr(result, "format", "")), "text": text}
        )
    return codes


def _format_name(raw: Any) -> str:
    value = getattr(raw, "name", None) or str(raw)
    return value.replace("BarcodeFormat.", "")
