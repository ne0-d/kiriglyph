from __future__ import annotations

import struct
from pathlib import Path
from typing import BinaryIO


class ImageSizeError(Exception):
    pass


JPEG_SCAN_LIMIT_BYTES = 1_048_576


def read_image_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        header = image.read(24)

        if header.startswith(b"\x89PNG\r\n\x1a\n"):
            if len(header) < 24:
                raise ImageSizeError("truncated PNG header")
            width, height = struct.unpack(">II", header[16:24])
            if width < 1 or height < 1:
                raise ImageSizeError("invalid PNG dimensions")
            return width, height

        if header[:6] in (b"GIF87a", b"GIF89a"):
            if len(header) < 10:
                raise ImageSizeError("truncated GIF header")
            width, height = struct.unpack("<HH", header[6:10])
            if width < 1 or height < 1:
                raise ImageSizeError("invalid GIF dimensions")
            return width, height

        if header.startswith(b"\xff\xd8"):
            image.seek(0)
            return _jpeg_size(image)

    raise ImageSizeError("unsupported or unreadable image format")


def _read_limited(image: BinaryIO, size: int, scanned: int) -> tuple[bytes, int]:
    if scanned + size > JPEG_SCAN_LIMIT_BYTES:
        raise ImageSizeError("JPEG header scan limit exceeded")
    data = image.read(size)
    if len(data) != size:
        raise ImageSizeError("truncated JPEG header")
    return data, scanned + size


def _skip_limited(image: BinaryIO, size: int, scanned: int) -> int:
    if scanned + size > JPEG_SCAN_LIMIT_BYTES:
        raise ImageSizeError("JPEG header scan limit exceeded")
    image.seek(size, 1)
    return scanned + size


def _jpeg_size(image: BinaryIO) -> tuple[int, int]:
    soi, scanned = _read_limited(image, 2, 0)
    if soi != b"\xff\xd8":
        raise ImageSizeError("missing JPEG SOI marker")

    while True:
        marker_prefix, scanned = _read_limited(image, 1, scanned)
        if marker_prefix != b"\xff":
            raise ImageSizeError("invalid JPEG marker sequence")

        marker_bytes = b"\xff"
        while marker_bytes == b"\xff":
            marker_bytes, scanned = _read_limited(image, 1, scanned)
        marker = marker_bytes[0]

        if marker in (0xD8, 0xD9):
            continue

        segment_length_bytes, scanned = _read_limited(image, 2, scanned)
        segment_length = struct.unpack(">H", segment_length_bytes)[0]
        if segment_length < 2:
            raise ImageSizeError("invalid JPEG segment length")

        if marker in (
            0xC0,
            0xC1,
            0xC2,
            0xC3,
            0xC5,
            0xC6,
            0xC7,
            0xC9,
            0xCA,
            0xCB,
            0xCD,
            0xCE,
            0xCF,
        ):
            sof_header, scanned = _read_limited(image, 5, scanned)
            height, width = struct.unpack(">HH", sof_header[1:5])
            if width < 1 or height < 1:
                raise ImageSizeError("invalid JPEG dimensions")
            return width, height

        scanned = _skip_limited(image, segment_length - 2, scanned)
