# Silent-capture spike runbook (issue 16)

Throwaway. Results land in `/tmp/live-text-spike/*.json`; `place` also saves
screen crops under `/tmp/live-text-spike/place-*/` (private — never copy them
into the repo).

```sh
cd "spikes/silent-capture"
S() { /usr/bin/python3 capture_spike.py "$@"; }
```

Steps below write `$S`; with this function, type `S` (works in zsh and bash).

## Steps

1. `$S install`, then `$S lookup`. Expect `"spike_app": null`.
2. `$S grant`. Click **Request screenshot permission** while its window is
   focused. GNOME should ask "Allow Live Text Capture Spike to Take
   Screenshots?". Click **Allow**. Expect `"outcome": "captured"`,
   `"spike_app": ["yes"]`, `"empty_id_present": false`.
   If no dialog appears and the outcome is `ended`, run
   `journalctl --user -u xdg-desktop-portal -n 20` and report it. Then try
   launching "Live Text Capture Spike" from Activities instead.
3. `$S measure`. Watch the screen and listen. You'll see 10 captures, one
   per second. Answer the flash/sound prompts.
4. Placement at 100%, once for each display. Run the command, move the
   pointer onto the named display within 3 seconds, and keep it still:
   - `$S place --label hdmi-100 --pointer-on HDMI-1`
   - `$S place --label edp-100 --pointer-on eDP-1`

   Watch for these things: which display goes "frozen"; any flash, shift,
   blur, or black frame; and whether the other display stays live. Press
   Escape, or wait 20 seconds.
5. Fractional scaling: Settings → Displays → Built-in display → Scale
   **125%** → Apply → Keep Changes. Then:
   - `$S display-state` (expect eDP-1 `"scale": 1.25`)
   - `$S place --label edp-125 --pointer-on eDP-1`
   - `$S place --label hdmi-mixed --pointer-on HDMI-1`

   Then set the scale back to 100%.
6. Only if a window opened on the wrong display: rerun that case with
   `--monitor 0` and `--monitor 1`, using the GTK index from the JSON.
7. Cleanup: `$S uninstall` (expect `"spike_app": null`). Once the results have
   been read, run `rm -rf /tmp/live-text-spike`.

## Research notes

**Verified** (source + local test). xdg-desktop-portal derives a host app ID
in two ways:

- **Systemd unit:** the caller's unit, `app[-<launcher>]-<id>-<random>.scope`,
  `.slice`, or `.service`. This only counts if `<id>.desktop` exists
  (`src/xdp-app-info-host.c`, 1.21.1).
- **Registration:** `org.freedesktop.host.portal.Registry.Register`
  (`data/org.freedesktop.host.portal.Registry.xml`, `src/registry.c`).

Rules for `Register`:

- **One connection:** it applies to one D-Bus connection (unique name).
- **Once only:** a second call fails ("already associated").
- **Before portal calls:** it must come before any portal method call on that
  connection. Locally, `Settings.ReadOne` first caused a failure, but
  `Properties.Get` first did not.
- **Desktop file required:** without one it fails with "App info not found";
  with one it succeeds.
- **Not for sandboxed apps:** sandboxed callers are refused.
- **No proof of identity:** any host process can claim any ID.

GNOME Shell shows the access dialog only if `<id>.desktop` is the focused app
(`js/ui/accessDialog.js`, 50.1). A denial is stored as `no`.

**Verified locally:** a GTK 3.24.52 `Gtk.Application` had already used its
shared session connection for a portal call before `activate`, so
`Register` failed there. The Flutter app must register on a private
connection, or in its helper process, before any capture call.

**Verified (Mutter source):** the image is sized `round(stage × max view
scale)`. Displays below the maximum scale are therefore upsampled, and are
never native there.

**Inference:** at 125%, GTK3 renders at scale 2. The compositor then
downsamples the frame, so the frozen frame is resampled twice and cannot be
guaranteed pixel-identical. `place` measures how large the difference is.
Alternatives:

- accept a slight blur;
- prefer integer scales;
- use a GTK4 (≥4.14, fractional-scale-v1) overlay helper;
- use ScreenCast for native per-display frames.
