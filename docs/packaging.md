# Kiriglyph beta Debian package

Build the local beta package from the repository root:

```bash
./scripts/build-deb.sh
```

The script writes `dist/kiriglyph_<version>_<arch>.deb`. It builds the Flutter
Linux release bundle, creates a private uv-managed Python runtime, installs the
locked worker wheels from `worker/uv.lock`, fetches and verifies the
EfficientSAM-Ti ONNX models, generates a bundled-component notice, and stages a
Debian package under a temporary `.deb-staging*` directory.

The installed layout is:

- `/usr/lib/kiriglyph/`: Flutter release bundle.
- `/usr/lib/kiriglyph/worker-runtime/`: bundled Python runtime and wheels.
- `/usr/lib/kiriglyph/worker/`: worker source used by the app.
- `/usr/lib/kiriglyph/models/`: EfficientSAM-Ti model files.
- `/usr/bin/kiriglyph`: stable launcher that sets worker and model paths.
- `/etc/xdg/autostart/dev.kiriglyph.Kiriglyph.desktop`: system autostart entry.

Use `kiriglyph --setup` after installing to print the GNOME shortcut steps. It
offers to create the shortcut with `gsettings`, but only after an explicit
confirmation. Package removal intentionally leaves user data and portal grants
in place.
