# Evaluate Flutter and native system boundaries

Type: research
Status: resolved
Blocked by:

## Question

What architecture can combine a maintainable cross-platform UI preference with reliable Ubuntu GNOME Wayland capture and overlay behavior? Evaluate Flutter Linux support for transparent or full-screen overlays, multi-window operation, keyboard and pointer hit testing, accessibility, platform channels or FFI, and libadwaita visual fidelity. Compare a Flutter-only design with hybrid Flutter plus Rust or C++ services and a GTK4/libadwaita-native design, including IPC and crash-isolation implications.

## Answer

Recommend a hybrid: use Flutter only for on-demand settings/history UI, and a
separate native GTK4 service for portal/PipeWire capture, coordinate mapping,
OCR orchestration, and the overlay. Use D-Bus for commands/results, keep raw
frames in the service, and add a Unix-socket/shared-FD OCR worker only if a real
engine later justifies crash isolation. This keeps the UI replaceable and does
not lock the OCR engine.

- Flutter-only keeps one UI stack, but production multi-window remains
  experimental, Linux transparency/window input require native runner work,
  libadwaita widgets cannot be embedded, and native faults take down the app.
- Hybrid preserves the cross-platform UI preference and removes Flutter from
  the latency- and Wayland-critical path, at the cost of two stacks/processes.
- GTK4/libadwaita-native gives the best GNOME theming, accessibility, startup,
  and integration; prefer it outright if another desktop is not a funded
  near-term target.

Blockers requiring prototypes: GNOME Wayland cannot guarantee a live
transparent always-on-top fullscreen overlay, so validate a frozen captured
frame as the fullscreen background; stock Ubuntu 24.04 GNOME 46 lacks the
GlobalShortcuts portal, so activation needs a user-created system shortcut (or
a separately scoped Shell extension); and mixed-DPI/multi-monitor coordinates,
focus/input regions, Orca behavior, portal lifecycle, recovery, and current
Flutter/native footprint must be measured.

[Full cited report](../research/03-ui-stack-boundaries.md)
