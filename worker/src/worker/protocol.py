from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any

from worker.image_size import ImageSizeError, read_image_size
from worker.rapidocr_engine import OcrEngine, OcrEngineError

PROTOCOL_VERSION = 1
SUPPORTED_METHOD = "recognize"
REQUEST_KEYS = frozenset({"version", "id", "method", "params"})
PARAM_KEYS = frozenset({"image_path"})
MAX_NDJSON_LINE_BYTES = 1_048_576


class ErrorCode(StrEnum):
    MALFORMED_JSON = "malformed_json"
    INVALID_ENVELOPE = "invalid_envelope"
    UNSUPPORTED_METHOD = "unsupported_method"
    IMAGE_UNREADABLE = "image_unreadable"
    NO_TEXT = "no_text"
    OCR_FAILED = "ocr_failed"
    INTERNAL_ERROR = "internal_error"


@dataclass(frozen=True)
class RecognizeRequest:
    id: str
    image_path: Path


def _message_id(payload: dict[str, Any]) -> str | None:
    raw = payload.get("id")
    if isinstance(raw, str) and raw:
        return raw
    return None


def parse_request_line(
    raw_line: str,
) -> tuple[RecognizeRequest | None, dict[str, Any] | None]:
    try:
        payload = json.loads(raw_line)
    except json.JSONDecodeError:
        return None, error_response(
            None,
            ErrorCode.MALFORMED_JSON,
            "request line is not valid JSON",
        )

    if not isinstance(payload, dict):
        return None, error_response(
            None,
            ErrorCode.INVALID_ENVELOPE,
            "request must be a JSON object",
        )

    extra_top = set(payload) - REQUEST_KEYS
    if extra_top:
        return None, error_response(
            _message_id(payload),
            ErrorCode.INVALID_ENVELOPE,
            f"unexpected request fields: {', '.join(sorted(extra_top))}",
        )

    version = payload.get("version")
    if type(version) is not int or version != PROTOCOL_VERSION:
        return None, error_response(
            _message_id(payload),
            ErrorCode.INVALID_ENVELOPE,
            "unsupported protocol version",
        )

    message_id = _message_id(payload)
    if message_id is None:
        return None, error_response(
            None,
            ErrorCode.INVALID_ENVELOPE,
            "id must be a non-empty string",
        )

    method = payload.get("method")
    if method != SUPPORTED_METHOD:
        return None, error_response(
            message_id,
            ErrorCode.UNSUPPORTED_METHOD,
            f"unsupported method: {method!r}",
        )

    params = payload.get("params")
    if not isinstance(params, dict):
        return None, error_response(
            message_id,
            ErrorCode.INVALID_ENVELOPE,
            "params must be a JSON object",
        )

    extra_params = set(params) - PARAM_KEYS
    if extra_params:
        return None, error_response(
            message_id,
            ErrorCode.INVALID_ENVELOPE,
            f"unexpected params fields: {', '.join(sorted(extra_params))}",
        )

    image_path_raw = params.get("image_path")
    if not isinstance(image_path_raw, str) or not image_path_raw:
        return None, error_response(
            message_id,
            ErrorCode.INVALID_ENVELOPE,
            "image_path must be a non-empty string",
        )

    return RecognizeRequest(id=message_id, image_path=Path(image_path_raw)), None


def handle_recognize(
    request: RecognizeRequest,
    engine: OcrEngine,
) -> dict[str, Any]:
    path = request.image_path
    try:
        width, height = read_image_size(path)
    except (OSError, ImageSizeError):
        return error_response(
            request.id,
            ErrorCode.IMAGE_UNREADABLE,
            "image file is missing or not readable",
        )

    try:
        result = engine.recognize(path, width=width, height=height)
    except OcrEngineError:
        return error_response(
            request.id,
            ErrorCode.OCR_FAILED,
            "local text recognition failed",
        )
    if not result["regions"]:
        return error_response(
            request.id,
            ErrorCode.NO_TEXT,
            "no text was recognized in the image",
        )
    return success_response(request.id, result)


def success_response(message_id: str, result: dict[str, Any]) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "id": message_id,
        "ok": True,
        "result": result,
    }


def error_response(
    message_id: str | None,
    code: ErrorCode,
    message: str,
) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "id": message_id,
        "ok": False,
        "error": {"code": code.value, "message": message},
    }


def encode_response(response: dict[str, Any]) -> str:
    return json.dumps(response, separators=(",", ":"))
