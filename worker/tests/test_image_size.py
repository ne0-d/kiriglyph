from __future__ import annotations

import struct
from pathlib import Path

import pytest
from PIL import Image
from worker.image_size import ImageSizeError, read_image_size


def png_header(width: int, height: int) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + b"\0" * 8 + struct.pack(">II", width, height)


def gif_header(width: int, height: int) -> bytes:
    return b"GIF89a" + struct.pack("<HH", width, height) + b"\0" * 4


def jpeg_with_sof(width: int, height: int, filler_size: int = 0) -> bytes:
    filler = bytearray()
    while filler_size:
        chunk_size = min(filler_size, 60_000)
        filler += b"\xff\xe0" + struct.pack(">H", chunk_size + 2) + (b"x" * chunk_size)
        filler_size -= chunk_size
    sof_payload = b"\x08" + struct.pack(">HH", height, width) + b"\x01\x01\x11\x00"
    return (
        b"\xff\xd8"
        + bytes(filler)
        + b"\xff\xc0"
        + struct.pack(">H", len(sof_payload) + 2)
        + sof_payload
    )


@pytest.mark.parametrize(
    ("content", "expected"),
    [
        (png_header(7, 5) + (b"x" * 5_000_000), (7, 5)),
        (gif_header(9, 4) + (b"x" * 5_000_000), (9, 4)),
        (jpeg_with_sof(11, 6), (11, 6)),
    ],
)
def test_read_image_size_uses_bounded_headers(
    tmp_path: Path, content: bytes, expected: tuple[int, int]
):
    image = tmp_path / "image.bin"
    image.write_bytes(content)

    assert read_image_size(image) == expected


def test_jpeg_scan_cap_rejects_unbounded_header_search(tmp_path: Path):
    image = tmp_path / "huge-prefix.jpg"
    image.write_bytes(jpeg_with_sof(11, 6, filler_size=2_000_000))

    with pytest.raises(ImageSizeError):
        read_image_size(image)


@pytest.mark.parametrize(
    ("image_format", "expected"), [("BMP", (13, 7)), ("WEBP", (14, 8))]
)
def test_read_image_size_supports_picker_formats(
    tmp_path: Path,
    image_format: str,
    expected: tuple[int, int],
):
    image_path = tmp_path / f"image.{image_format.lower()}"
    Image.new("RGB", expected, "white").save(image_path, format=image_format)

    assert read_image_size(image_path) == expected
