from __future__ import annotations

from pathlib import Path

import qrcode

from conftest import parse_response_line, read_response_line, write_request
from worker.barcode_decoder import decode_barcodes


def _qr_fixture(tmp_path: Path, text: str) -> Path:
    image = qrcode.make(text)
    path = tmp_path / "qr.png"
    image.save(path)
    return path


def test_decode_barcodes_reads_generated_qr(tmp_path: Path):
    path = _qr_fixture(tmp_path, "https://example.com/local")

    codes = decode_barcodes(path)

    assert codes == [{"format": "QRCode", "text": "https://example.com/local"}]


def test_worker_decodes_codes_without_logging_content(worker_process, tmp_path: Path):
    path = _qr_fixture(tmp_path, "private-code-content")
    write_request(
        worker_process,
        {
            "version": 1,
            "id": "decode-qr",
            "method": "decode_codes",
            "params": {"image_path": str(path)},
        },
    )

    response = parse_response_line(read_response_line(worker_process))

    assert response["id"] == "decode-qr"
    assert response["ok"] is True
    assert response["result"]["codes"] == [
        {"format": "QRCode", "text": "private-code-content"}
    ]
    assert worker_process.stderr is not None
    worker_process.stdin.close()
    worker_process.stdin = None
    _, stderr = worker_process.communicate(timeout=5)
    assert "private-code-content" not in stderr
    assert str(path) not in stderr
