from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

WORKER_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = WORKER_ROOT.parent
CONTRACTS_V1 = REPO_ROOT / "contracts" / "v1"
FIXTURES = REPO_ROOT / "fixtures" / "worker" / "protocol"
SAMPLE_IMAGE = FIXTURES / "sample-64x32.png"
REAL_OCR_IMAGE = REPO_ROOT / "fixtures" / "worker" / "images" / "hello-ubuntu.png"


def load_schema(name: str) -> dict:
    path = CONTRACTS_V1 / name
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def schema_store() -> dict[str, dict]:
    names = [
        "point.schema.json",
        "polygon.schema.json",
        "request-params.schema.json",
        "request.schema.json",
        "image.schema.json",
        "region.schema.json",
        "recognize-result.schema.json",
        "error-code.schema.json",
        "protocol-error.schema.json",
        "response-success.schema.json",
        "response-error.schema.json",
        "response.schema.json",
    ]
    store = {name: load_schema(name) for name in names}
    store["request"] = store["request.schema.json"]
    store["response_success"] = store["response-success.schema.json"]
    store["response_error"] = store["response-error.schema.json"]
    store["response"] = store["response.schema.json"]
    return store


@pytest.fixture(scope="session")
def schema_registry(schema_store: dict[str, dict]) -> Registry:
    resources = (
        (schema["$id"], Resource.from_contents(schema))
        for name, schema in schema_store.items()
        if name.endswith(".schema.json")
    )
    return Registry().with_resources(resources)


def validate(instance: object, schema: dict, registry: Registry) -> None:
    Draft202012Validator(schema, registry=registry).validate(instance)


def worker_env() -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(WORKER_ROOT / "src")
    return env


def recognize_request(request_id: str, image_path: Path | str) -> dict:
    return {
        "version": 1,
        "id": request_id,
        "method": "recognize",
        "params": {"image_path": str(image_path)},
    }


@pytest.fixture
def worker_process():
    proc = subprocess.Popen(
        [sys.executable, "-m", "worker"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=WORKER_ROOT,
        env=worker_env(),
        text=True,
        bufsize=1,
    )
    try:
        yield proc
    finally:
        if proc.poll() is None:
            proc.stdin.close()
            proc.wait(timeout=5)


def write_request(proc: subprocess.Popen[str], payload: dict) -> None:
    assert proc.stdin is not None
    proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    proc.stdin.flush()


def read_response_line(proc: subprocess.Popen[str]) -> str:
    assert proc.stdout is not None
    line = proc.stdout.readline()
    assert line != "", "worker stdout closed before a response line"
    return line.rstrip("\n")


def parse_response_line(line: str) -> dict:
    return json.loads(line)
