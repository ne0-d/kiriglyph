"""One-shot XDG Screenshot portal client.

Runs as its own short-lived process, separate from the long-lived OCR worker,
because an interactive capture lasts as long as the user takes to choose, and
because registering an app ID must be the first portal call on a D-Bus
connection, which the GTK app's shared connection can no longer guarantee.
Prints exactly one JSON object to stdout; diagnostics on stderr never include
paths or URIs.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import sys
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

PORTAL_BUS_NAME = "org.freedesktop.portal.Desktop"
PORTAL_OBJECT_PATH = "/org/freedesktop/portal/desktop"
SCREENSHOT_INTERFACE = "org.freedesktop.portal.Screenshot"
REQUEST_INTERFACE = "org.freedesktop.portal.Request"
REGISTRY_INTERFACE = "org.freedesktop.host.portal.Registry"
MIN_INTERACTIVE_VERSION = 2

UNAVAILABLE_ERRORS = frozenset(
    {
        "org.freedesktop.DBus.Error.ServiceUnknown",
        "org.freedesktop.DBus.Error.UnknownInterface",
        "org.freedesktop.DBus.Error.UnknownMethod",
        "org.freedesktop.DBus.Error.UnknownObject",
        "org.freedesktop.DBus.Error.NameHasNoOwner",
    }
)
DENIED_ERRORS = frozenset(
    {
        "org.freedesktop.DBus.Error.AccessDenied",
        "org.freedesktop.portal.Error.NotAllowed",
    }
)


@dataclass(frozen=True)
class CaptureOutcome:
    outcome: str
    path: str | None = None

    def to_json(self) -> str:
        payload: dict[str, str] = {"outcome": self.outcome}
        if self.path is not None:
            payload["path"] = self.path
        return json.dumps(payload, ensure_ascii=False)


class PortalCallError(Exception):
    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.name = name


def request_object_path(unique_name: str, token: str) -> str:
    sender = unique_name.removeprefix(":").replace(".", "_")
    return f"{PORTAL_OBJECT_PATH}/request/{sender}/{token}"


def path_from_uri(uri: object) -> str | None:
    if not isinstance(uri, str) or not uri:
        return None
    parsed = urlparse(uri)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
        return None
    path = unquote(parsed.path)
    if not path.startswith("/"):
        return None
    return path


def outcome_for_response(code: int, results: dict[str, Any]) -> CaptureOutcome:
    if code == 1:
        return CaptureOutcome("cancelled")
    if code == 2:
        return CaptureOutcome("ended")
    if code != 0:
        return CaptureOutcome("failed")
    path = path_from_uri(results.get("uri"))
    if path is None:
        return CaptureOutcome("invalid_uri")
    file = Path(path)
    if not file.is_file() or not os.access(file, os.R_OK):
        return CaptureOutcome("unreadable")
    return CaptureOutcome("captured", path)


def outcome_for_error(name: str) -> CaptureOutcome:
    if name in UNAVAILABLE_ERRORS:
        return CaptureOutcome("unavailable")
    if name in DENIED_ERRORS:
        return CaptureOutcome("denied")
    return CaptureOutcome("failed")


class PortalClient:
    """The D-Bus operations the capture flow needs; faked in tests."""

    unique_name: str

    async def register(self, app_id: str) -> None:
        raise NotImplementedError

    async def screenshot_version(self) -> int:
        raise NotImplementedError

    async def watch_response(self, request_path: str) -> asyncio.Future:
        raise NotImplementedError

    async def screenshot(self, token: str, *, interactive: bool) -> str:
        raise NotImplementedError


async def capture(
    client: PortalClient,
    token_factory: Callable[[], str] | None = None,
    *,
    interactive: bool = True,
    app_id: str | None = None,
) -> CaptureOutcome:
    if app_id is not None:
        # The portal accepts Register only before any other portal call on
        # the connection, so it must come before the version lookup.
        try:
            await client.register(app_id)
        except PortalCallError as error:
            _log(f"app registration failed: {error.name or 'unknown error'}")
            return CaptureOutcome("unavailable")
    try:
        version = await client.screenshot_version()
    except PortalCallError as error:
        return outcome_for_error(error.name)
    if interactive and version < MIN_INTERACTIVE_VERSION:
        return CaptureOutcome("unavailable")

    token = (token_factory or _new_token)()
    predicted = request_object_path(client.unique_name, token)
    try:
        response = await client.watch_response(predicted)
        handle = await client.screenshot(token, interactive=interactive)
        if handle != predicted:
            response = await client.watch_response(handle)
    except PortalCallError as error:
        return outcome_for_error(error.name)

    code, results = await response
    return outcome_for_response(code, results)


def _new_token() -> str:
    return f"kiriglyph_{secrets.token_hex(8)}"


class DbusFastPortalClient(PortalClient):
    def __init__(self, bus: Any) -> None:
        from dbus_fast import MessageType

        self._bus = bus
        self._signal_type = MessageType.SIGNAL
        self._pending: dict[str, asyncio.Future] = {}
        self._early: dict[str, tuple[int, dict[str, Any]]] = {}
        self.unique_name = bus.unique_name
        bus.add_message_handler(self._on_message)

    def _on_message(self, message: Any) -> bool:
        if (
            message.message_type != self._signal_type
            or message.interface != REQUEST_INTERFACE
            or message.member != "Response"
        ):
            return False
        code = int(message.body[0])
        results = {key: value.value for key, value in message.body[1].items()}
        future = self._pending.get(message.path)
        if future is not None and not future.done():
            future.set_result((code, results))
        else:
            self._early[message.path] = (code, results)
        return False

    async def _call(self, **kwargs: Any) -> list[Any]:
        from dbus_fast import Message, MessageType

        reply = await self._bus.call(Message(**kwargs))
        if reply.message_type == MessageType.ERROR:
            raise PortalCallError(reply.error_name or "")
        return reply.body

    async def register(self, app_id: str) -> None:
        await self._call(
            destination=PORTAL_BUS_NAME,
            path=PORTAL_OBJECT_PATH,
            interface=REGISTRY_INTERFACE,
            member="Register",
            signature="sa{sv}",
            body=[app_id, {}],
        )

    async def screenshot_version(self) -> int:
        body = await self._call(
            destination=PORTAL_BUS_NAME,
            path=PORTAL_OBJECT_PATH,
            interface="org.freedesktop.DBus.Properties",
            member="Get",
            signature="ss",
            body=[SCREENSHOT_INTERFACE, "version"],
        )
        return int(body[0].value)

    async def watch_response(self, request_path: str) -> asyncio.Future:
        future = self._pending.get(request_path)
        if future is None:
            future = asyncio.get_running_loop().create_future()
            self._pending[request_path] = future
            await self._call(
                destination="org.freedesktop.DBus",
                path="/org/freedesktop/DBus",
                interface="org.freedesktop.DBus",
                member="AddMatch",
                signature="s",
                body=[
                    "type='signal',"
                    f"sender='{PORTAL_BUS_NAME}',"
                    f"interface='{REQUEST_INTERFACE}',"
                    "member='Response',"
                    f"path='{request_path}'"
                ],
            )
            early = self._early.pop(request_path, None)
            if early is not None:
                future.set_result(early)
        return future

    async def screenshot(self, token: str, *, interactive: bool) -> str:
        from dbus_fast import Variant

        body = await self._call(
            destination=PORTAL_BUS_NAME,
            path=PORTAL_OBJECT_PATH,
            interface=SCREENSHOT_INTERFACE,
            member="Screenshot",
            signature="sa{sv}",
            body=[
                "",
                {
                    "handle_token": Variant("s", token),
                    "interactive": Variant("b", interactive),
                },
            ],
        )
        return str(body[0])


@dataclass(frozen=True)
class CaptureOptions:
    interactive: bool = True
    app_id: str | None = None


def parse_options(argv: list[str]) -> CaptureOptions:
    parser = argparse.ArgumentParser(prog="worker.portal_capture")
    parser.add_argument(
        "--silent",
        action="store_true",
        help="non-interactive capture of all displays; needs a stored grant",
    )
    parser.add_argument(
        "--app-id",
        help="register this desktop app ID first; its desktop file must exist",
    )
    args = parser.parse_args(argv)
    return CaptureOptions(interactive=not args.silent, app_id=args.app_id)


async def _run(
    options: CaptureOptions,
    connect: Callable[[], Awaitable[Any]] | None = None,
) -> CaptureOutcome:
    try:
        bus = await (connect or _connect_session_bus)()
    except Exception:  # noqa: BLE001 - no session bus means no portal.
        _log("session bus unavailable")
        return CaptureOutcome("unavailable")
    try:
        return await capture(
            DbusFastPortalClient(bus),
            interactive=options.interactive,
            app_id=options.app_id,
        )
    finally:
        bus.disconnect()


async def _connect_session_bus() -> Any:
    from dbus_fast import BusType
    from dbus_fast.aio import MessageBus

    return await MessageBus(bus_type=BusType.SESSION).connect()


def _log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def main(argv: list[str] | None = None) -> None:
    options = parse_options(sys.argv[1:] if argv is None else argv)
    try:
        outcome = asyncio.run(_run(options))
    except Exception:  # noqa: BLE001 - final process boundary.
        _log("capture failed")
        outcome = CaptureOutcome("failed")
    _log(f"capture {outcome.outcome}")
    sys.stdout.write(outcome.to_json() + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
