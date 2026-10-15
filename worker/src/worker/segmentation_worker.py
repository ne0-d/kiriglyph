from __future__ import annotations

import sys
import threading
from concurrent.futures import Future, ThreadPoolExecutor
from typing import Callable

from worker.efficient_sam_adapter import EfficientSamTiAdapter
from worker.segmentation_contract import (
    SegmentationAdapter,
    SegmentationContractError,
    SegmentationFailureKind,
)
from worker.segmentation_protocol import (
    MAX_NDJSON_LINE_BYTES,
    SegmentationMethod,
    SegmentationRequest,
    encode_response,
    error_from_contract,
    error_response,
    parse_cancel_params,
    parse_embed_params,
    parse_prompt_params,
    parse_request_line,
    success_response,
)


AdapterFactory = Callable[[], SegmentationAdapter]


class SegmentationWorker:
    def __init__(self, adapter_factory: AdapterFactory = EfficientSamTiAdapter) -> None:
        self._adapter_factory = adapter_factory
        self._adapter: SegmentationAdapter | None = None
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._pending: dict[str, Future] = {}
        self._cancelled: set[str] = set()
        self._stdout_lock = threading.Lock()
        self._closed = False

    def handle(self, request: SegmentationRequest) -> bool:
        if self._closed and request.method is not SegmentationMethod.CLOSE:
            self._write(
                error_response(
                    request.id,
                    SegmentationFailureKind.SESSION_CLOSED.value,
                    "segmentation session is closed",
                )
            )
            return True
        if request.method is SegmentationMethod.CANCEL:
            self._cancel(request)
            return True
        if request.method is SegmentationMethod.CLOSE:
            self._close(request)
            return False
        future = self._executor.submit(self._run_request, request)
        self._pending[request.id] = future
        future.add_done_callback(lambda done, req=request: self._finish(req, done))
        return True

    def shutdown(self) -> None:
        self._closed = True
        self._executor.shutdown(wait=False, cancel_futures=True)
        if self._adapter is not None:
            self._adapter.close_session()
            self._adapter = None

    def _run_request(self, request: SegmentationRequest) -> dict:
        adapter = self._ensure_adapter()
        if request.method is SegmentationMethod.EMBED:
            embed = adapter.embed_image(parse_embed_params(request.params))
            return success_response(request.id, embed.to_json())
        if request.method is SegmentationMethod.PROMPT:
            handle, prompt = parse_prompt_params(request.params)
            result = adapter.prompt(handle, prompt)
            return success_response(request.id, result.to_json())
        return error_response(request.id, "unsupported_method", "unsupported segmentation method")

    def _finish(self, request: SegmentationRequest, future: Future) -> None:
        self._pending.pop(request.id, None)
        if request.id in self._cancelled:
            self._cancelled.remove(request.id)
            self._write(
                error_response(
                    request.id,
                    SegmentationFailureKind.CANCELLED.value,
                    "segmentation request was cancelled",
                )
            )
            return
        try:
            response = future.result()
        except SegmentationContractError as exc:
            response = error_from_contract(request.id, exc)
        except MemoryError:
            response = error_response(
                request.id,
                SegmentationFailureKind.OUT_OF_MEMORY.value,
                "segmentation worker ran out of memory",
            )
        except Exception:  # noqa: BLE001 - process boundary must not leak details.
            response = error_response(
                request.id,
                SegmentationFailureKind.MODEL_LOAD_FAILED.value,
                "local segmentation failed",
            )
        self._write(response)

    def _cancel(self, request: SegmentationRequest) -> None:
        try:
            target = parse_cancel_params(request.params)
        except SegmentationContractError as exc:
            self._write(error_from_contract(request.id, exc))
            return
        future = self._pending.get(target)
        if future is not None:
            self._cancelled.add(target)
            future.cancel()
        self._write(success_response(request.id, {"request_id": target, "cancelled": True}))

    def _close(self, request: SegmentationRequest) -> None:
        self._closed = True
        for request_id, future in list(self._pending.items()):
            self._cancelled.add(request_id)
            future.cancel()
        if self._adapter is not None:
            self._adapter.close_session()
            self._adapter = None
        self._write(success_response(request.id, {"closed": True}))

    def _ensure_adapter(self) -> SegmentationAdapter:
        if self._adapter is None:
            self._adapter = self._adapter_factory()
        return self._adapter

    def _write(self, response: dict) -> None:
        with self._stdout_lock:
            sys.stdout.write(encode_response(response) + "\n")
            sys.stdout.flush()


def process_request_line(raw_line: bytes, worker: SegmentationWorker) -> bool:
    if len(raw_line) > MAX_NDJSON_LINE_BYTES:
        worker._write(error_response(None, "malformed_json", "request line exceeds maximum length"))
        return True
    try:
        line = raw_line.rstrip(b"\n").decode("utf-8")
    except UnicodeDecodeError:
        worker._write(error_response(None, "malformed_json", "request line is not valid UTF-8 JSON"))
        return True
    request, error = parse_request_line(line)
    if error is not None:
        worker._write(error)
        return True
    assert request is not None
    return worker.handle(request)


def _drain_oversized_line() -> None:
    while True:
        chunk = sys.stdin.buffer.readline(MAX_NDJSON_LINE_BYTES)
        if chunk == b"" or chunk.endswith(b"\n"):
            return


def run_loop(adapter_factory: AdapterFactory = EfficientSamTiAdapter) -> None:
    worker = SegmentationWorker(adapter_factory)
    try:
        while True:
            raw_line = sys.stdin.buffer.readline(MAX_NDJSON_LINE_BYTES + 1)
            if raw_line == b"":
                return
            if raw_line == b"\n":
                continue
            if len(raw_line) > MAX_NDJSON_LINE_BYTES and not raw_line.endswith(b"\n"):
                _drain_oversized_line()
            print("segmentation request received", file=sys.stderr, flush=True)
            keep_running = process_request_line(raw_line, worker)
            if not keep_running:
                return
    finally:
        worker.shutdown()


def main() -> None:
    try:
        run_loop()
    except BrokenPipeError:
        pass


if __name__ == "__main__":
    main()
