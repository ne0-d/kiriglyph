from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from worker.segmentation_contract import (
    EmbedImageRequest,
    EmbeddedImageHandle,
    SegmentationContractError,
    SegmentationFailureKind,
    SegmentationPrompt,
)

PROTOCOL_VERSION = 1
MAX_NDJSON_LINE_BYTES = 1_048_576


class SegmentationMethod(StrEnum):
    EMBED = "embed"
    PROMPT = "prompt"
    CANCEL = "cancel"
    CLOSE = "close"


@dataclass(frozen=True)
class SegmentationRequest:
    id: str
    method: SegmentationMethod
    params: dict[str, Any]


def parse_request_line(raw_line: str) -> tuple[SegmentationRequest | None, dict[str, Any] | None]:
    try:
        payload = json.loads(raw_line)
    except json.JSONDecodeError:
        return None, error_response(None, "malformed_json", "request line is not valid JSON")
    if not isinstance(payload, dict):
        return None, error_response(None, "invalid_envelope", "request must be a JSON object")
    version = payload.get("version")
    if type(version) is not int or version != PROTOCOL_VERSION:
        return None, error_response(_message_id(payload), "invalid_envelope", "unsupported protocol version")
    message_id = _message_id(payload)
    if message_id is None:
        return None, error_response(None, "invalid_envelope", "id must be a non-empty string")
    try:
        method = SegmentationMethod(payload.get("method"))
    except ValueError:
        return None, error_response(message_id, "unsupported_method", "unsupported segmentation method")
    params = payload.get("params", {})
    if not isinstance(params, dict):
        return None, error_response(message_id, "invalid_envelope", "params must be an object")
    return SegmentationRequest(id=message_id, method=method, params=params), None


def parse_embed_params(params: dict[str, Any]) -> EmbedImageRequest:
    return EmbedImageRequest.from_json(params)


def parse_prompt_params(params: dict[str, Any]) -> tuple[EmbeddedImageHandle, SegmentationPrompt]:
    handle = EmbeddedImageHandle.from_json(params.get("handle"))
    prompt = SegmentationPrompt.from_json(params.get("prompt"))
    return handle, prompt


def parse_cancel_params(params: dict[str, Any]) -> str:
    request_id = params.get("request_id")
    if not isinstance(request_id, str) or not request_id:
        raise SegmentationContractError(
            SegmentationFailureKind.MALFORMED_OUTPUT,
            "cancel request_id must be a non-empty string",
        )
    return request_id


def success_response(message_id: str, result: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "id": message_id,
        "ok": True,
        "result": result or {},
    }


def error_response(
    message_id: str | None,
    code: str,
    message: str,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if details:
        error["details"] = details
    return {"version": PROTOCOL_VERSION, "id": message_id, "ok": False, "error": error}


def error_from_contract(message_id: str, error: SegmentationContractError) -> dict[str, Any]:
    return error_response(message_id, error.kind.value, error.message, error.details)


def encode_response(response: dict[str, Any]) -> str:
    return json.dumps(response, separators=(",", ":"))


def _message_id(payload: dict[str, Any]) -> str | None:
    raw = payload.get("id")
    if isinstance(raw, str) and raw:
        return raw
    return None
