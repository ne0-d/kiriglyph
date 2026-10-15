#!/usr/bin/python3
"""Throwaway spike for issue 16: silent portal capture and fullscreen placement.

Run with the system interpreter (/usr/bin/python3, PyGObject). Every
subcommand writes a JSON result to /tmp/live-text-spike/. Screen content is
only ever written under /tmp, never into the repository.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import statistics
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_foreign("cairo")

import cairo  # noqa: E402
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

APP_ID = "dev.livetext.CaptureSpike"
SCRIPT = Path(__file__).resolve()
DESKTOP_FILE = Path.home() / ".local/share/applications" / f"{APP_ID}.desktop"
OUT_DIR = Path("/tmp/live-text-spike")

PORTAL_BUS = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
REGISTRY_IFACE = "org.freedesktop.host.portal.Registry"
SCREENSHOT_IFACE = "org.freedesktop.portal.Screenshot"
REQUEST_IFACE = "org.freedesktop.portal.Request"
STORE_BUS = "org.freedesktop.impl.portal.PermissionStore"
STORE_PATH = "/org/freedesktop/impl/portal/PermissionStore"
STORE_IFACE = "org.freedesktop.impl.portal.PermissionStore"
MUTTER_BUS = "org.gnome.Mutter.DisplayConfig"
MUTTER_PATH = "/org/gnome/Mutter/DisplayConfig"

DESKTOP_ENTRY = f"""[Desktop Entry]
Type=Application
Name=Live Text Capture Spike
Comment=Throwaway prototype for Ubuntu Live Text issue 16
Exec=/usr/bin/python3 "{SCRIPT}" grant
Icon=applets-screenshooter-symbolic
Terminal=false
StartupNotify=false
StartupWMClass={APP_ID}
"""


# ---------------------------------------------------------------- utilities


def write_result(name: str, payload: dict, label: str | None = None) -> Path:
    OUT_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    payload = {"subcommand": name, "label": label, "timestamp": stamp, **payload}
    stem = f"{name}-{label}" if label else name
    text = json.dumps(payload, indent=2, default=str)
    path = OUT_DIR / f"{stem}-{stamp}.json"
    path.write_text(text)
    (OUT_DIR / f"{stem}-latest.json").write_text(text)
    print(text)
    print(f"\nresult written to {path}", file=sys.stderr)
    return path


def dbus_error(error: GLib.Error) -> dict:
    name = Gio.DBusError.get_remote_error(error)
    Gio.DBusError.strip_remote_error(error)
    return {"remote_error": name, "message": error.message}


def session_bus() -> Gio.DBusConnection:
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def private_bus() -> Gio.DBusConnection:
    """A fresh connection, so the portal has never seen this unique name."""
    address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
    flags = (
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
        | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
    )
    return Gio.DBusConnection.new_for_address_sync(address, flags, None, None)


def call(conn, bus, path, iface, method, params=None, reply=None, timeout_ms=10000):
    result = conn.call_sync(
        bus, path, iface, method, params,
        GLib.VariantType.new(reply) if reply else None,
        Gio.DBusCallFlags.NONE, timeout_ms, None,
    )
    return result.unpack() if result is not None else None


def register(conn) -> dict:
    try:
        call(conn, PORTAL_BUS, PORTAL_PATH, REGISTRY_IFACE, "Register",
             GLib.Variant("(sa{sv})", (APP_ID, {})))
        return {"ok": True}
    except GLib.Error as error:
        return {"ok": False, **dbus_error(error)}


def permission_lookup() -> dict:
    try:
        perms, _data = call(session_bus(), STORE_BUS, STORE_PATH, STORE_IFACE,
                            "Lookup", GLib.Variant("(ss)", ("screenshot", "screenshot")))
    except GLib.Error as error:
        return {"table_entry": None, **dbus_error(error)}
    return {
        "table_entry": {app or "<empty app id>": list(v) for app, v in perms.items()},
        "spike_app": perms.get(APP_ID),
        "empty_id_present": "" in perms,
    }


def pictures_dir() -> Path:
    special = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
    return Path(special) if special else Path.home() / "Pictures"


def pictures_snapshot(limit: int = 20000) -> dict:
    root = pictures_dir()
    entries: dict[str, tuple[int, int]] = {}
    stack = [root]
    while stack and len(entries) < limit:
        try:
            with os.scandir(stack.pop()) as it:
                for entry in it:
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(Path(entry.path))
                    else:
                        st = entry.stat(follow_symlinks=False)
                        entries[os.path.relpath(entry.path, root)] = (st.st_size, st.st_mtime_ns)
        except OSError:
            continue
    return entries


def pictures_diff(before: dict, after: dict) -> dict:
    added = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    changed = sorted(k for k in set(before) & set(after) if before[k] != after[k])
    return {
        "unchanged": not (added or removed or changed),
        "added": added[:20], "removed": removed[:20], "changed": changed[:20],
    }


def path_from_uri(uri) -> str | None:
    if not isinstance(uri, str):
        return None
    parsed = urlparse(uri)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
        return None
    return unquote(parsed.path)


def delete_returned_file(path: str | None, started_wall: float) -> dict:
    """Delete exactly the file the portal returned, with sanity guards."""
    if not path:
        return {"deleted": False, "reason": "no path"}
    p = Path(path)
    if not p.is_file() or p.is_symlink():
        return {"deleted": False, "reason": "not a regular file"}
    if p.stat().st_mtime < started_wall - 2:
        return {"deleted": False, "reason": "file predates the request; left untouched"}
    p.unlink()
    return {"deleted": True, "gone": not p.exists(), "name": p.name}


def require_grant() -> None:
    state = permission_lookup()
    if state.get("spike_app") != ["yes"]:
        sys.exit(f"No 'yes' grant stored for {APP_ID} (found {state}). Run `grant` first.")


# ------------------------------------------------------------ portal capture


class Capture:
    """One non-interactive Screenshot request on a registered connection."""

    def __init__(self, conn, on_done, timeout_s: int = 120, parent_window: str = ""):
        self.conn = conn
        self.on_done = on_done
        self.timeout_s = timeout_s
        self.parent_window = parent_window
        self.subs: list[int] = []
        self.finished = False

    def start(self) -> None:
        token = f"spike_{secrets.token_hex(8)}"
        sender = self.conn.get_unique_name().removeprefix(":").replace(".", "_")
        self.predicted = f"{PORTAL_PATH}/request/{sender}/{token}"
        self._watch(self.predicted)
        self.started_wall = time.time()
        self.t0 = time.monotonic()
        self.timer = GLib.timeout_add_seconds(self.timeout_s, self._on_timeout)
        options = {
            "handle_token": GLib.Variant("s", token),
            "interactive": GLib.Variant("b", False),
        }
        self.conn.call(
            PORTAL_BUS, PORTAL_PATH, SCREENSHOT_IFACE, "Screenshot",
            GLib.Variant("(sa{sv})", (self.parent_window, options)),
            GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, -1, None,
            self._on_handle,
        )

    def _watch(self, path: str) -> None:
        self.subs.append(self.conn.signal_subscribe(
            None, REQUEST_IFACE, "Response", path, None,
            Gio.DBusSignalFlags.NONE, self._on_response))

    def _on_handle(self, conn, res) -> None:
        try:
            (handle,) = conn.call_finish(res).unpack()
        except GLib.Error as error:
            self._finish({"outcome": "call_error", **dbus_error(error)})
            return
        self.handle_ms = (time.monotonic() - self.t0) * 1000
        if handle != self.predicted:
            self._watch(handle)

    def _on_response(self, _conn, _sender, _path, _iface, _signal, params) -> None:
        code, results = params.unpack()
        latency_ms = (time.monotonic() - self.t0) * 1000
        outcome = {0: "captured", 1: "cancelled", 2: "ended"}.get(code, "failed")
        self._finish({
            "outcome": outcome, "response_code": code, "latency_ms": round(latency_ms, 1),
            "path": path_from_uri(results.get("uri")),
        })

    def _on_timeout(self) -> bool:
        self._finish({"outcome": "timeout"})
        return False

    def _finish(self, result: dict) -> None:
        if self.finished:
            return
        self.finished = True
        for sub in self.subs:
            self.conn.signal_unsubscribe(sub)
        if result.get("outcome") != "timeout":
            GLib.source_remove(self.timer)
        result["started_wall"] = self.started_wall
        self.on_done(result)


def capture_sync(conn, timeout_s: int = 30) -> dict:
    loop = GLib.MainLoop()
    box: dict = {}

    def done(result):
        box.update(result)
        loop.quit()

    Capture(conn, done, timeout_s).start()
    loop.run()
    return box


def image_info(path: str | None) -> dict:
    if not path:
        return {}
    try:
        fmt, width, height = GdkPixbuf.Pixbuf.get_file_info(path)
        return {"format": fmt.get_name() if fmt else None, "width": width, "height": height}
    except GLib.Error as error:
        return {"error": error.message}


# ------------------------------------------------------------ display layout


def display_state() -> dict:
    serial, monitors, logical, props = call(
        session_bus(), MUTTER_BUS, MUTTER_PATH, MUTTER_BUS, "GetCurrentState")
    phys = {}
    for (connector, vendor, product, _serial), modes, mprops in monitors:
        current = next((m for m in modes if m[6].get("is-current")), None)
        phys[connector] = {
            "vendor": vendor, "product": product,
            "display_name": mprops.get("display-name"),
            "builtin": mprops.get("is-builtin"),
            "mode_px": [current[1], current[2]] if current else None,
            "refresh": current[3] if current else None,
            "supported_scales": [round(s, 4) for s in current[5]] if current else None,
        }
    layout_mode = props.get("layout-mode")
    logical_out = []
    for x, y, scale, transform, primary, specs, _lprops in logical:
        connectors = [spec[0] for spec in specs]
        mode = phys.get(connectors[0], {}).get("mode_px") if connectors else None
        size = None
        if mode:
            w, h = mode if transform % 2 == 0 else mode[::-1]
            size = [round(w / scale), round(h / scale)] if layout_mode == 1 else [w, h]
        logical_out.append({
            "connectors": connectors, "x": x, "y": y, "scale": round(scale, 6),
            "transform": transform, "primary": primary,
            "logical_size_derived": size,
        })
    return {
        "serial": serial,
        "layout_mode": {1: "logical", 2: "physical"}.get(layout_mode, layout_mode),
        "global_scale_required": props.get("global-scale-required"),
        "monitors": phys, "logical_monitors": logical_out,
    }


# --------------------------------------------------------------- subcommands


def cmd_install(_args) -> None:
    DESKTOP_FILE.parent.mkdir(parents=True, exist_ok=True)
    DESKTOP_FILE.write_text(DESKTOP_ENTRY)
    write_result("install", {"desktop_file": str(DESKTOP_FILE),
                             "gio_finds_it": _desktop_visible()})


def cmd_uninstall(_args) -> None:
    removed = DESKTOP_FILE.exists()
    DESKTOP_FILE.unlink(missing_ok=True)
    try:
        call(session_bus(), STORE_BUS, STORE_PATH, STORE_IFACE, "DeletePermission",
             GLib.Variant("(sss)", ("screenshot", "screenshot", APP_ID)))
        deleted = {"ok": True}
    except GLib.Error as error:
        deleted = {"ok": False, **dbus_error(error)}
    write_result("uninstall", {"desktop_file_removed": removed,
                               "delete_permission": deleted,
                               "permission_after": permission_lookup()})


def _desktop_visible() -> bool:
    try:
        gi.require_version("GioUnix", "2.0")
        from gi.repository import GioUnix as unix
    except (ValueError, ImportError):
        unix = Gio
    return unix.DesktopAppInfo.new(f"{APP_ID}.desktop") is not None


def cmd_lookup(_args) -> None:
    write_result("lookup", permission_lookup())


def cmd_display_state(_args) -> None:
    write_result("display-state", display_state())


def cmd_register_check(_args) -> None:
    """Registry ordering experiments; never calls Screenshot."""
    checks = {"desktop_file_present": DESKTOP_FILE.exists()}

    conn = private_bus()
    checks["register_first"] = register(conn)
    checks["register_again_same_conn"] = register(conn)
    conn.close_sync(None)

    conn = private_bus()
    try:
        (checks["screenshot_version"],) = call(
            conn, PORTAL_BUS, PORTAL_PATH, "org.freedesktop.DBus.Properties",
            "Get", GLib.Variant("(ss)", (SCREENSHOT_IFACE, "version")))
    except GLib.Error as error:
        checks["screenshot_version"] = dbus_error(error)
    checks["register_after_property_get"] = register(conn)
    conn.close_sync(None)

    conn = private_bus()
    try:
        call(conn, PORTAL_BUS, PORTAL_PATH, "org.freedesktop.portal.Settings", "ReadOne",
             GLib.Variant("(ss)", ("org.freedesktop.appearance", "color-scheme")))
        checks["settings_read"] = {"ok": True}
    except GLib.Error as error:
        checks["settings_read"] = dbus_error(error)
    checks["register_after_portal_method"] = register(conn)
    conn.close_sync(None)

    write_result("register-check", checks)


def cmd_grant(args) -> None:
    before = permission_lookup()
    GLib.set_prgname(APP_ID)
    app = Gtk.Application(application_id=APP_ID)
    state: dict = {"permission_before": before}

    def on_activate(app):
        win = Gtk.ApplicationWindow(application=app, title="Live Text capture spike")
        win.set_default_size(460, 180)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        label = Gtk.Label(wrap=True, xalign=0)
        label.set_text(
            "Click the button. GNOME should ask whether 'Live Text Capture Spike' may "
            "take screenshots. Choose Allow.")
        if before.get("spike_app"):
            label.set_text(f"A grant already exists for {APP_ID}: {before['spike_app']}. "
                           "Run `uninstall` then `install` to start over.")
        button = Gtk.Button(label="Request screenshot permission")
        box.pack_start(label, True, True, 0)
        box.pack_start(button, False, False, 0)
        win.add(box)

        def on_done(result):
            path = result.pop("path", None)
            result["image"] = image_info(path)
            result["file"] = delete_returned_file(path, result.pop("started_wall"))
            state["capture"] = result
            state["permission_after"] = permission_lookup()
            write_result("grant", state)
            label.set_text(f"Outcome: {result['outcome']}. Stored grant: "
                           f"{state['permission_after'].get('spike_app')}. "
                           "Closing in 4 seconds.")
            GLib.timeout_add_seconds(4, lambda: app.quit() or False)

        def on_click(_button):
            button.set_sensitive(False)
            conn = private_bus()
            state["conn"] = conn
            state["register"] = register(conn)
            if not state["register"]["ok"]:
                on_done({"outcome": "register_failed", "started_wall": time.time()})
                return
            label.set_text("Waiting for GNOME's access dialog...")
            Capture(conn, on_done, timeout_s=args.timeout).start()

        button.connect("clicked", on_click)
        win.show_all()

    app.connect("activate", on_activate)
    app.run([sys.argv[0]])
    state.pop("conn", None)


def cmd_measure(args) -> None:
    require_grant()
    print(f"Watch the screen and listen. {args.count} captures start in 3 seconds, "
          f"{args.interval}s apart.", flush=True)
    time.sleep(3)
    before = pictures_snapshot()
    conn = private_bus()
    reg = register(conn)
    if not reg["ok"]:
        write_result("measure", {"register": reg})
        return
    runs = []
    for i in range(args.count):
        result = capture_sync(conn)
        path = result.pop("path", None)
        result["image"] = image_info(path)
        result["file"] = delete_returned_file(path, result.pop("started_wall"))
        runs.append(result)
        print(f"capture {i + 1}: {result['outcome']} {result.get('latency_ms')} ms", flush=True)
        time.sleep(args.interval)
    latencies = [r["latency_ms"] for r in runs if r["outcome"] == "captured"]
    summary = {
        "successes": len(latencies),
        "median_ms": statistics.median(latencies) if latencies else None,
        "min_ms": min(latencies) if latencies else None,
        "max_ms": max(latencies) if latencies else None,
        "all_deleted": all(r["file"].get("gone") for r in runs),
        "image_sizes": sorted({(r["image"].get("width"), r["image"].get("height")) for r in runs}),
    }
    pics = pictures_diff(before, pictures_snapshot())
    flash = _ask("Did you see the screen flash or dim during the captures? [y/n/unsure] ")
    sound = _ask("Did you hear a shutter sound? [y/n/unsure] ")
    write_result("measure", {"register": reg, "summary": summary, "pictures": pics,
                             "user_saw_flash": flash, "user_heard_sound": sound,
                             "runs": runs}, args.label)


def _ask(prompt: str) -> str | None:
    if not sys.stdin.isatty():
        return None
    try:
        return input(prompt).strip().lower() or None
    except EOFError:
        return None


# ------------------------------------------------------------------- place


def crop_rect(gtk_monitors: list[dict], target: dict, image_w: int, image_h: int) -> dict:
    """Map a logical monitor rectangle into the spanning screenshot's pixels.

    GNOME Shell sizes the image as round(stage_logical * max_view_scale)
    (clutter_stage_get_capture_final_size), so every display is rendered at
    the largest scale present, not its own scale.
    """
    x0 = min(m["x"] for m in gtk_monitors)
    y0 = min(m["y"] for m in gtk_monitors)
    x1 = max(m["x"] + m["width"] for m in gtk_monitors)
    y1 = max(m["y"] + m["height"] for m in gtk_monitors)
    sx = image_w / (x1 - x0)
    sy = image_h / (y1 - y0)
    exact = {
        "x": (target["x"] - x0) * sx, "y": (target["y"] - y0) * sy,
        "width": target["width"] * sx, "height": target["height"] * sy,
    }
    return {
        "stage_logical": [x1 - x0, y1 - y0],
        "image_scale": [round(sx, 6), round(sy, 6)],
        "exact": {k: round(v, 3) for k, v in exact.items()},
        "rect": {k: int(round(v)) for k, v in exact.items()},
    }


def pixbuf_surface(pixbuf) -> cairo.ImageSurface:
    surface = cairo.ImageSurface(cairo.FORMAT_RGB24, pixbuf.get_width(), pixbuf.get_height())
    cr = cairo.Context(surface)
    Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
    cr.set_operator(cairo.OPERATOR_SOURCE)
    cr.paint()
    surface.flush()
    return surface


def compare_and_save(crop, shown, out: Path) -> dict:
    """Save crop, displayed, side-by-side and amplified diff; return statistics."""
    w, h = crop.get_width(), crop.get_height()
    if (shown.get_width(), shown.get_height()) != (w, h):
        return {"comparable": False, "reason": "size mismatch"}
    a, b = pixbuf_surface(crop), pixbuf_surface(shown)
    a.write_to_png(str(out / "crop.png"))
    b.write_to_png(str(out / "displayed.png"))

    side = cairo.ImageSurface(cairo.FORMAT_RGB24, w * 2, h)
    cr = cairo.Context(side)
    cr.set_source_surface(a, 0, 0)
    cr.paint()
    cr.set_source_surface(b, w, 0)
    cr.paint()
    side.write_to_png(str(out / "side-by-side.png"))

    diff = cairo.ImageSurface(cairo.FORMAT_RGB24, w, h)
    cr = cairo.Context(diff)
    cr.set_source_surface(a, 0, 0)
    cr.set_operator(cairo.OPERATOR_SOURCE)
    cr.paint()
    cr.set_source_surface(b, 0, 0)
    cr.set_operator(cairo.OPERATOR_DIFFERENCE)
    cr.paint()
    diff.flush()
    data = bytes(diff.get_data())
    channels = [data[i::4] for i in range(3)]  # BGRx on little-endian
    total = 3 * w * h
    nonzero = sum(len(c) - c.count(0) for c in channels)
    over8 = sum(len(c) - c.translate(bytes(min(v, 9) // 9 for v in range(256))).count(0)
                for c in channels)
    amplified = bytearray(data.translate(bytes(min(255, v * 8) for v in range(256))))
    cairo.ImageSurface.create_for_data(
        amplified, cairo.FORMAT_RGB24, w, h, diff.get_stride()
    ).write_to_png(str(out / "diff-x8.png"))
    return {
        "comparable": True,
        "pixel_identical": nonzero == 0,
        "max_channel_diff": max(max(c) for c in channels),
        "mean_abs_channel_diff": round(sum(sum(c) for c in channels) / total, 4),
        "fraction_channels_differing": round(nonzero / total, 6),
        "fraction_channels_diff_gt8": round(over8 / total, 6),
        "files": sorted(p.name for p in out.iterdir()),
    }


class Placement:
    def __init__(self, app: Gtk.Application, args):
        self.app = app
        self.args = args
        self.conn = private_bus()
        self.result: dict = {
            "pointer_on_declared": args.pointer_on,
            "fullscreen_on_monitor_arg": args.monitor,
            "filter": args.filter,
            "pictures_before": pictures_snapshot(),
        }
        self.crop = None
        self.pixbuf = None
        self.t_mapped = None
        self.analyzed = False
        self.written = False
        self.out = OUT_DIR / f"place-{args.label or 'run'}-{time.strftime('%Y%m%d-%H%M%S')}"

    def start(self) -> None:
        self.app.hold()
        self.result["display_state"] = display_state()
        self.result["register"] = register(self.conn)
        if not self.result["register"]["ok"]:
            self.finish()
            return
        Capture(self.conn, self.on_first_capture, timeout_s=30).start()

    def on_first_capture(self, result: dict) -> None:
        path = result.pop("path", None)
        if result["outcome"] == "captured" and path:
            self.pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
        result["file"] = delete_returned_file(path, result.pop("started_wall"))
        self.result["first_capture"] = result
        if self.pixbuf is None:
            self.finish()
            return
        self.result["image_px"] = [self.pixbuf.get_width(), self.pixbuf.get_height()]
        self.show_window()
        self.app.release()

    def show_window(self) -> None:
        win = Gtk.ApplicationWindow(application=self.app, title="Live Text placement spike")
        self.win = win
        win.set_decorated(False)
        visual = win.get_screen().get_rgba_visual()
        if visual is not None:
            win.set_visual(visual)
        win.set_app_paintable(True)
        win.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.ENTER_NOTIFY_MASK
                       | Gdk.EventMask.KEY_PRESS_MASK)
        win.connect("draw", self.on_draw)
        win.connect("window-state-event", self.on_state)
        win.connect("key-press-event", self.on_key)
        win.connect("enter-notify-event", self.on_pointer)
        win.connect("motion-notify-event", self.on_pointer)
        win.connect("destroy", lambda *_: self.finish())
        if self.args.monitor is not None:
            win.fullscreen_on_monitor(win.get_screen(), self.args.monitor)
        else:
            win.fullscreen()
        win.show_all()
        self.t_shown = time.monotonic()
        GLib.timeout_add_seconds(self.args.timeout, self.close)

    def on_pointer(self, _win, event) -> bool:
        self.result.setdefault("pointer_entered_window", {
            "event": event.type.value_nick,
            "window_xy": [round(event.x, 1), round(event.y, 1)],
        })
        return False

    def on_key(self, _win, event) -> bool:
        if event.keyval == Gdk.KEY_Escape:
            self.close()
        return True

    def on_state(self, _win, event) -> bool:
        if event.new_window_state & Gdk.WindowState.FULLSCREEN and not self.analyzed:
            self.analyzed = True
            self.result["ms_show_to_fullscreen"] = round((time.monotonic() - self.t_shown) * 1000)
            GLib.timeout_add(300, self.analyze)
        return False

    def analyze(self) -> bool:
        display = Gdk.Display.get_default()
        gdk_win = self.win.get_window()
        placed = display.get_monitor_at_window(gdk_win)
        monitors = []
        for i in range(display.get_n_monitors()):
            m = display.get_monitor(i)
            g = m.get_geometry()
            monitors.append({
                "index": i, "x": g.x, "y": g.y, "width": g.width, "height": g.height,
                "gtk_scale_factor": m.get_scale_factor(), "model": m.get_model(),
                "manufacturer": m.get_manufacturer(), "primary": m.is_primary(),
                "is_placed": m == placed,
            })
        target = next(m for m in monitors if m["is_placed"])
        logical = self.result["display_state"]["logical_monitors"]
        mutter = next((lm for lm in logical if (lm["x"], lm["y"]) == (target["x"], target["y"])),
                      None)
        connector = mutter["connectors"][0] if mutter else None
        mode_px = self.result["display_state"]["monitors"].get(connector, {}).get("mode_px")

        geo = crop_rect(monitors, target, *self.result["image_px"])
        r = geo["rect"]
        self.crop = self.pixbuf.new_subpixbuf(r["x"], r["y"], r["width"], r["height"]).copy()
        self.pixbuf = None

        alloc = [self.win.get_allocated_width(), self.win.get_allocated_height()]
        s = self.win.get_scale_factor()
        buffer_px = [alloc[0] * s, alloc[1] * s]
        crop_px = [r["width"], r["height"]]
        frac = mutter["scale"] if mutter else None
        self.result.update({
            "gtk_monitors": monitors,
            "placed_monitor": {**target, "connector": connector,
                               "mutter_scale": frac, "physical_mode_px": mode_px},
            "pointer_matches_placement": (self.args.pointer_on == connector
                                          if self.args.pointer_on else None),
            "crop": geo,
            "window": {"allocation_logical": alloc, "gtk_scale_factor": s,
                       "buffer_px": buffer_px},
            "scale_report": {
                "crop_px": crop_px,
                "crop_equals_physical_mode": crop_px == mode_px,
                "crop_equals_gtk_buffer": crop_px == buffer_px,
                "gtk_buffer_equals_physical_mode": buffer_px == mode_px,
                "compositor_rescales_buffer": (frac is not None and abs(s - frac) > 1e-6),
                "draw_mode": "1:1 into buffer" if crop_px == buffer_px else
                             f"resampled ({self.args.filter}) to fill window",
            },
        })
        self.win.queue_draw()
        GLib.timeout_add(1200, self.second_capture)
        return False

    def on_draw(self, widget, cr) -> bool:
        cr.set_operator(cairo.OPERATOR_SOURCE)
        if self.crop is None:
            cr.set_source_rgba(0, 0, 0, 0)
            cr.paint()
            return True
        s = widget.get_scale_factor()
        lw, lh = widget.get_allocated_width(), widget.get_allocated_height()
        cw, ch = self.crop.get_width(), self.crop.get_height()
        if (cw, ch) == (lw * s, lh * s):
            cr.scale(1 / s, 1 / s)
        else:
            cr.scale(lw / cw, lh / ch)
        Gdk.cairo_set_source_pixbuf(cr, self.crop, 0, 0)
        cr.get_source().set_filter(
            cairo.FILTER_NEAREST if self.args.filter == "nearest" else cairo.FILTER_GOOD)
        cr.paint()
        if "ms_show_to_first_crop_draw" not in self.result:
            self.result["ms_show_to_first_crop_draw"] = round(
                (time.monotonic() - self.t_shown) * 1000)
        return True

    def second_capture(self) -> bool:
        Capture(self.conn, self.on_second_capture, timeout_s=30).start()
        return False

    def on_second_capture(self, result: dict) -> None:
        path = result.pop("path", None)
        shown = None
        if result["outcome"] == "captured" and path:
            full = GdkPixbuf.Pixbuf.new_from_file(path)
            r = self.result["crop"]["rect"]
            if [full.get_width(), full.get_height()] == self.result["image_px"]:
                shown = full.new_subpixbuf(r["x"], r["y"], r["width"], r["height"]).copy()
        result["file"] = delete_returned_file(path, result.pop("started_wall"))
        self.result["second_capture"] = result
        if shown is not None:
            self.out.mkdir(mode=0o700, parents=True, exist_ok=True)
            self.result["comparison"] = compare_and_save(self.crop, shown, self.out)
            self.result["comparison"]["dir"] = str(self.out)
        print("Comparison captured. Press Escape (or wait) to close.", flush=True)

    def close(self) -> bool:
        if getattr(self, "win", None) is not None:
            win, self.win = self.win, None
            win.destroy()
        return False

    def finish(self) -> None:
        if self.written:
            return
        self.written = True
        before = self.result.pop("pictures_before")
        self.result["pictures"] = pictures_diff(before, pictures_snapshot())
        write_result("place", self.result, self.args.label)
        self.app.quit()


def cmd_place(args) -> None:
    require_grant()
    if args.pointer_on is None and sys.stdin.isatty():
        args.pointer_on = _ask("Connector the pointer will be on (e.g. HDMI-1, eDP-1): ")
        if args.pointer_on:
            args.pointer_on = {c.lower(): c for c in ("HDMI-1", "eDP-1")}.get(
                args.pointer_on.lower(), args.pointer_on)
    print("Move the pointer onto that display now and keep it still. "
          "Capturing in 3 seconds...", flush=True)
    time.sleep(3)
    GLib.set_prgname(APP_ID)
    app = Gtk.Application(application_id=APP_ID)
    placement = Placement(app, args)
    app.connect("activate", lambda _app: placement.start())
    app.run([sys.argv[0]])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("install", help="write the spike desktop file")
    sub.add_parser("uninstall", help="remove desktop file and the spike's screenshot grant")
    sub.add_parser("lookup", help="print the screenshot permission-store entry")
    sub.add_parser("display-state", help="print Mutter's current logical layout")
    sub.add_parser("register-check", help="Registry.Register ordering checks (no capture)")
    p = sub.add_parser("grant", help="[interactive] focused window triggers GNOME's dialog")
    p.add_argument("--timeout", type=int, default=120)
    p = sub.add_parser("measure", help="[user-run] 10 silent captures, latency, cleanup")
    p.add_argument("--count", type=int, default=10)
    p.add_argument("--interval", type=float, default=1.0)
    p.add_argument("--label")
    p = sub.add_parser("place", help="[user-run] capture, then fullscreen frozen frame")
    p.add_argument("--label", help="e.g. hdmi-100, edp-125")
    p.add_argument("--pointer-on", help="connector the pointer is on, e.g. HDMI-1")
    p.add_argument("--monitor", type=int, help="use fullscreen_on_monitor with this GTK index")
    p.add_argument("--filter", choices=("nearest", "good"), default="nearest")
    p.add_argument("--timeout", type=int, default=20)
    args = parser.parse_args()
    {
        "install": cmd_install, "uninstall": cmd_uninstall, "lookup": cmd_lookup,
        "display-state": cmd_display_state, "register-check": cmd_register_check,
        "grant": cmd_grant, "measure": cmd_measure, "place": cmd_place,
    }[args.cmd](args)


if __name__ == "__main__":
    main()
