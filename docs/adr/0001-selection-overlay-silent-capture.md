# 0001: Selection overlay over a silent portal capture

**Status:** accepted

The shipping app ID is `dev.kiriglyph.Kiriglyph` (renamed from
`dev.livetext.LiveText` in issue 22).

## Context

Issue 07 shipped capture through GNOME's interactive screenshot picker. It
works, but it feels like opening a separate screenshot tool: the user picks an
area, GNOME saves a file, and results appear in a normal window. The product
goal is closer to Circle to Search: press a shortcut and the desktop itself
becomes selectable.

On Wayland only the compositor can read the screen, so any capture still goes
through a GNOME portal.

## Decision

- A GNOME shortcut activates the resident, autostarted app. It takes a
  non-interactive XDG Screenshot portal capture, crops the display under the
  pointer, and shows it in a borderless fullscreen overlay on that display
  only. Other displays stay live.
- Silent capture is granted once through GNOME's access dialog, triggered from
  the app's focused window, and stored against the app's real application ID.
- The app deletes the exact file the portal returned immediately after reading.

## Evidence (Ubuntu 26.04, GNOME 50.1, two displays at scale 1.0)

- A non-interactive request with no stored grant fails at once with response 2;
  the portal logs "Only the focused app is allowed to show a system access
  dialog" when the caller is not the focused app.
- Run from a focused GNOME Terminal, the dialog appears once. After Allow, the
  next request returns without a dialog.
- Unidentified host processes are stored under an empty app ID, so a grant
  given to them applies to every unidentified host program. The app must have
  a real ID and desktop file.
- The image spans all displays (4480×1440 for 2560×1440 plus 1920×1080 side by
  side; unused area is black). It is written to `~/Pictures/Screenshot.png`,
  then `Screenshot-1.png`, with no clipboard copy, notification, or
  `Pictures/Screenshots` entry.

## Spike findings so far (issue 16)

These were verified without showing a dialog or taking a capture:

- **Registering an app ID:** `org.freedesktop.host.portal.Registry.Register`
  gives an unsandboxed connection a real app ID.
  - Without `~/.local/share/applications/<id>.desktop` it fails with "App info
    not found". With the file it succeeds.
  - It works once per connection.
  - It fails after any portal method call on that connection.
- **GTK3 startup blocks registration:** a GTK 3.24 `Gtk.Application` makes a
  portal call on its shared session connection during startup. Registration
  must therefore use a private connection, or a helper process.
- **Captures are rendered at the highest display scale:** GNOME Shell renders
  the image at the largest scale of any display. A display at a lower scale is
  upsampled in the capture.

## Rejected alternatives

- **Keep the interactive picker:** reliable, but does not feel like the
  desktop becoming selectable.
- **ScreenCast portal (PipeWire):** per-display frames and no file, but needs
  a video pipeline and briefly shows GNOME's screen-sharing indicator.
- **Overlay on every display:** needs Flutter's experimental multi-window
  support; deferred.

## Manual spike results (issue 16, two displays at 100%)

- **Grant:** with app ID `dev.livetext.CaptureSpike` registered and its window
  focused, GNOME showed the dialog once; the grant was stored as
  `dev.livetext.CaptureSpike: yes`, with no empty-ID entry.
- **Latency:** after the grant, 10 hidden captures took a median of 520 ms
  (518–526 ms) without a dialog.
- **Flash and sound:** every capture flashes the screen and plays GNOME's
  shutter sound. The portal offers no option to suppress either. Accepted: the
  overlay's entry animation starts from the flash.
- **Placement:** an undecorated fullscreen GTK3 window opened on the display
  under the pointer for both displays.
- **Pixel match:** the cropped frame drawn 1:1 was pixel-identical to a fresh
  capture of that display (maximum channel difference 0). The window drew its
  first frame about 360 ms after being shown.
- **Pictures folder:** each returned file was deleted, and nothing else in
  Pictures changed.

## Open questions

- Fractional scaling was not tested by user decision. GTK3 renders at an
  integer scale, so at 125% the frozen frame is expected to be resampled and
  slightly soft. Revisit in the overlay acceptance (issue 18).
