# Research Ubuntu Wayland capture and overlay integration

Type: research
Status: resolved
Blocked by:

## Question

On Ubuntu 24.04 GNOME Wayland, which supported APIs and integration mechanisms can provide an explicit global shortcut, screen/region/window capture, a native-feeling full-screen selection overlay, clipboard output, multi-monitor and fractional-scaling correctness, and secure operation? Identify portal, PipeWire, GNOME Shell, Mutter, layer-shell, D-Bus, and permission constraints; distinguish public supported paths from brittle or private APIs.

## Answer

Recommend a user-created GNOME Custom Shortcut that launches the application, followed by `org.freedesktop.portal.Screenshot` with `interactive=true`. This reuses GNOME Shell's native frozen-frame selector for area, screen, and window capture; OCR the returned image and copy confirmed text with `GdkClipboard`.

Top blockers are that Ubuntu 24.04's GNOME 46 backend does not implement the Global Shortcuts portal, Screenshot v2 cannot request a specific target mode, Mutter does not implement layer-shell, and an ordinary Wayland client cannot guarantee a Shell-level always-on-top overlay. If a custom overlay becomes mandatory, use ScreenCast/PipeWire to freeze selected monitor streams and paint one GTK fullscreen window per monitor, accepting chooser, scaling, focus, and compositor-policy constraints.

[Detailed research report](../research/01-wayland-capture-overlay.md)
