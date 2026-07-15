# Ubuntu 24.04 GNOME Wayland capture and overlay research

Target: Ubuntu 24.04 LTS, GNOME on Wayland  
Ticket: [01-wayland-capture-overlay](../issues/01-wayland-capture-overlay.md)

Primary sources are used throughout. “System-wide” below means desktop-global within the active logged-in user session; none of these mechanisms is an appropriate integration point for GDM, another user’s session, or the lock screen.

## Executive conclusion

The supported V1 path is:

1. Ask the user to create a **GNOME Custom Shortcut** that launches a stable application command.
2. On invocation, call `org.freedesktop.portal.Screenshot.Screenshot` with `interactive=true`.
3. Let GNOME Shell provide its native frozen-frame, full-stage selector for area, screen, or window capture.
4. OCR the returned image URI, present the result in an ordinary application surface, and place chosen text on the clipboard with `GdkClipboard` after the user’s selection/copy action.

This path is the least privileged and the most native on Ubuntu 24.04. It avoids private Shell/Mutter D-Bus APIs, handles compositor-owned screen content through the portal, and leaves monitor and fractional-scale selection to GNOME Shell.

A custom frozen-frame overlay is technically possible as a second-tier path: request monitor/window streams with the ScreenCast portal, read and freeze the first PipeWire frames, close the capture session, then paint those frames into one GTK fullscreen window per monitor. It is materially more complex and cannot be made into a guaranteed Shell-level overlay: Wayland gives an ordinary client no standard always-on-top layer, no absolute global placement, and no right to seize focus. `wlr-layer-shell` is not available in Mutter.

The principal target-specific blocker is global invocation. Ubuntu 24.04 ships the Global Shortcuts portal frontend API, but its GNOME 46 backend does not implement that portal. GNOME added the backend in GNOME 48, not in the GNOME 46 line used by Ubuntu 24.04.

## Target baseline

Ubuntu 24.04’s relevant upstream lines are:

- `xdg-desktop-portal` **1.18.4**;
- `xdg-desktop-portal-gnome` **46.2** (46.0 in the original release);
- GNOME Shell **46.0**;
- Mutter **46.2**;
- PipeWire **1.0.5**;
- GTK **4.14**.

The Ubuntu revisions continue receiving fixes, but these upstream major/minor lines determine the API set discussed here. Sources: [Ubuntu Noble xdg-desktop-portal](https://launchpad.net/ubuntu/noble/+source/xdg-desktop-portal), [xdg-desktop-portal-gnome](https://launchpad.net/ubuntu/noble/+source/xdg-desktop-portal-gnome), [GNOME Shell](https://launchpad.net/ubuntu/noble/+source/gnome-shell), [Mutter](https://launchpad.net/ubuntu/noble/+source/mutter), [PipeWire](https://launchpad.net/ubuntu/noble/+source/pipewire), and [GTK 4](https://launchpad.net/ubuntu/noble/+source/gtk4).

Two version distinctions matter:

- Ubuntu’s Screenshot portal is interface **version 2**. It supports `interactive`, but not the version-3 `target` option or `AvailableTargets`. Therefore this target cannot request “open directly in Area mode” through the standard API; it can request GNOME’s interactive chooser and let the user choose Area, Window, or Screen. Sources: [1.18.4 Screenshot interface XML](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.Screenshot.xml), [GNOME 46 backend exporting version 2](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screenshot.c), and [current version-3 specification for contrast](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Screenshot.html).
- Ubuntu’s ScreenCast portal is interface **version 5**. It has restore tokens, persistence, `mapping_id`, compositor-space position/size metadata, and monitor/window/virtual sources, but not version-6 `pipewire-serial`. Sources: [1.18.4 ScreenCast interface XML](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.ScreenCast.xml) and [GNOME 46 ScreenCast backend](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screencast.c).

## Capability findings

### 1. Explicit global invocation

#### Standards-supported API, unavailable on this target

`org.freedesktop.portal.GlobalShortcuts` is the correct cross-desktop API. It creates an application-bound session, asks the user to bind shortcuts, and emits `Activated`/`Deactivated` even while the application is unfocused. `preferred_trigger` is only a preference; the user-facing portal controls the actual binding. Source: [xdg-desktop-portal 1.18.4 GlobalShortcuts interface](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.GlobalShortcuts.xml).

It does **not** work with Ubuntu 24.04’s GNOME backend. The GNOME 46 backend manifest enumerates its implemented portal interfaces and omits `org.freedesktop.impl.portal.GlobalShortcuts`; GNOME 48 release notes explicitly record “Add global shortcuts portal backend.” The frontend API being present in `xdg-desktop-portal` is insufficient when the desktop backend does not implement it. Sources: [GNOME 46 backend interface manifest](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/data/meson.build) and [GNOME 48 NEWS](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-48/NEWS).

Recommendation: probe the portal at runtime for future desktops, but do not make it the Ubuntu 24.04 invocation path.

#### Supported GNOME user integration

GNOME Settings officially supports a user-created custom shortcut consisting of a name, command, and chosen accelerator. This is explicit consent, resolves the missing portal backend, and launches on demand instead of requiring a permanently privileged input listener. Ship a stable command and document a suggested accelerator; do not silently write GNOME’s internal GSettings keys. Source: [GNOME Help — Set keyboard shortcuts, “Custom shortcuts”](https://help.gnome.org/users/gnome-help/stable/keyboard-shortcuts-set.html.en).

The shortcut is per user and per desktop session. It should invoke a single-instance application/service command so repeated presses activate the existing process rather than start overlapping capture flows.

#### Private GNOME D-Bus path, unusable by an application

GNOME Shell 46 still exposes `GrabAccelerator(s)` methods in `org.gnome.Shell`, but its implementation checks the caller against an allowlist containing only `org.gnome.Settings` and `org.gnome.SettingsDaemon.MediaKeys`. A third-party OCR application will be rejected. GNOME maintainers also describe these Shell D-Bus APIs as platform-private rather than application APIs. Sources: [GNOME Shell 46 `shellDBus.js`](https://gitlab.gnome.org/GNOME/gnome-shell/-/raw/gnome-46/js/ui/shellDBus.js), [interface XML](https://gitlab.gnome.org/GNOME/gnome-shell/-/raw/gnome-46/data/dbus-interfaces/org.gnome.Shell.xml), and [GNOME restriction rationale](https://gitlab.gnome.org/GNOME/gnome-shell/-/merge_requests/1970).

An ordinary Wayland client cannot implement a fallback by listening to all keyboard events: keyboard delivery follows compositor focus and Wayland has no client-controlled explicit global grab. Source: [Wayland protocol/model — surfaces, focus, and grabs](https://wayland.freedesktop.org/docs/html/ch04.html).

#### GNOME Shell extension option

A Shell extension can register a Shell keybinding and place Clutter/St actors over the whole stage because it executes inside GNOME Shell. This is capable of the most native UX, but it is a privileged, GNOME-only architecture rather than a normal application API. GNOME’s own documentation says extensions become part of the Shell process, can access internal Shell code, and can crash the desktop; it also explains that there is no stable extension API and releases are tied to tested Shell versions. Sources: [GNOME extension architecture](https://gjs.guide/extensions/overview/architecture.html), [updates and breakage](https://gjs.guide/extensions/overview/updates-and-breakage.html), and [extension anatomy](https://gjs.guide/extensions/overview/anatomy.html).

Use an extension only if the product explicitly accepts per-GNOME-version maintenance, installation/enabling friction, extension review, and the increased trust boundary. It is not the recommended V1.

### 2. Screen, region, and window capture

#### Screenshot portal: recommended one-shot path

On Ubuntu 24.04, call:

- `org.freedesktop.portal.Screenshot.Screenshot`
- `interactive=true`
- a valid parent-window identifier when one exists, otherwise an empty parent for a shortcut-launched headless request

The result is a portal request whose successful response contains an image `uri`. On GNOME 46, the backend forwards the interactive request to the allowlisted `org.gnome.Shell.Screenshot.InteractiveScreenshot` service. Sources: [Screenshot v2 interface](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.Screenshot.xml) and [GNOME 46 screenshot backend](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screenshot.c).

GNOME’s UI supports selection/area, entire screen, and a user-selected window. It snapshots the Shell stage with `screenshot_stage_to_content()`, displays that captured content in the Shell screenshot UI group, and then crops/composites the selected result. This is a genuine compositor-owned frozen-frame overlay, not an ordinary transparent client window. Sources: [GNOME Help — Screenshots and screencasts](https://help.gnome.org/users/gnome-help/stable/screen-shot-record.html.en) and [GNOME Shell 46 screenshot UI source](https://gitlab.gnome.org/GNOME/gnome-shell/-/raw/gnome-46/js/ui/screenshot.js).

Limits on this target:

- `interactive` is a hint in the cross-desktop specification, but GNOME 46 does invoke its native chooser.
- Version 2 cannot preselect Area, Window, Screen, or Active Window. The user chooses in Shell.
- The portal returns the image URI, not the selected rectangle, monitor identity, or a reusable frozen-frame surface.
- Cancellation is normal and must leave no stale overlay or OCR job.

These limits follow from the [1.18.4 Screenshot interface](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.Screenshot.xml) and the [GNOME 46 backend](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screenshot.c).

#### Non-interactive Screenshot portal: viable but not preferred for V1

With `interactive=false`, xdg-desktop-portal 1.18.4 asks for a persistent screenshot permission if it is not already set. The prompt says the application wants to take screenshots “at any time,” stores allow/deny in the permission store, and says the choice can be changed in privacy settings. Once checked, GNOME’s backend can skip its share dialog and take the default whole-screen screenshot. Sources: [xdg-desktop-portal 1.18.4 screenshot permission flow](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/src/screenshot.c) and [GNOME 46 non-interactive screenshot dialog](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screenshotdialog.c).

This can feed an application-owned frozen overlay, but it carries a broader persistent permission and the returned PNG has no portal monitor-layout metadata. It is therefore a weaker default for privacy and mixed-scale multi-monitor correctness than GNOME’s interactive selector.

Use a stable application ID/desktop file. The frontend source notes that an unidentified unsandboxed host application can fall into a generic permission shared by host apps, which is undesirable for clear attribution. Source: [xdg-desktop-portal screenshot permission source](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/src/screenshot.c).

#### ScreenCast portal plus PipeWire: supported custom-capture path

The standard sequence is `CreateSession` → `SelectSources` → `Start` → `OpenPipeWireRemote`. `Start` normally presents a source chooser. The target API supports:

- source types `MONITOR`, `WINDOW`, and `VIRTUAL`;
- `multiple=true` for one or more selected streams;
- hidden, embedded, or metadata cursor modes;
- `persist_mode` and single-use `restore_token` to restore a prior source selection;
- stream properties `id`, `position`, `size`, `source_type`, and `mapping_id`.

Sources: [ScreenCast v5 interface](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.ScreenCast.xml), [GNOME 46 ScreenCast implementation](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screencast.c), and [GNOME stream-property proxying](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/gnomescreencast.c).

There is no `AREA` source in the standard ScreenCast API. A custom region flow must capture a monitor, freeze a frame, collect a rectangle in the application, and crop locally. The private Mutter ScreenCast API does contain `RecordArea`, but its XML explicitly says the API is private and promises no compatibility; bypassing the portal is not an acceptable product path. Sources: [ScreenCast v5 source types](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.ScreenCast.xml) and [Mutter 46 private ScreenCast interface](https://gitlab.gnome.org/GNOME/mutter/-/raw/gnome-46/data/dbus-interfaces/org.gnome.Mutter.ScreenCast.xml).

`OpenPipeWireRemote` returns a restricted connection on which only the authorized screencast nodes are available. Directly connecting to PipeWire does not grant access to compositor pixels; the portal/compositor must create and authorize the nodes. Sources: [ScreenCast v5 `OpenPipeWireRemote`](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.ScreenCast.xml) and [PipeWire portal access control](https://pipewire.pages.freedesktop.org/pipewire/page_portal.html).

For a frozen frame, consume the first valid negotiated frame, copy it into application-owned memory, close the portal session promptly, and render the copy. Parse the negotiated PipeWire video format for the actual frame width/height; do not infer buffer pixels from the portal’s compositor-space `size`. Source: [PipeWire video capture tutorial](https://pipewire.pages.freedesktop.org/pipewire/page_tutorial5.html).

Persistence can remove repeated source selection when GNOME successfully restores the source, but it is not an unconditional silent-capture grant. Tokens are single-use; a missing monitor/window, withdrawn permission, or failed restore causes normal prompting. Source: [ScreenCast persistence specification](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html).

### 3. Frozen-frame and fullscreen overlays

#### Native supported overlay

The only fully native, compositor-owned selection overlay available to an ordinary application is GNOME Shell’s screenshot UI reached through `Screenshot(interactive=true)`. It already snapshots the stage, covers the Shell stage, captures input in Shell, and supports area/screen/window choice. This should be treated as the V1 overlay rather than recreated. Source: [GNOME Shell 46 screenshot UI](https://gitlab.gnome.org/GNOME/gnome-shell/-/raw/gnome-46/js/ui/screenshot.js).

#### Standards-supported application approximation

An application can request one `xdg_toplevel`/GTK window fullscreen on each `GdkMonitor`. GTK exposes `gtk_window_fullscreen_on_monitor()`, but documents that fullscreen is a request: the application must not assume it was honored and should observe the resulting state. Sources: [GTK `fullscreen_on_monitor`](https://docs.gtk.org/gtk4/method.Window.fullscreen_on_monitor.html) and [GTK `is_fullscreen`](https://docs.gtk.org/gtk4/method.Window.is_fullscreen.html).

The xdg-shell protocol similarly makes fullscreen subject to compositor policy and accepts an output only as a preference. It also requires a compositor to prevent unrelated screen content from showing through a non-opaque fullscreen surface. Therefore a “transparent fullscreen overlay over the live desktop” is not portable; the application must paint the captured frozen frame as its own background. Source: [xdg-shell 1.34 `xdg_toplevel.set_fullscreen`](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/raw/1.34/stable/xdg-shell/xdg-shell.xml).

This approximation cannot guarantee:

- atomic appearance across all monitors;
- placement above Shell UI, notifications, lock UI, or every fullscreen surface;
- global absolute positioning;
- focus if the compositor does not accept the activation;
- identical behavior across workspaces or monitor hotplug.

Wayland clients do not know their surfaces’ global positions and cannot access other clients’ surfaces; xdg-shell exposes no general always-on-top or desktop-overlay role. Sources: [Wayland protocol/model](https://wayland.freedesktop.org/docs/html/ch04.html) and [xdg-shell protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/raw/1.34/stable/xdg-shell/xdg-shell.xml).

#### Layer-shell is not a GNOME solution

`zwlr_layer_shell_v1` defines background/bottom/top/overlay layers, output anchoring, and keyboard-interactivity controls, but it is a wlroots protocol, not a standard xdg-shell role. Mutter has an unresolved request to implement it and does not provide it in the Ubuntu 24.04 GNOME 46 stack. Sources: [wlr-layer-shell protocol](https://github.com/swaywm/wlr-protocols/blob/master/unstable/wlr-layer-shell-unstable-v1.xml) and [Mutter issue #973](https://gitlab.gnome.org/GNOME/mutter/-/issues/973).

Do not build the GNOME path around `gtk-layer-shell`, `wlr-layer-shell`, `wlr-screencopy`, or `wlr-data-control`; those are useful on wlroots compositors but do not solve this target.

### 4. Clipboard output

Use GTK/GDK’s normal clipboard API after the user selects or confirms OCR text:

- `gdk_clipboard_set_text()` publishes UTF-8 text.
- Keep the application alive while consumers request the data.
- On shutdown, GTK calls the equivalent of `gdk_clipboard_store_async()`; explicit storage can be requested, but the documentation warns that persistence beyond process lifetime depends on platform clipboard-manager support.

Sources: [GDK `Clipboard.set_text`](https://docs.gtk.org/gdk4/method.Clipboard.set_text.html) and [GDK `Clipboard.store_async`](https://docs.gtk.org/gdk4/method.Clipboard.store_async.html).

For reliability, perform the clipboard write in response to input received by the focused result/overlay surface. Core Wayland’s `wl_data_device.set_selection` requires “the serial number of the event that triggered this request,” and selection offers are tied to keyboard focus. A headless process activated only by an out-of-process shortcut has no guaranteed fresh input serial. Source: [Wayland 1.22 core data-device protocol](https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.22.0/protocol/wayland.xml).

The XDG Clipboard portal in 1.18.4 is **not** a generic “copy text” portal. It attaches clipboard transfer to an existing supported portal session, specifically RemoteDesktop on this stack. GNOME’s backend rejects non-RemoteDesktop sessions. Requesting RemoteDesktop solely to copy OCR text would be unnecessary privilege and a poor permission experience. Sources: [Clipboard portal v1 interface](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.Clipboard.xml) and [GNOME 46 Clipboard backend](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/clipboard.c).

### 5. Multi-monitor and fractional scaling

The native interactive Screenshot path is preferred because Shell captures and displays its own stage snapshot and owns the selection coordinate system. This removes the application’s need to reconstruct monitor-to-image mapping for the capture step. It does not eliminate the need for target-hardware tests, but it avoids relying on underspecified cross-coordinate conversion. Source: [GNOME Shell 46 screenshot UI](https://gitlab.gnome.org/GNOME/gnome-shell/-/raw/gnome-46/js/ui/screenshot.js).

For a custom ScreenCast overlay:

1. Request monitor sources and, if needed, `multiple=true`.
2. Treat each PipeWire stream independently.
3. Read actual frame pixels from the negotiated SPA video format.
4. Use portal `position` and `size` only as compositor-space layout metadata. The v5 specification explicitly warns that these values need not equal pixel coordinates or the actual stream size.
5. Enumerate `GdkMonitor` objects. `gdk_monitor_get_geometry()` returns application pixels; GTK 4.14’s `gdk_monitor_get_scale()` returns the double scale mapping monitor coordinates to device pixels.
6. Match and transform cautiously; never assume `frame_width == logical_width * integer_scale`.

Sources: [ScreenCast v5 stream properties](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.ScreenCast.xml), [PipeWire negotiated video size](https://pipewire.pages.freedesktop.org/pipewire/page_tutorial5.html), [GDK monitor geometry](https://docs.gtk.org/gdk4/method.Monitor.get_geometry.html), and [GDK fractional monitor scale](https://docs.gtk.org/gdk4/method.Monitor.get_scale.html).

Mutter has supported `fractional_scale_v1` since the GNOME 44 line and GNOME 46 includes further fractional-scale/screencast fixes. That support does not collapse logical, compositor, and buffer-pixel coordinates into one space; the portal warnings still apply. Sources: [Mutter fractional-scale implementation](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/2394) and [Mutter GNOME 46 NEWS](https://gitlab.gnome.org/GNOME/mutter/-/raw/gnome-46/NEWS).

Remaining uncertainty requiring tests:

- The portal does not standardize a stable connector/output ID in v5. `position` and `size` are optional, and mirrored outputs may be ambiguous.
- The Screenshot portal gives only an image URI, so an application-owned whole-desktop overlay cannot recover authoritative per-monitor raster boundaries from the response.
- Hotplug, suspend/resume, and mode changes can invalidate v5 PipeWire node IDs; version 6’s non-reused `pipewire-serial` is not present on this target.
- Fractional-scale rounding at seams and monitors with negative logical origins needs pixel-level validation.

### 6. Permission and prompt behavior

Expected user-visible interactions on Ubuntu 24.04:

- **GNOME Custom Shortcut:** one-time user configuration in Settings. There is no application-side prompt because the user explicitly creates the binding. Source: [GNOME custom-shortcut instructions](https://help.gnome.org/users/gnome-help/stable/keyboard-shortcuts-set.html.en).
- **Interactive Screenshot:** GNOME’s screenshot overlay appears on every invocation. The frontend does not ask for the broad non-interactive “at any time” permission when `interactive=true`; the Shell UI itself is the confirmation. Sources: [xdg-desktop-portal permission flow](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/src/screenshot.c) and [GNOME backend](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screenshot.c).
- **Non-interactive Screenshot:** first use asks to allow screenshots at any time; allow/deny is stored. A denial is remembered until changed in privacy settings. Source: [xdg-desktop-portal 1.18.4 screenshot permission flow](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/src/screenshot.c).
- **ScreenCast:** `Start` normally opens the GNOME source chooser. Persistence may return a restore token and later suppress reselection, but restoration can fail or be revoked. Sources: [ScreenCast v5](https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/1.18.4/data/org.freedesktop.portal.ScreenCast.xml) and [GNOME 46 restoration code](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-46/src/screencast.c).
- **Clipboard write:** no portal prompt is needed for the application’s own focused interaction; normal Wayland selection/focus rules apply. Sources: [GDK Clipboard](https://docs.gtk.org/gdk4/class.Clipboard.html) and [Wayland data-device protocol](https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.22.0/protocol/wayland.xml).
- **Shell extension:** the user installs/enables privileged code that runs inside Shell; there is no fine-grained capture permission boundary comparable to the portal. Source: [GNOME extension architecture](https://gjs.guide/extensions/overview/architecture.html).

Security recommendations:

- Prefer interactive Screenshot for V1; do not request RemoteDesktop, InputCapture, or persistent screencast access for a one-shot OCR action.
- If ScreenCast is used, request only monitor/window source types actually needed, close after freezing the frame, rotate the single-use restore token, and handle revocation.
- Keep capture and OCR data in memory where practical, delete temporary portal-exported files when ownership/lifetime rules permit, and do not log recognized text.
- Use a stable application ID so permission attribution is specific.
- Treat cancellation, lock/session transitions, monitor removal, and portal disappearance as normal teardown paths.

## API classification

### Standards-supported and usable on Ubuntu 24.04

- XDG Screenshot portal v2, including GNOME’s interactive native selector.
- XDG ScreenCast portal v5 plus its restricted PipeWire remote.
- ScreenCast monitor/window/virtual sources, multiple streams, cursor modes, and restore tokens.
- xdg-shell fullscreen requests and GTK fullscreen-on-monitor windows, with compositor-policy limitations.
- Core Wayland clipboard through public GDK clipboard APIs.

### Standard API present, but unavailable through the target backend

- XDG GlobalShortcuts: frontend interface present; GNOME 46 implementation absent.

### GNOME-specific supported mechanisms

- User-created GNOME Settings Custom Shortcut launching an application command.
- GNOME Shell’s screenshot UX, but only when reached through the public Screenshot portal.
- Public GTK/GDK monitor, fullscreen, and clipboard APIs.

### Private or brittle interfaces to reject for the application path

- `org.gnome.Shell.GrabAccelerator(s)`: caller-restricted to GNOME components.
- Direct `org.gnome.Shell.Screenshot`: caller allowlist includes portal backends and GNOME components, not arbitrary apps. Source: [GNOME Shell 46 screenshot caller check](https://gitlab.gnome.org/GNOME/gnome-shell/-/raw/gnome-46/js/ui/screenshot.js).
- Direct `org.gnome.Mutter.ScreenCast`/`RemoteDesktop`: explicitly private with no compatibility promise. Sources: [Mutter ScreenCast XML](https://gitlab.gnome.org/GNOME/mutter/-/raw/gnome-46/data/dbus-interfaces/org.gnome.Mutter.ScreenCast.xml) and [RemoteDesktop XML](https://gitlab.gnome.org/GNOME/mutter/-/raw/gnome-46/data/dbus-interfaces/org.gnome.Mutter.RemoteDesktop.xml).
- Shell-extension use of Shell/Mutter/St internals: powerful, privileged, and version-coupled.
- Programmatically mutating GNOME custom-keybinding GSettings instead of asking the user to configure it.
- wlroots-only layer-shell, screencopy, or data-control protocols on Mutter.

### Impossible or constrained by the target Wayland model

- An ordinary app cannot inspect other clients’ buffers or capture the desktop without compositor mediation.
- An ordinary app cannot globally listen for arbitrary keys or force an explicit keyboard grab while unfocused.
- An ordinary app cannot force absolute placement or a trusted always-on-top Shell overlay.
- A transparent xdg-shell fullscreen surface cannot portably expose the live desktop beneath it; paint a captured frame.
- The ScreenCast portal cannot directly select a rectangular region.
- The target Screenshot v2 portal cannot programmatically choose Area/Window/Screen mode.
- The target Clipboard portal cannot be used as a generic background clipboard setter.

## Recommended architecture

### V1: supported and low-risk

1. Install a normal host application with a stable application ID and stable launcher command.
2. On first run, show instructions/deep guidance for adding a GNOME Custom Shortcut; do not edit the setting silently.
3. On shortcut activation, serialize requests so only one capture flow exists.
4. Call Screenshot v2 with `interactive=true`.
5. Let GNOME Shell show its frozen-frame selector and let the user choose area, screen, or window.
6. Decode the returned URI, run OCR locally, and discard the raster as soon as the interaction permits.
7. Show OCR results in an ordinary focused GTK surface. Copy only after the user selects/confirms text, using `GdkClipboard`.
8. Handle portal cancellation and session/monitor changes without retries that reopen prompts.

This path provides explicit global invocation, native region/window/screen selection, a frozen frame, compositor-correct capture, and clipboard output without a Shell extension or continuous screen permission.

### Optional V2: custom OCR-on-frozen-frame overlay

Use only if product requirements demand drawing OCR boxes before the user chooses text:

1. Establish a ScreenCast v5 session for monitor sources, optionally with `multiple=true` and persistent restore.
2. Receive one frame per selected monitor through the restricted PipeWire remote.
3. Copy frames and immediately close ScreenCast.
4. Create one GTK fullscreen window per monitor and paint the corresponding frozen frame; never depend on transparency.
5. Map pointer/application coordinates to frame pixels using portal compositor geometry, GDK monitor geometry/scale, and negotiated frame dimensions.
6. Verify every window actually entered fullscreen before accepting selection, and fall back to a normal window if not.

This path still cannot promise a Shell-level overlay. Before adopting it, prototype and test mixed 100/125/150/200% scaling, left/up negative monitor origins, mirrored outputs, rotated displays, hotplug during capture, full-screen apps, multiple workspaces, cancellation, denied/revoked permissions, and clipboard persistence after process exit.

### Future desktop path

On GNOME 48 or another backend that implements GlobalShortcuts, prefer the standard portal after runtime capability detection. Keep the user-configured GNOME shortcut as the Ubuntu 24.04 fallback. Screenshot target selection should likewise be enabled only after detecting interface version 3 and checking `AvailableTargets`.

## Final recommendation

Adopt **GNOME Custom Shortcut → interactive Screenshot portal → GNOME Shell frozen selector → local OCR → user-driven GDK clipboard copy** for Ubuntu 24.04.

The top blockers to a fully custom overlay are:

1. no GNOME GlobalShortcuts backend in GNOME 46;
2. no standard always-on-top/absolute overlay role and no Mutter layer-shell;
3. Screenshot v2 cannot request a specific target mode;
4. ScreenCast has no region source and normally adds a chooser/permission step;
5. custom multi-monitor overlays must reconcile optional compositor-space metadata with actual PipeWire pixels and fractional GDK coordinates.

The native Screenshot portal path avoids all but the first blocker and is the appropriate V1 boundary.
