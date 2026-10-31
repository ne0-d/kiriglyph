from __future__ import annotations

import asyncio
import json

import pytest

from worker import portal_capture
from worker.portal_capture import (
    CaptureOutcome,
    PortalCallError,
    PortalClient,
    capture,
    outcome_for_error,
    outcome_for_response,
    path_from_uri,
    request_object_path,
)


@pytest.mark.parametrize(
    ("uri", "expected"),
    [
        (
            "file:///home/user/Pictures/Screenshots/Screenshot%20from%20x.png",
            "/home/user/Pictures/Screenshots/Screenshot from x.png",
        ),
        ("file://localhost/tmp/a.png", "/tmp/a.png"),
        ("file://otherhost/tmp/a.png", None),
        ("https://example.com/a.png", None),
        ("file:relative.png", None),
        ("", None),
        (None, None),
    ],
)
def test_path_from_uri_accepts_only_local_absolute_files(uri, expected):
    assert path_from_uri(uri) == expected


def test_request_path_follows_the_portal_naming_rule():
    assert request_object_path(":1.42", "tok") == (
        "/org/freedesktop/portal/desktop/request/1_42/tok"
    )


def test_response_codes_map_to_distinct_outcomes(tmp_path):
    image = tmp_path / "shot one.png"
    image.write_bytes(b"png")

    assert outcome_for_response(0, {"uri": image.as_uri()}) == CaptureOutcome(
        "captured", str(image)
    )
    assert outcome_for_response(1, {}).outcome == "cancelled"
    assert outcome_for_response(2, {}).outcome == "ended"
    assert outcome_for_response(7, {}).outcome == "failed"
    assert outcome_for_response(0, {}).outcome == "invalid_uri"
    assert (
        outcome_for_response(0, {"uri": (tmp_path / "gone.png").as_uri()}).outcome
        == "unreadable"
    )


def test_dbus_errors_map_to_unavailable_denied_or_failed():
    assert (
        outcome_for_error("org.freedesktop.DBus.Error.ServiceUnknown").outcome
        == "unavailable"
    )
    assert (
        outcome_for_error("org.freedesktop.DBus.Error.AccessDenied").outcome
        == "denied"
    )
    assert outcome_for_error("org.example.Boom").outcome == "failed"


class _FakePortal(PortalClient):
    def __init__(
        self,
        *,
        version=2,
        handle=None,
        response=(1, {}),
        error=None,
        register_error=None,
    ):
        self.unique_name = ":1.7"
        self._version = version
        self._handle = handle
        self._response = response
        self._error = error
        self._register_error = register_error
        self.calls: list[str] = []
        self.watched: list[str] = []
        self.tokens: list[str] = []
        self.interactive: list[bool] = []

    async def register(self, app_id: str) -> None:
        self.calls.append(f"register:{app_id}")
        if self._register_error is not None:
            raise PortalCallError(self._register_error)

    async def screenshot_version(self) -> int:
        self.calls.append("version")
        if self._error is not None:
            raise PortalCallError(self._error)
        return self._version

    async def watch_response(self, request_path: str) -> asyncio.Future:
        self.watched.append(request_path)
        future = asyncio.get_running_loop().create_future()
        future.set_result(self._response)
        return future

    async def screenshot(self, token: str, *, interactive: bool) -> str:
        self.calls.append("screenshot")
        self.tokens.append(token)
        self.interactive.append(interactive)
        return self._handle or request_object_path(self.unique_name, token)


def test_capture_watches_the_predicted_request_before_calling():
    portal = _FakePortal()

    outcome = asyncio.run(capture(portal, token_factory=lambda: "tok"))

    assert outcome.outcome == "cancelled"
    assert portal.watched == [request_object_path(":1.7", "tok")]
    assert portal.tokens == ["tok"]


def test_capture_follows_a_handle_that_differs_from_the_prediction():
    portal = _FakePortal(handle="/org/freedesktop/portal/desktop/request/x/y")

    asyncio.run(capture(portal, token_factory=lambda: "tok"))

    assert portal.watched[-1] == "/org/freedesktop/portal/desktop/request/x/y"


def test_capture_rejects_portals_without_interactive_support():
    assert asyncio.run(capture(_FakePortal(version=1))).outcome == "unavailable"


def test_capture_maps_a_missing_portal_to_unavailable():
    portal = _FakePortal(error="org.freedesktop.DBus.Error.ServiceUnknown")

    assert asyncio.run(capture(portal)).outcome == "unavailable"


def test_interactive_capture_never_registers():
    portal = _FakePortal()

    asyncio.run(capture(portal, token_factory=lambda: "tok"))

    assert portal.calls == ["version", "screenshot"]
    assert portal.interactive == [True]


def test_silent_capture_registers_before_any_other_portal_call(tmp_path):
    image = tmp_path / "Screenshot.png"
    image.write_bytes(b"png")
    portal = _FakePortal(version=1, response=(0, {"uri": image.as_uri()}))

    outcome = asyncio.run(
        capture(portal, interactive=False, app_id="dev.kiriglyph.Kiriglyph")
    )

    assert outcome == CaptureOutcome("captured", str(image))
    assert portal.calls == ["register:dev.kiriglyph.Kiriglyph", "version", "screenshot"]
    assert portal.interactive == [False]


def test_silent_capture_without_a_grant_ends():
    portal = _FakePortal(response=(2, {}))

    outcome = asyncio.run(capture(portal, interactive=False, app_id="a.b.C"))

    assert outcome.outcome == "ended"


def test_registration_failure_is_unavailable_and_skips_capture(capsys):
    portal = _FakePortal(register_error="org.freedesktop.portal.Error.Failed")

    outcome = asyncio.run(capture(portal, interactive=False, app_id="a.b.C"))

    assert outcome.outcome == "unavailable"
    assert portal.calls == ["register:a.b.C"]
    assert "app registration failed" in capsys.readouterr().err


def test_options_default_to_interactive_without_registration():
    assert portal_capture.parse_options([]) == portal_capture.CaptureOptions()
    assert portal_capture.parse_options(
        ["--silent", "--app-id", "dev.kiriglyph.Kiriglyph"]
    ) == portal_capture.CaptureOptions(
        interactive=False, app_id="dev.kiriglyph.Kiriglyph"
    )


def test_main_prints_exactly_one_json_line(monkeypatch, capsys):
    seen = []

    async def fake_run(options):
        seen.append(options)
        return CaptureOutcome("captured", "/tmp/shot.png")

    monkeypatch.setattr(portal_capture, "_run", fake_run)

    portal_capture.main(["--silent", "--app-id", "a.b.C"])

    out = capsys.readouterr()
    lines = out.out.splitlines()
    assert len(lines) == 1
    assert json.loads(lines[0]) == {"outcome": "captured", "path": "/tmp/shot.png"}
    assert "/tmp/shot.png" not in out.err
    assert seen == [portal_capture.CaptureOptions(interactive=False, app_id="a.b.C")]


def test_main_reports_unavailable_without_a_session_bus(monkeypatch, capsys):
    async def no_bus():
        raise OSError("no bus")

    monkeypatch.setattr(portal_capture, "_connect_session_bus", no_bus)

    portal_capture.main([])

    assert json.loads(capsys.readouterr().out) == {"outcome": "unavailable"}
