# UI stack boundaries for an Ubuntu 24.04 GNOME Wayland OCR overlay

## Scope

This report evaluates the UI and native-system boundary for an Ubuntu 24.04
GNOME Wayland OCR overlay. Flutter is preferred where it is a good fit, but
capture, overlay reliability, accessibility, crash isolation, and native desktop
behavior take precedence. The OCR engine itself is deliberately left open.

## Conclusion

Use a **hybrid architecture**:

- a Flutter process for settings, onboarding, history, and other conventional
  control UI;
- a separate native Linux service for activation, portal/PipeWire capture,
  coordinate mapping, OCR orchestration, and GTK4 overlay windows;
- D-Bus as the small-message control plane, with raw image buffers kept inside
  the native service; and
- an optional Unix-socket plus passed file descriptor boundary only if the OCR
  engine later needs its own crash-isolated worker.

This preserves the Flutter preference without putting unsupported or
Linux-specific window behavior behind Flutter plugins. It also leaves a clean
fallback: if no real cross-platform control UI is planned, replace the Flutter
client with GTK4/libadwaita while keeping the service API and core modules.

Do **not** make a Flutter-only overlay the production baseline. A narrowly
scoped, single-window Flutter proof of concept is possible, but current stable
Flutter does not offer the combination of first-class transparent windowing,
production multi-window support, native GTK4/libadwaita controls, and proven
Linux accessibility needed here.

## The Wayland constraint that drives the design

This is not only a toolkit choice.

- Wayland clients do not know the global position of their surfaces and cannot
  access other clients' surfaces; the compositor owns composition and input
  routing ([Wayland protocol model](https://wayland.freedesktop.org/docs/book/Protocol.html)).
- An `xdg_toplevel.set_fullscreen` call is a request subject to compositor
  policy. More importantly, the xdg-shell protocol says that when a fullscreen
  surface is not opaque, the compositor **must prevent unrelated screen content
  from being visible below it**
  ([xdg-shell source](https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/main/stable/xdg-shell/xdg-shell.xml),
  [rendered protocol](https://wayland.app/protocols/xdg-shell#xdg_toplevel:request:set_fullscreen)).
- GTK4 mirrors those limits: fullscreen is a request whose result must be
  observed, and GTK4 removed X11-oriented position, move, stacking, and
  `keep-above` APIs
  ([GTK4 fullscreen-on-monitor](https://docs.gtk.org/gtk4/method.Window.fullscreen_on_monitor.html),
  [GTK3-to-GTK4 migration](https://docs.gtk.org/gtk4/migrating-3to4.html)).

Therefore a standard GNOME Wayland application cannot promise a persistent,
live, transparent, always-on-top desktop overlay merely by choosing GTK instead
of Flutter. The reliable product model is:

1. capture through the ScreenCast portal;
2. display the captured frame as the **opaque frozen background** of a
   fullscreen selection/result window;
3. draw selection dimming, OCR boxes, and controls above that frame; and
4. dismiss the window to return to the live desktop.

This avoids depending on seeing other applications through a transparent
fullscreen surface. If the required UX is instead a persistent click-through
overlay over a live desktop, that is an unresolved GNOME Shell integration
problem, potentially requiring a Shell extension and a different security and
distribution decision.

## Ubuntu 24.04 baseline

Ubuntu 24.04 supplies GTK 4.14.2 and libadwaita 1.5.0
([GTK4 package](https://packages.ubuntu.com/noble/amd64/libgtk-4-1),
[libadwaita package](https://packages.ubuntu.com/noble/amd64/libadwaita-1-0)).
Its libadwaita package includes Ubuntu's Yaru accent-color integration
([Ubuntu changelog](https://blueprints.launchpad.net/ubuntu/+source/libadwaita-1/+changelog)).
That is a strong native target for this application.

Flutter's supported Linux runner is different:

- Flutter's official Linux setup still installs `libgtk-3-dev`
  ([Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)).
- Ubuntu 24.04 ships GTK 3.24.41
  ([Ubuntu GTK3 package](https://packages.ubuntu.com/noble/libgtk-3-0t64)).
- Flutter's GTK4 migration remains open; the Flutter issue records the need to
  support both GTK3 and GTK4 and unresolved build/plugin/accessibility work
  ([Flutter GTK4 issue](https://github.com/flutter/flutter/issues/94804)).

A Flutter window and a GTK4/libadwaita window can coexist as separate processes.
Trying to mix libadwaita controls into the Flutter scene is not a viable escape
hatch: Flutter paints its own controls rather than using OS widgets
([Flutter FAQ](https://docs.flutter.dev/resources/faq)), and supported desktop
platform views are still unavailable
([Flutter architecture](https://docs.flutter.dev/resources/architectural-overview),
[desktop platform-view tracking](https://github.com/flutter/flutter/issues/188375)).

## Flutter Linux evaluation

### Transparent and fullscreen windows

Flutter can render a transparent Linux view, but this is a native-runner
capability, not a complete Dart window-overlay contract.

- Flutter's Linux engine exposes `fl_view_set_background_color`; the documented
  transparent value is `#00000000`
  ([Flutter issue #152154](https://github.com/flutter/flutter/issues/152154)).
- The long-running Linux transparency issue explicitly distinguishes a
  transparent Flutter view from making the application window transparent;
  the latter belongs in native runner code
  ([Flutter issue #66751](https://github.com/flutter/flutter/issues/66751)).
- GTK3 can request fullscreen and per-monitor fullscreen, but the window manager
  may decline
  ([GTK3 fullscreen](https://docs.gtk.org/gtk3/method.Window.fullscreen.html),
  [GTK3 fullscreen-on-monitor](https://docs.gtk.org/gtk3/method.Window.fullscreen_on_monitor.html)).

There is contradictory evidence on Ubuntu 24.04's exact transparency path.
Flutter issue #152154 warns that GL transparency is broken in GTK 3.24.41,
while GTK's own 3.24.41 release notes say GtkGLArea fixed a transparency
regression
([GTK 3.24 NEWS](https://gitlab.gnome.org/GNOME/gtk/-/raw/gtk-3-24/NEWS)).
Current Flutter tracking also reports that a fully transparent frame can fail
to replace the previous frame, leaving stale pixels on Wayland and X11
([Flutter issue #191870](https://github.com/flutter/flutter/issues/191870)).
This makes Flutter transparency a prototype question, not a dependable product
assumption.

For the proposed frozen-frame UX, true whole-window transparency is unnecessary.
That removes a major source of Flutter and compositor risk.

### Multi-window

Flutter's normal Linux desktop support is stable, but its new multi-window API
is not:

- The official example requires Flutter's main channel and the
  `--enable-windowing` feature
  ([official multiple-windows example](https://github.com/flutter/flutter/tree/master/examples/multiple_windows)).
- Flutter's source says the API is experimental, must not be used in production
  or published plugins, and may change even in patch releases
  ([windowing guard in `binding.dart`](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/binding.dart)).
- The Linux multi-view tracker remains active
  ([Flutter issue #138178](https://github.com/flutter/flutter/issues/138178)).

Community packages do not change the support level of Flutter itself.
`desktop_multi_window` is currently maintained, but requires custom Linux
runner registration
([package documentation](https://pub.dev/packages/desktop_multi_window)).
`window_manager` is also active, but is migrating to a different native core,
and its new Linux build still calls out GTK3, X11, and Xi dependencies
([package documentation](https://pub.dev/packages/window_manager)). Its issue
tracker contains Wayland-specific failures for window constraints and
always-on-top behavior
([window_manager issue #538](https://github.com/leanflutter/window_manager/issues/538)).

A single Flutter root window could be converted into a one-monitor fullscreen
selection view by custom runner code. Simultaneously keeping a control window,
creating one overlay per monitor, or relying on multiple independent Flutter
views would put production behavior on experimental or community windowing.

### Pointer and keyboard hit testing

Flutter widget hit testing is not operating-system window hit testing.
`IgnorePointer` only makes a subtree return false inside Flutter's render tree
([Flutter `IgnorePointer`](https://api.flutter.dev/flutter/widgets/IgnorePointer-class.html)).
It does not send a click to a different application's Wayland surface.

Native surface input regions are the relevant mechanism:

- GTK3 exposes `gtk_widget_input_shape_combine_region`, which can be called from
  a custom Flutter runner/plugin
  ([GTK3 input shape](https://docs.gtk.org/gtk3/method.Widget.input_shape_combine_region.html)).
- GTK4 exposes `gdk_surface_set_input_region`; unset pixels pass mouse events to
  the surface below, and support can be queried at runtime
  ([GTK4 input region](https://docs.gtk.org/gdk4/method.Surface.set_input_region.html),
  [input-shape capability](https://docs.gtk.org/gdk4/method.Display.supports_input_shapes.html)).

For a modal frozen-frame selection window, the simplest and most accessible
behavior is for the whole overlay to accept pointer input. Dynamic click-through
regions are only needed for a persistent result overlay, which is already the
less reliable Wayland product model.

Flutter keyboard listeners also require focus
([`KeyboardListener`](https://api.flutter.dev/flutter/widgets/KeyboardListener-class.html)).
Neither Flutter nor GTK can force GNOME Wayland to focus a window. The overlay
should request presentation, accept `Esc` once focused, and have a pointer
cancel path. A global activation shortcut is a separate desktop capability.

### Stock Ubuntu 24.04 global-shortcut blocker

The GlobalShortcuts portal API exists
([portal specification](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html)),
but stock Ubuntu 24.04's GNOME backend does not implement it:

- Ubuntu 24.04 ships the GNOME 46 portal backend
  ([Ubuntu package](https://packages.ubuntu.com/noble/xdg-desktop-portal-gnome)).
- GNOME added its GlobalShortcuts backend in GNOME 48
  ([GNOME 48 NEWS](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-48/NEWS),
  [implementation merge request](https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/merge_requests/208)).

This is an architecture-independent blocker. The supported Ubuntu 24.04
fallback is a user-created GNOME custom shortcut whose command invokes a small
`capture` CLI/D-Bus activator
([GNOME custom-shortcut instructions](https://help.gnome.org/users/gnome-help/3.20/keyboard-shortcuts-set.html.en)).
Do not depend on GNOME Shell's private D-Bus accelerator APIs; GNOME explicitly
restricts private Shell interfaces to expected callers
([GNOME Shell restriction](https://gitlab.gnome.org/GNOME/gnome-shell/-/merge_requests/1970)).
A Shell extension is a separate, optional future integration.

### Accessibility

Flutter has a real Linux accessibility bridge: its engine maps Flutter
semantics to ATK objects and actions
([`fl_accessible_node.cc`](https://github.com/flutter/engine/blob/main/shell/platform/linux/fl_accessible_node.cc)).
That is better than treating Flutter Linux accessibility as absent.

It is not equivalent to native GTK4 maturity:

- Flutter's proposal to replace its ATK layer with direct AT-SPI access remains
  open
  ([Flutter issue #159460](https://github.com/flutter/flutter/issues/159460)).
- Current Linux reports show live regions, dialogs, route changes, and snackbars
  failing to produce expected AT-SPI announcements without explicit
  announcements
  ([Flutter issue #194045](https://github.com/flutter/flutter/issues/194045)).
- GTK4 standard controls implement `GtkAccessible` by default and use AT-SPI on
  Linux; custom widgets must provide their own accessible properties and tree
  ([GTK4 accessibility](https://docs.gtk.org/gtk4/section-accessibility.html)).

Neither toolkit automatically makes text painted over an image accessible.
OCR results need an explicit semantic/accessibility representation: ordered
text blocks, names, bounds, focus navigation, copy actions, and announcements.
Native GTK labels/buttons give the overlay a better default, while custom-drawn
boxes still require explicit `GtkAccessible` work. Orca behavior must be tested
on the target session.

### Native theming and libadwaita fidelity

Flutter cannot be genuinely libadwaita-native because it draws its own widget
tree. Canonical's maintained Yaru package provides a strong Ubuntu-looking
Flutter theme and widget set
([Yaru package](https://pub.dev/packages/yaru)), but it is still a Flutter
implementation rather than libadwaita widgets.

GTK4/libadwaita provides:

- actual Adwaita widgets and application windows
  ([`AdwApplicationWindow`](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/class.ApplicationWindow.html));
- system color-scheme, dark, accent, and high-contrast integration
  ([libadwaita styles](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/styles-and-appearance.html)); and
- standard keyboard and styling behavior expected by the GNOME HIG
  ([keyboard guidance](https://developer.gnome.org/hig/guidelines/keyboard.html),
  [UI styling guidance](https://developer.gnome.org/hig/guidelines/ui-styling.html)).

This matters most for settings and result controls. The overlay canvas itself
is necessarily custom in all three architectures.

### Platform channels versus `dart:ffi`

Use the boundary according to what it owns:

- **Platform channels** are appropriate for small, asynchronous operations tied
  to Flutter's host window, plugin registry, or GTK main loop. Standard channels
  serialize JSON-like values and byte buffers
  ([Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)).
  They provide no crash isolation because the native handler is normally in the
  Flutter process.
- **`dart:ffi`** is appropriate for a stable C ABI and hot, in-process calls
  where avoiding channel serialization matters. Flutter documents that FFI is
  faster because no serialization is required
  ([Flutter architecture](https://docs.flutter.dev/resources/architectural-overview)).
  Dart FFI is a C-language ABI
  ([Dart C interop](https://dart.dev/interop/c-interop)); C++ or Rust should
  expose a C ABI or generated equivalent.
- Do not make a long OCR call a leaf FFI call. Dart documents leaf calls as
  short-running and non-blocking, and warns that a long/blocking leaf call can
  stall runtime synchronization
  ([Dart `Native.isLeaf`](https://api.dart.dev/dart-ffi/Native/isLeaf.html)).
  Callbacks from arbitrary native threads should use
  `NativeCallable.listener`
  ([Dart API](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html)).
- Since Flutter 3.41, Linux merges the UI and platform threads by default,
  which helps FFI access to main-thread-only APIs but also makes blocking native
  work on that thread especially inappropriate
  ([Flutter Linux merged threads](https://docs.flutter.dev/release/breaking-changes/linux-merged-threads)).

For this product, platform channels and FFI are implementation details inside a
single process. They are not substitutes for the recommended process boundary.

### Rust and C++ choices

The architecture does not require selecting one native language immediately.

For Rust:

- `gtk4-rs` provides maintained safe GTK4 bindings
  ([gtk4-rs docs](https://gtk-rs.org/gtk4-rs/stable/latest/docs/gtk4/index.html));
- `libadwaita-rs` provides maintained Adwaita bindings
  ([libadwaita-rs docs](https://world.pages.gitlab.gnome.org/Rust/libadwaita-rs/stable/latest/docs/libadwaita/));
- `ashpd` wraps ScreenCast and GlobalShortcuts portals
  ([ScreenCast](https://docs.rs/ashpd/latest/ashpd/desktop/screencast/index.html),
  [GlobalShortcuts](https://docs.rs/ashpd/latest/ashpd/desktop/global_shortcuts/));
  the latter still depends on the desktop backend and therefore does not solve
  Ubuntu 24.04's GNOME 46 gap; and
- `zbus` is a maintained D-Bus implementation and supports Unix FD passing
  ([zbus connection builder](https://docs.rs/zbus/latest/zbus/connection/struct.Builder.html)).

For C++:

- Flutter's generated Linux runner/plugin environment is already C/C++, and
  `gtkmm-4.0` is the maintained C++ wrapper for GTK4
  ([gtkmm documentation](https://gnome.pages.gitlab.gnome.org/gtkmm-documentation/sec-gtkmm.html)).
- Direct libadwaita/libportal C APIs remain available.
- If a Rust OCR adapter must be linked into a C++ core, CXX provides a
  statically checked Rust/C++ bridge with negligible boundary overhead
  ([CXX documentation](https://cxx.rs/)).

For Flutter-to-Rust in one process, `flutter_rust_bridge` is active and supports
async Rust and generated glue
([package](https://pub.dev/packages/flutter_rust_bridge)). It is optional
convenience, not isolation. A plain, small C ABI remains easier to version and
replace. Rust panics must not unwind through an ordinary C boundary; Rust's
documentation recommends catching them for graceful error conversion or
accepting process abort behavior
([Rust FFI guidance](https://doc.rust-lang.org/nomicon/ffi.html)).

### Startup and footprint

Flutter has unavoidable engine/runtime baseline cost:

- a Linux release must ship its executable, native `.so` libraries, and data
  assets
  ([Flutter Linux bundle](https://docs.flutter.dev/platform-integration/linux/building));
- Flutter initializes an embedder, engine, Dart runtime, UI/raster work, and a
  rendered texture
  ([Flutter architecture](https://docs.flutter.dev/resources/architectural-overview)); and
- historical first-party measurements of a default Linux app reported an
  approximately 18 MB bundle and materially higher RSS than a small native app,
  though those old figures are not a current Ubuntu 24.04 benchmark
  ([Flutter issue #92318](https://github.com/flutter/flutter/issues/92318)).

The exact current cold-start, proportional set size, and installed-size
difference is unresolved and must be measured. Flutter's official
`--analyze-size` support can measure its bundle
([Flutter app-size docs](https://docs.flutter.dev/perf/app-size)).

The recommended hybrid keeps Flutter off the latency-critical path: the native
service can stay lightweight and show the capture overlay directly; Flutter
starts only when the user opens settings/history. Running Flutter and native UI
at the same time costs more memory than a GTK-only app, but not on every capture.

### Plugin-maintenance assessment

Flutter's general Linux plugin model is sound and supports federated
implementations
([Flutter plugin docs](https://docs.flutter.dev/packages-and-plugins/developing-packages)).
The issue is the maturity of the exact capabilities needed here.

- Official production multi-window support is not ready.
- Critical Wayland window controls are spread across community packages and
  native runner edits.
- Canonical's Dart `dbus` package is maintained and can pass Unix FDs
  ([dbus.dart](https://github.com/canonical/dbus.dart/)).
- Canonical's Dart portal package is maintained, but its published
  `XdgScreenCastPortal` currently exposes only `getVersion`, not the session,
  source-selection, start, or PipeWire-open workflow
  ([published API](https://pub.dev/documentation/xdg_desktop_portal/latest/xdg_desktop_portal/XdgScreenCastPortal-class.html)).

Owning a thin, application-specific adapter around portal/window behavior is
safer than making a community plugin's API an architectural boundary. In the
recommended design that adapter is in the native service.

## Three honest architectures

### 1. Flutter-only

Definition: one Flutter executable owns the control UI, capture flow, OCR, and
overlay, with native runner/plugin code only where Linux APIs require it.

Strengths:

- one application project and one UI technology;
- fastest path for a team already strong in Flutter;
- portable control UI and shared state; and
- viable for a single selected-monitor, screenshot-backed, modal overlay if a
  custom GTK3 runner is accepted.

Costs and risks:

- "Flutter-only" is not actually Dart-only: PipeWire consumption, reliable
  portal coverage, native input regions, and window setup still need FFI or a
  Linux plugin;
- stable multi-window is unavailable;
- libadwaita widgets cannot be embedded;
- Linux accessibility has known AT-SPI gaps;
- native window behavior is coupled to Flutter's GTK3 embedder and plugin
  churn; and
- an engine/plugin/native crash takes down the entire app.

Verdict: acceptable only as a time-boxed prototype or if the product is reduced
to one modal window on one monitor. Not the production recommendation.

### 2. Flutter control UI plus native capture/overlay/OCR core

Definition:

- `image-segment-ui`: Flutter settings, onboarding, history, language/model
  selection, and diagnostics;
- `image-segment-core`: native session service owning activation, portal and
  PipeWire objects, frames, coordinate mapping, OCR scheduling, and GTK4
  overlays; and
- optional `image-segment-ocr-worker`: a later process boundary for a crashy,
  untrusted, or memory-heavy OCR engine.

Strengths:

- preserves Flutter where it is strongest;
- makes the overlay independent of Flutter multi-window and GTK3;
- uses GTK4 surface/input APIs and native accessibility for the critical
  interaction;
- raw pixels need not cross into Dart;
- Flutter can crash or be closed without breaking the capture service;
- the overlay hot path does not pay Flutter startup cost; and
- the UI client is replaceable without changing capture or OCR modules.

Costs and risks:

- two UI stacks and two process lifecycles;
- D-Bus API versioning and reconnect behavior must be designed;
- higher peak memory when both UIs are open; and
- the native overlay still obeys Wayland/GNOME restrictions; it cannot promise
  a live, transparent, always-on-top surface.

Verdict: recommended when Flutter preference represents a real cross-platform
roadmap.

### 3. GTK4/libadwaita-native UI plus native core

Definition: settings and overlay use GTK4/libadwaita, in Rust through gtk-rs or
in C/C++; capture and OCR modules are either in process or behind the same
service contract.

Strengths:

- best Ubuntu/GNOME visual, input, accessibility, portal-parenting, and
  high-contrast fidelity;
- no Flutter engine or GTK3 dependency;
- simplest native debugging and packaging story;
- likely lowest startup and memory floor, subject to measurement; and
- GTK4/libadwaita versions required by the app are already present on Ubuntu
  24.04.

Costs and risks:

- control UI is not shared with Windows/macOS;
- fewer developers may know GTK object/lifecycle patterns; and
- an in-process UI/core design loses crash isolation unless the service
  boundary is retained.

Verdict: best technical choice for an Ubuntu-only product. It should replace,
not fork, the Flutter client if the cross-platform requirement does not
materialize.

## Replaceable module boundaries

Define domain interfaces before choosing an OCR implementation:

- `ActivationBackend`
  - emits `CaptureRequested`;
  - Ubuntu 24.04 implementation is a CLI/D-Bus activation command configured as
    a GNOME custom shortcut;
  - future implementation may use the GlobalShortcuts portal.
- `CaptureBackend`
  - owns portal session and PipeWire stream;
  - returns a `FrameSet` with immutable planes, stream/output identity,
    dimensions, scale, transform, cursor metadata, and timestamp.
- `CoordinateMapper`
  - converts source-pixel polygons to overlay logical coordinates;
  - owns fractional scaling, monitor transforms, and multi-stream composition.
- `OcrEngine`
  - accepts an immutable frame reference plus language hints and cancellation;
  - returns structured text blocks, lines/words, source-pixel polygons,
    confidence, orientation, and engine-neutral error codes;
  - has no GTK, Flutter, portal, storage, or clipboard dependency.
- `OcrScheduler`
  - owns worker limits, cancellation, deadlines, and engine lifecycle.
- `OverlayPresenter`
  - consumes `FrameSet`, selection state, and engine-neutral OCR results;
  - exposes select, cancel, copy, and dismiss events;
  - is implemented by GTK4 in the recommended design.
- `ApplicationService`
  - is the stable use-case layer: start capture, cancel, report state, expose
    result metadata, and update preferences.
- `ControlUiClient`
  - depends only on the versioned service API, not on engine or portal types.

Keep OCR coordinates in source-pixel space until `CoordinateMapper` transforms
them. That prevents an OCR engine swap from inheriting toolkit-specific scale
assumptions.

## IPC and isolation

### D-Bus: default control plane

Use a versioned session-bus service for commands and state:

- methods such as `StartCapture`, `CancelCapture`, `GetState`,
  `GetCapabilities`, and `SetPreferences`;
- signals such as `StateChanged`, `ResultReady`, `PermissionRequired`, and
  `CoreRestarted`; and
- small values only: IDs, text, polygons, errors, and settings.

D-Bus is already the portal transport, has good GLib/Rust/Dart bindings, and can
pass Unix file descriptors out of band
([D-Bus specification](https://dbus.freedesktop.org/doc/dbus-specification.html)).
Do not marshal full-resolution frames as D-Bus byte arrays.

### Unix socket plus shared buffer: optional data plane

If OCR moves to a separate process, send a sealed `memfd`/shared-memory file
descriptor plus explicit format/stride/size metadata over an AF_UNIX socket.
Linux `SCM_RIGHTS` gives the receiver a reference to the same open file
description
([`unix(7)`](https://man7.org/linux/man-pages/man7/unix.7.html)).

This gives isolation and avoids a full image copy, but requires framing,
credential checks, cleanup, backpressure, and protocol versioning. Do not add
it until an OCR worker process is justified.

### In-process FFI

Use FFI only inside a process for a narrow compute adapter. It has the least
marshalling overhead but no crash boundary: a native memory error or uncaught
abort terminates the UI/service process. It is suitable for a proven OCR
library behind `OcrEngine`, not for coupling the Flutter control UI to GTK
overlay objects.

### Recommended process ownership

Keep portal, PipeWire, coordinate mapping, overlay, and initially OCR in one
native service so frames remain local. Separate the Flutter client immediately.
Split OCR into a worker only after a real engine demonstrates crash, leak, ABI,
or memory-pressure risk. The UI should watch D-Bus name ownership and reconnect;
the service supervisor should be able to restart after failure.

## Blockers and prototype questions

These questions cannot be closed by documentation alone.

1. **Product UX blocker — frozen versus live overlay**
   - Confirm that a screenshot-backed modal overlay is acceptable.
   - If persistent live transparency is mandatory, stop and prototype a GNOME
     Shell extension path before committing to any application toolkit.

2. **GTK4 overlay prototype on stock Ubuntu 24.04**
   - Start from a ScreenCast portal stream, freeze a frame, and show a
     borderless fullscreen-on-monitor GTK4 window.
   - Verify first-frame flash, actual fullscreen state, `Esc`, pointer cancel,
     input regions, fractional scale, rotated displays, and mixed-DPI dual
     monitors on a GNOME Wayland session.
   - Verify that portal-to-overlay coordinates remain correct.

3. **Activation prototype**
   - Verify a GNOME custom shortcut invoking `image-segment-ai capture` can
     D-Bus-activate the service and present the overlay with focus.
   - Detect the GlobalShortcuts portal at runtime for future GNOME versions,
     but expose the custom-shortcut setup on Ubuntu 24.04.

4. **Portal lifecycle prototype**
   - Verify user-selection flow, restore tokens, cancellation, service restart,
     lock/unlock, monitor hotplug, and permission revocation.
   - Verify whether the portal dialog can be acceptably parented when capture is
     initiated without the Flutter settings window.

5. **Accessibility prototype**
   - With Orca, verify ordered OCR text, focus movement, selection, copy,
     result announcements, cancel/dismiss, and bounds.
   - Test high contrast, large text, keyboard-only use, and reduced motion.
   - Repeat a minimal comparison in Flutter only if Flutter overlay remains
     under consideration.

6. **Flutter window spike, only if stakeholders still want Flutter overlay**
   - On current stable Flutter and Ubuntu 24.04 Wayland, test one custom-runner
     window with `fl_view_set_background_color`, GTK3 fullscreen, input shape,
     focus, first/fully-transparent frames, and Orca.
   - Do not use experimental Flutter multi-window as acceptance evidence.

7. **Footprint and latency benchmark**
   - Compare hybrid and all-native release builds on the same machine.
   - Measure cold and warm shortcut-to-visible-overlay latency, settings-window
     startup, idle/peak PSS and RSS, installed size, and first-capture GPU use.
   - Include service-only idle and service-plus-Flutter cases.

8. **Engine-neutral OCR seam**
   - Implement a deterministic mock `OcrEngine`.
   - Prove cancellation, timeouts, engine replacement, malformed result
     rejection, and source-pixel coordinate mapping before integrating a real
     engine.

9. **Recovery**
   - Kill the Flutter client, native service, and optional OCR worker at each
     capture state.
   - Verify portal/session cleanup, no stuck overlay, client reconnection, and a
     bounded restart policy.

## Recommended decision

Adopt architecture 2, with the following guardrails:

- native GTK4 overlay, never Flutter multi-window for the production overlay;
- frozen captured frame rather than transparent fullscreen composition;
- native service owns all raw frames;
- D-Bus is the replaceable UI boundary;
- Flutter is an on-demand control client, themed with Yaru where appropriate;
- Ubuntu 24.04 activation uses a user-configured custom shortcut, with runtime
  GlobalShortcuts support added only on desktops that actually provide it; and
- `OcrEngine` remains an engine-neutral interface, initially in the service and
  movable behind a Unix-socket/FD boundary if evidence warrants isolation.

Choose architecture 3 instead if the next supported desktop is not a funded,
near-term requirement. Architecture 1 should not pass design review without
successful prototypes for every Flutter-specific blocker above.
