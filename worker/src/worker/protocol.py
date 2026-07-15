from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from worker.image_size import ImageSizeError, read_image_size
from worker.mock_engine import build_mock_result

PROTOCOL_VERSION = 1
SUPPORTED_METHOD = "recognize"
REQUEST_KEYS = frozenset({"version", "id", "method", "params"})
PARAM_KEYS = frozenset({"image_path"})
MAX_NDJSON_LINE_BYTES = 1_048_576


@dataclass(frozen=True)
class RecognizeRequest:
    id: str
    image_path: Path


def _message_id(payload: dict[str, Any]) -> str | None:
    raw = payload.get("id")
    if isinstance(raw, str) and raw:
        return raw
    return None


def parse_request_line(raw_line: str) -> tuple[RecognizeRequest | None, dict[str, Any] | None]:
    try:
        payload = json.loads(raw_line)
    except json.JSONDecodeError:
        return None, error_response(None, "malformed_json", "request line is not valid JSON")

    if not isinstance(payload, dict):
        return None, error_response(None, "invalid_envelope", "request must be a JSON object")

    extra_top = set(payload) - REQUEST_KEYS
    if extra_top:
        return None, error_response(
            _message_id(payload),
            "invalid_envelope",
            f"unexpected request fields: {', '.join(sorted(extra_top))}",
        )

    version = payload.get("version")
    if type(version) is not int or version != PROTOCOL_VERSION:
        return None, error_response(
            _message_id(payload),
            "invalid_envelope",
            "unsupported protocol version",
        )

    message_id = _message_id(payload)
    if message_id is None:
        return None, error_response(None, "invalid_envelope", "id must be a non-empty string")

    method = payload.get("method")
    if method != SUPPORTED_METHOD:
        return None, error_response(message_id, "unsupported_method", f"unsupported method: {method!r}")

    params = payload.get("params")
    if not isinstance(params, dict):
        return None, error_response(message_id, "invalid_envelope", "params must be a JSON object")

    extra_params = set(params) - PARAM_KEYS
    if extra_params:
        return None, error_response(
            message_id,
            "invalid_envelope",
            f"unexpected params fields: {', '.join(sorted(extra_params))}",
        )

    image_path_raw = params.get("image_path")
    if not isinstance(image_path_raw, str) or not image_path_raw:
        return None, error_response(message_id, "invalid_envelope", "image_path must be a non-empty string")

    return RecognizeRequest(id=message_id, image_path=Path(image_path_raw)), None


def handle_recognize(request: RecognizeRequest) -> dict[str, Any]:
    path = request.image_path
    try:
        width, height = read_image_size(path)
    except (OSError, ImageSizeError):
        return error_response(request.id, "image_unreadable", "image file is missing or not readable")

    return success_response(request.id, build_mock_result(width, height))


def success_response(message_id: str, result: dict[str, Any]) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "id": message_id,
        "ok": True,
        "result": result,
    }


def error_response(
    message_id: str | None,
    code: str,
    message: str,
) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "id": message_id,
        "ok": False,
        "error": {"code": code, "message": message},
    }


def encode_response(response: dict[str, Any]) -> str:
    return json.dumps(response, separators=(",", ":"))
