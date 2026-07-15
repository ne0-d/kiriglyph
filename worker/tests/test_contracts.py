from __future__ import annotations

import json

import pytest
from jsonschema.exceptions import ValidationError

from conftest import FIXTURES, SAMPLE_IMAGE, validate
from worker.protocol import parse_request_line


REQUEST_FIXTURES = [
    ("request-valid-recognize.json", True),
    ("request-invalid-boolean-version.json", False),
    ("request-invalid-extra-field.json", False),
]


@pytest.mark.parametrize(("fixture_name", "is_valid"), REQUEST_FIXTURES)
def test_request_fixtures_match_request_schema(
    fixture_name: str,
    is_valid: bool,
    schema_store: dict[str, dict],
    schema_registry,
):
    payload = json.loads((FIXTURES / fixture_name).read_text(encoding="utf-8"))

    if is_valid:
        validate(payload, schema_store["request"], schema_registry)
    else:
        with pytest.raises(ValidationError):
            validate(payload, schema_store["request"], schema_registry)


@pytest.mark.parametrize(
    ("name", "payload", "schema_valid", "runtime_code"),
    [
        ("valid", {"version": 1, "id": "ok", "method": "recognize", "params": {"image_path": str(SAMPLE_IMAGE)}}, True, None),
        ("boolean version", {"version": True, "id": "bad-bool", "method": "recognize", "params": {"image_path": str(SAMPLE_IMAGE)}}, False, "invalid_envelope"),
        ("float version", {"version": 1.5, "id": "bad-float", "method": "recognize", "params": {"image_path": str(SAMPLE_IMAGE)}}, False, "invalid_envelope"),
        ("missing id", {"version": 1, "method": "recognize", "params": {"image_path": str(SAMPLE_IMAGE)}}, False, "invalid_envelope"),
        ("non-object params", {"version": 1, "id": "bad-params", "method": "recognize", "params": []}, False, "invalid_envelope"),
        ("extra request key", {"version": 1, "id": "bad-extra", "method": "recognize", "params": {"image_path": str(SAMPLE_IMAGE)}, "extra": None}, False, "invalid_envelope"),
        ("extra params key", {"version": 1, "id": "bad-extra-param", "method": "recognize", "params": {"image_path": str(SAMPLE_IMAGE), "extra": None}}, False, "invalid_envelope"),
        ("unsupported method", {"version": 1, "id": "bad-method", "method": "shutdown", "params": {"image_path": str(SAMPLE_IMAGE)}}, False, "unsupported_method"),
    ],
)
def test_request_schema_and_runtime_validation_agree(
    name: str,
    payload: dict,
    schema_valid: bool,
    runtime_code: str | None,
    schema_store: dict[str, dict],
    schema_registry,
):
    try:
        validate(payload, schema_store["request"], schema_registry)
        actual_schema_valid = True
    except ValidationError:
        actual_schema_valid = False

    request, error = parse_request_line(json.dumps(payload))

    assert actual_schema_valid is schema_valid, name
    if schema_valid:
        assert request is not None
        assert error is None
    else:
        assert request is None
        assert error is not None
        assert error["error"]["code"] == runtime_code


def test_success_schema_allows_empty_ocr_result(schema_store: dict[str, dict], schema_registry):
    response = {
        "version": 1,
        "id": "empty-result",
        "ok": True,
        "result": {
            "image": {"width": 1, "height": 1},
            "full_text": "",
            "regions": [],
            "timings_ms": {"total": 0},
        },
    }

    validate(response, schema_store["response_success"], schema_registry)


def test_runtime_rejects_integral_float_version():
    request, error = parse_request_line(
        json.dumps(
            {
                "version": 1.0,
                "id": "bad-integral-float",
                "method": "recognize",
                "params": {"image_path": str(SAMPLE_IMAGE)},
            }
        )
    )

    assert request is None
    assert error is not None
    assert error["error"]["code"] == "invalid_envelope"
