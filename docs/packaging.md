# The Kiriglyph Debian package

Build it from the repository root:

```bash
./scripts/build-deb.sh
```

The script builds the Flutter Linux release bundle, creates a private
uv-managed Python runtime, installs the locked worker wheels from
`worker/uv.lock`, fetches and verifies the EfficientSAM-Ti ONNX models,
generates the bundled-component notice, and stages a Debian package in a
temporary `.deb-staging*` directory. It writes three files to `dist/`:

- `kiriglyph_<version>_<arch>.deb`, the package.
- `kiriglyph_amd64.deb`, a copy with a **fixed name**. Upload this one to a
  release and the README's download link
  (`releases/latest/download/kiriglyph_amd64.deb`) always points at the newest.
- `SHA256SUMS`, the checksum of that file, attached to the release too.

`KIRIGLYPH_REUSE_FLUTTER_BUILD=1 ./scripts/build-deb.sh` skips the Flutter build
and reuses `app/build/linux/x64/release/bundle`, which saves time when only
packaging files changed.

## Installed layout

- `/usr/lib/kiriglyph/`: Flutter release bundle.
- `/usr/lib/kiriglyph/worker-runtime/`: bundled Python runtime and wheels.
- `/usr/lib/kiriglyph/worker/`: worker source used by the app.
- `/usr/lib/kiriglyph/models/`: EfficientSAM-Ti model files.
- `/usr/bin/kiriglyph`: stable launcher that sets worker and model paths.
- `/etc/xdg/autostart/dev.kiriglyph.Kiriglyph.desktop`: system autostart entry
  (a conffile).
- `/usr/share/doc/kiriglyph/`: `copyright`, `changelog.gz`, `NOTICE`,
  `README.Debian`. Plus a man page and the desktop entry, icons and AppStream
  data.

The package does not set up the shortcut: its install scripts run as root,
outside the user's session. Instead, the first time the user opens Kiriglyph it
adds its own GNOME shortcut
([ADR 0003](adr/0003-app-sets-its-own-shortcut-on-first-run.md)), so setup is
install, open, click Allow. `kiriglyph --setup` still prints the steps and can
create the shortcut after an explicit confirmation. Package removal
intentionally leaves user data and portal grants in place. There is no `prerm`:
removal stops nothing, and an empty maintainer script is a lintian warning.

## Licence and notices

Kiriglyph is under Apache-2.0 ([ADR 0004](adr/0004-apache-2-licence.md)). The
repository has `LICENSE` and `NOTICE`. The package ships a machine-readable
`copyright` that points at `/usr/share/common-licenses/Apache-2.0`.

`packaging/generate_notice.py` writes `/usr/share/doc/kiriglyph/NOTICE`, the
inventory of everything bundled:

- Python wheels: from each wheel's own metadata.
- Dart packages: the ones the app's dependency graph links (not the ones only
  tests and lints use), with each licence read from the package's licence file.
  The Flutter framework and engine licences are in
  `data/flutter_assets/NOTICES.Z`, which the Flutter build generates.
- The runtime and models: stated in the script, with the sources of the claims
  (rapidocr ships `MODEL_LICENSES.md`; EfficientSAM-Ti is Apache-2.0).

**Before a release, the notice must contain no `UNVERIFIED` row.** If one
appears, find the licence and teach the script about it. A new dependency with a
copyleft licence needs a decision record first.

## Checks before a release

```bash
lintian dist/kiriglyph_amd64.deb
desktop-file-validate packaging/linux/dev.kiriglyph.Kiriglyph.desktop \
  packaging/linux/dev.kiriglyph.Kiriglyph.autostart.desktop
appstreamcli validate --no-net <(sed -e s/@VERSION@/0.1.0/ -e s/@DATE@/2026-01-01/ \
  packaging/linux/dev.kiriglyph.Kiriglyph.metainfo.xml.in)
```

`packaging/linux/kiriglyph.lintian-overrides` accepts a short list of lintian
tags on purpose, and each one is scoped to third-party files so lintian still
catches mistakes in Kiriglyph's own:

| Tag | Why it is accepted |
| --- | --- |
| `unstripped-binary-or-object` | The Python runtime and wheels are shipped as their authors built them. Flutter's `libapp.so` is a Dart snapshot and must never be stripped. |
| `embedded-library` | Pillow, OpenCV and the standalone CPython bundle their own codec and compression libraries by design. Their licences are in the notice. |
| `custom-library-search-path` | A manylinux wheel (shapely) sets an unused `/usr/local/lib64` RUNPATH. |
| `hardening-no-pie` | The standalone CPython is not a position-independent executable. |
| `shared-library-lacks-prerequisites` | `libapp.so` is a Dart snapshot, and numpy ships test modules. |
| `script-not-executable`, `unusual-interpreter`, `shell-script-fails-syntax-check` | Helper scripts inside Python and its wheels that nothing here runs, or Python files lintian misreads as shell. |

Plugin libraries must not carry the build machine's path. The Flutter plugin
libraries are installed by copying, so CMake never rewrites their search path;
`app/linux/CMakeLists.txt` sets `CMAKE_BUILD_WITH_INSTALL_RPATH` so they are
built with the right one. After a build, `readelf -d` on each `lib/*.so` should
show only `$ORIGIN` paths.

## Clean-machine test

`scripts/acceptance/deb-clean-room/run.sh` tries the built package on a fresh
Ubuntu 26.04 root filesystem, with no root, Docker or VM
([how it works](../scripts/acceptance/README.md#package-clean-room-check)). Run
it after every package build; it prints `CLEAN ROOM PASSED`. It covers:

- **Install** with apt, so the declared dependencies must be enough; every ELF
  file must resolve all its libraries; the bundled models must match their
  pinned hashes; the bundled OCR must read text offline; both segmentation
  models must load.
- **Start** the app on a virtual display: it must stay up, start its Python
  worker from the bundled runtime, log no missing library or unhandled
  exception, and leave no process after `kiriglyph --quit`.
- **Upgrade** (an edited conffile must survive), **remove**, and **purge**
  (nothing of Kiriglyph may remain on the system).

It cannot see anything specific to the real Wayland desktop (window placement,
the screenshot portal, the top-bar icon), so those stay manual.

What it caught for 0.1.0, all fixed:

- The app aborted at start-up on a minimal system: Flutter opens EGL and GLES
  at run time, which the link-time scan cannot see, so `libegl1` and `libgles2`
  are now declared. `gsettings-desktop-schemas` is declared for the same reason.
- The plugin libraries searched the build machine's directory, and then
  `$ORIGIN/lib`, for the engine library instead of their own folder.
- The package had no `Installed-Size`, so apt would have shown "0 kB".

Two things it shows that are accepted:

- The package ships no `.pyc` files, so Python compiles the worker's libraries
  at each start. Measured: importing them takes about 0.5 s instead of 0.2 s,
  once per login, because the worker stays resident. Not worth a larger package.
  (The test runs Python with `-B`, as a normal user cannot write into
  `/usr/lib`, so it does not leave bytecode behind.)
- Flutter's compiled snapshot (`lib/libapp.so`) records one build path, the
  generated plugin registrant's file URI. It is harmless, and the check skips
  that one file.

## Releasing

1. Set the new version in `app/pubspec.yaml` (`0.1.0+1` is version 0.1.0, build
   1) and add its section to `CHANGELOG.md`.
2. `./scripts/check.sh full --build` must print `CHECK PASSED`.
3. `./scripts/build-deb.sh`, then the checks above.
4. Commit, then tag it and push the tag: `git tag v0.1.0 && git push origin v0.1.0`.
5. On GitHub choose **Releases → Draft a new release**, pick the tag, paste the
   changelog section as the notes, and attach `dist/kiriglyph_amd64.deb` (keep
   that exact name) and `dist/SHA256SUMS`.
6. Publish it as a normal release, **not** marked "pre-release", even for a beta
   (say so in the title). GitHub's `releases/latest` link skips pre-releases, so
   the README's one-click download would stop working. The `gh` command does the
   same: `gh release create v0.1.0 dist/kiriglyph_amd64.deb dist/SHA256SUMS
   --title "Kiriglyph 0.1.0 (beta)" --notes-file <notes>`.
7. Open the download link in a private window, and install from it on a machine
   that has never had Kiriglyph.
