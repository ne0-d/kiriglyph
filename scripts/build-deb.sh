#!/usr/bin/env bash
# Build a local beta .deb for Ubuntu testers. The package bundles the Flutter
# release bundle, a private uv-managed Python runtime, locked worker wheels, and
# EfficientSAM-Ti models fetched and verified at build time.
set -euo pipefail
shopt -s inherit_errexit
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"
WORKER_DIR="$ROOT/worker"
PACKAGING_DIR="$ROOT/packaging"
FLUTTER="$ROOT/.tools/flutter/bin/flutter"
UV="$ROOT/.tools/uv-bin/uv"
APP_ID="dev.kiriglyph.Kiriglyph"
PACKAGE="kiriglyph"
ARCHITECTURE="$(dpkg --print-architecture)"
DIST_DIR="$ROOT/dist"
STAGING="$(mktemp -d "$ROOT/.deb-staging.XXXXXX")"
PKGROOT="$STAGING/pkg"
REQ_FILE="$STAGING/worker-requirements.txt"
PYTHON_VERSION="3.12"

cleanup() {
  /usr/bin/rm -rf "$STAGING"
}
trap cleanup EXIT

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  fi
}

version_from_pubspec() {
  awk -F': *' '$1 == "version" {print $2; exit}' "$APP_DIR/pubspec.yaml"
}

deb_safe_version() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9.+:~-' '-'
}

sh_quote() {
  local quote="'" escaped="'\\''"
  printf "'%s'" "${1//"$quote"/"$escaped"}"
}
find_flutter_bundle() {
  shopt -s nullglob
  local bundles=("$APP_DIR"/build/linux/*/release/bundle)
  shopt -u nullglob
  if ((${#bundles[@]} != 1)); then
    printf 'Expected exactly one release bundle, found %d.\n' "${#bundles[@]}" >&2
    exit 1
  fi
  printf '%s\n' "${bundles[0]}"
}

copy_icons() {
  local icon_root="$PKGROOT/usr/share/icons/hicolor"
  install -Dm644 "$APP_DIR/assets/icons/kiriglyph-symbolic.svg" \
    "$icon_root/symbolic/apps/kiriglyph-symbolic.svg"
  install -Dm644 "$APP_DIR/assets/icons/kiriglyph-attention-symbolic.svg" \
    "$icon_root/symbolic/apps/kiriglyph-attention-symbolic.svg"
  install -Dm644 "$APP_DIR/assets/icons/kiriglyph-busy-symbolic.svg" \
    "$icon_root/symbolic/apps/kiriglyph-busy-symbolic.svg"
}

stage_desktop_files() {
  install -Dm644 "$PACKAGING_DIR/linux/$APP_ID.desktop" \
    "$PKGROOT/usr/share/applications/$APP_ID.desktop"
  install -Dm644 "$PACKAGING_DIR/linux/$APP_ID.autostart.desktop" \
    "$PKGROOT/etc/xdg/autostart/$APP_ID.desktop"
  install -d "$PKGROOT/usr/share/metainfo"
  sed -e "s/@VERSION@/$VERSION/g" -e "s/@DATE@/$(date -u +%F)/g" \
    "$PACKAGING_DIR/linux/$APP_ID.metainfo.xml.in" \
    >"$PKGROOT/usr/share/metainfo/$APP_ID.metainfo.xml"
}

stage_launcher() {
  install -d "$PKGROOT/usr/bin"
  sed "s/@VERSION@/$VERSION/g" "$PACKAGING_DIR/linux/kiriglyph.in" \
    >"$PKGROOT/usr/bin/kiriglyph"
  chmod 755 "$PKGROOT/usr/bin/kiriglyph"
}

stage_worker_runtime() {
  local runtime="$PKGROOT/usr/lib/kiriglyph/worker-runtime"
  local worker_target="$PKGROOT/usr/lib/kiriglyph/worker"
  local base_python
  local python_home

  "$UV" venv --clear --relocatable --managed-python --python "$PYTHON_VERSION" "$runtime"
  "$UV" export --project "$WORKER_DIR" --locked --no-dev --no-emit-project \
    --format requirements.txt --output-file "$REQ_FILE" >/dev/null
  "$UV" pip install --python "$runtime/bin/python" --require-hashes \
    --requirements "$REQ_FILE" --link-mode copy

  base_python="$(readlink -f "$runtime/bin/python")"
  python_home="$(cd "$(dirname "$base_python")/.." && pwd)"
  install -d "$runtime/python"
  cp -a "$python_home/." "$runtime/python/"
  rm -f "$runtime/bin/python" "$runtime/bin/python3" "$runtime/bin/python3.12"
  ln -s "../python/bin/python3.12" "$runtime/bin/python"
  ln -s "python" "$runtime/bin/python3"
  ln -s "python" "$runtime/bin/python3.12"

  rm -rf "$runtime"/bin/2to3* \
    "$runtime"/bin/f2py* \
    "$runtime"/bin/idle* \
    "$runtime"/bin/idna* \
    "$runtime"/bin/normalizer* \
    "$runtime"/bin/numpy-config* \
    "$runtime"/bin/onnxruntime_test* \
    "$runtime"/bin/pip* \
    "$runtime"/bin/pydoc* \
    "$runtime"/bin/python*-config \
    "$runtime"/bin/rapidocr* \
    "$runtime"/bin/tqdm* \
    "$runtime"/lib/itcl* \
    "$runtime"/lib/libtcl* \
    "$runtime"/lib/libtk* \
    "$runtime"/lib/tcl* \
    "$runtime"/lib/tk* \
    "$runtime"/lib/thread* \
    "$runtime"/lib/python*/ensurepip \
    "$runtime"/lib/python*/idlelib \
    "$runtime"/lib/python*/lib2to3 \
    "$runtime"/lib/python*/turtledemo \
    "$runtime"/lib/python*/tkinter \
    "$runtime"/lib/python*/lib-dynload/_tkinter* \
    "$runtime"/lib/python*/site-packages/pip \
    "$runtime"/lib/python*/site-packages/pip-*.dist-info
  rm -rf "$runtime"/python/bin/2to3* \
    "$runtime"/python/bin/idle* \
    "$runtime"/python/bin/pip* \
    "$runtime"/python/bin/pydoc* \
    "$runtime"/python/bin/python*-config \
    "$runtime"/python/lib/itcl* \
    "$runtime"/python/lib/libtcl* \
    "$runtime"/python/lib/libtk* \
    "$runtime"/python/lib/tcl* \
    "$runtime"/python/lib/tk* \
    "$runtime"/python/lib/thread* \
    "$runtime"/python/lib/python*/ensurepip \
    "$runtime"/python/lib/python*/idlelib \
    "$runtime"/python/lib/python*/lib2to3 \
    "$runtime"/python/lib/python*/turtledemo \
    "$runtime"/python/lib/python*/tkinter \
    "$runtime"/python/lib/python*/lib-dynload/_tkinter* \
    "$runtime"/python/lib/python*/site-packages/pip \
    "$runtime"/python/lib/python*/site-packages/pip-*.dist-info \
    "$runtime"/.gitignore
  find "$runtime"/lib/python*/site-packages -type d \( -name 'test' -o -name 'tests' \) \
    -prune -exec rm -rf {} +
  find "$runtime" -type d -name '__pycache__' -prune -exec rm -rf {} +
  find "$runtime" -type f -name '*.py[co]' -delete

  install -d "$worker_target"
  cp -a "$WORKER_DIR/src" "$worker_target/"
  install -m 644 "$WORKER_DIR/README.md" "$worker_target/README.md"
  install -m 644 "$WORKER_DIR/pyproject.toml" "$worker_target/pyproject.toml"
}

stage_models() {
  local app_root="$PKGROOT/usr/lib/kiriglyph"
  local models="$app_root/models"
  install -d "$models"
  PYTHONPATH="$app_root/worker/src" \
    KIRIGLYPH_MODELS_DIR="$models" \
    "$app_root/worker-runtime/bin/python" -m worker.segmentation_models >/dev/null
  PYTHONPATH="$app_root/worker/src" \
    KIRIGLYPH_MODELS_DIR="$models" \
    "$app_root/worker-runtime/bin/python" - <<'PY'
from worker.segmentation_models import verify_assets
verify_assets()
PY
}

stage_debian_metadata() {
  local debian="$PKGROOT/DEBIAN"
  install -d "$debian"
  install -m 755 "$PACKAGING_DIR/linux/postinst" "$debian/postinst"

  local depends installed_size
  depends="$(compute_depends)"
  # apt uses this to check free disk space before it unpacks the package.
  installed_size="$(du -sk --exclude=DEBIAN "$PKGROOT" | cut -f1)"
  cat >"$debian/control" <<EOF
Package: $PACKAGE
Version: $DEB_VERSION
Section: utils
Priority: optional
Architecture: $ARCHITECTURE
Installed-Size: $installed_size
Maintainer: Kiriglyph contributors <noreply@example.invalid>
Homepage: https://github.com/ne0-d/kiriglyph
Depends: $depends
Recommends: fonts-ubuntu
Description: Select and copy text from anything on screen, locally
 Kiriglyph freezes the screen on a keyboard shortcut. Drag over any text to
 copy it, or click an object to cut it out as a transparent PNG.
 .
 Text recognition and object segmentation run on this computer, with no
 cloud service. It needs Ubuntu with GNOME on Wayland. This is a beta release.
EOF

  cat >"$debian/triggers" <<'EOF'
interest-noawait /usr/share/applications
interest-noawait /usr/share/icons/hicolor
EOF
  cat >"$debian/conffiles" <<EOF
/etc/xdg/autostart/$APP_ID.desktop
EOF
}

compute_depends() {
  # Libraries the ldd scan below cannot see because they are loaded at run time:
  # Flutter opens EGL and GLES (the app aborts at start-up without them), and the
  # app reads GNOME's desktop settings schemas. A GNOME desktop always has all of
  # these; naming them keeps a minimal system honest.
  local explicit=(
    "libgtk-3-0t64 | libgtk-3-0"
    "libglib2.0-0t64 | libglib2.0-0"
    "libglib2.0-bin"
    "xdg-utils"
    "libegl1"
    "libgles2"
    "gsettings-desktop-schemas"
  )
  local discovered="$STAGING/discovered-depends.txt"
  : >"$discovered"
  while IFS= read -r -d '' file_path; do
    if ! file -b "$file_path" | grep -q '^ELF '; then
      continue
    fi
    ldd "$file_path" 2>/dev/null |
      awk '/=> \// {print $3} /^\// {print $1}' |
      while IFS= read -r lib_path; do
        dpkg-query -S "$lib_path" 2>/dev/null | awk -F: '{print $1}' | sed 's/:.*//' || true
      done >>"$discovered"
  done < <(find "$PKGROOT/usr/lib/kiriglyph" -type f -print0)

  {
    printf '%s\n' "${explicit[@]}"
    sort -u "$discovered"
  } |
    awk 'NF && !seen[$0]++ {items[++count]=$0} END {for (i=1; i<=count; i++) printf "%s%s", (i == 1 ? "" : ", "), items[i]}'
}

stage_docs() {
  local doc_dir="$PKGROOT/usr/share/doc/$PACKAGE"
  install -d "$doc_dir"
  "$ROOT/packaging/generate_notice.py" \
    --repo-root "$ROOT" \
    --worker-runtime "$PKGROOT/usr/lib/kiriglyph/worker-runtime" \
    --version "$VERSION" \
    --output "$doc_dir/NOTICE"
  cat >"$doc_dir/README.Debian" <<'EOF'
Kiriglyph beta package

This package starts Kiriglyph from /usr/bin/kiriglyph and installs a system
autostart entry. Users can disable launch-at-login in the app; the app writes a
Hidden=true override under ~/.config/autostart when the system entry exists.

Package removal leaves user data untouched, including screenshot portal grants
and ~/.local/share/kiriglyph. To reset those manually, remove the GNOME custom
shortcut in Settings, delete ~/.local/share/kiriglyph if present, and revoke the
screenshot permission from GNOME's privacy settings or the portal permission
store.
EOF
  cat >"$doc_dir/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Kiriglyph
Source: https://github.com/ne0-d/kiriglyph

Files: *
Copyright: 2026 Kiriglyph contributors
License: Apache-2.0
Comment: Bundled third-party components (the Flutter engine, the Python
 runtime and wheels, the OCR and segmentation models) keep their own
 licences. NOTICE lists them, and their licence texts ship with them.

License: Apache-2.0
 Licensed under the Apache License, Version 2.0. On Debian and Ubuntu systems
 the full text is in /usr/share/common-licenses/Apache-2.0.
EOF
  # A native package keeps its changelog in Debian format. The release notes
  # themselves live in CHANGELOG.md and on the GitHub release.
  {
    printf '%s (%s) unstable; urgency=medium\n\n' "$PACKAGE" "$DEB_VERSION"
    printf '  * Release %s. Notes: https://github.com/ne0-d/kiriglyph/releases\n\n' "$VERSION"
    printf ' -- Kiriglyph contributors <noreply@example.invalid>  %s\n' "$(date -R -u)"
  } | gzip -9n >"$doc_dir/changelog.gz"
  install -Dm644 /dev/stdin "$PKGROOT/usr/share/man/man1/$PACKAGE.1.gz" \
    < <(gzip -9nc "$PACKAGING_DIR/linux/$PACKAGE.1")
  install -Dm644 "$PACKAGING_DIR/linux/$PACKAGE.lintian-overrides" \
    "$PKGROOT/usr/share/lintian/overrides/$PACKAGE"
}

build_package() {
  mkdir -p "$DIST_DIR" "$PKGROOT/usr/lib/kiriglyph"
  local bundle
  bundle="$(find_flutter_bundle)"
  cp -a "$bundle/." "$PKGROOT/usr/lib/kiriglyph/"
  stage_worker_runtime
  stage_models
  find "$PKGROOT/usr/lib/kiriglyph" -type d -name '__pycache__' -prune -exec rm -rf {} +
  find "$PKGROOT/usr/lib/kiriglyph" -type f -name '*.py[co]' -delete
  stage_launcher
  stage_desktop_files
  copy_icons
  stage_docs
  stage_debian_metadata
  find "$PKGROOT" -type d -exec chmod 755 {} +
  find "$PKGROOT" -type f -exec chmod u+rw,go+r,go-w,a-x {} +
  chmod 755 "$PKGROOT/usr/bin/kiriglyph" \
    "$PKGROOT/usr/lib/kiriglyph/kiriglyph" \
    "$PKGROOT/usr/lib/kiriglyph/worker-runtime/bin/python3.12" \
    "$PKGROOT/DEBIAN/postinst"

  local out="$DIST_DIR/${PACKAGE}_${DEB_VERSION}_${ARCHITECTURE}.deb"
  dpkg-deb --root-owner-group -Zxz --build "$PKGROOT" "$out"
  # A fixed name, so a release can be downloaded from a permanent link:
  # https://github.com/ne0-d/kiriglyph/releases/latest/download/kiriglyph_amd64.deb
  cp -f "$out" "$DIST_DIR/${PACKAGE}_${ARCHITECTURE}.deb"
  (cd "$DIST_DIR" && sha256sum "${PACKAGE}_${ARCHITECTURE}.deb" >SHA256SUMS)
  printf '%s\n' "$out"
}

require_tool dpkg
require_tool dpkg-deb
require_tool dpkg-query
require_tool file
require_tool ldd

VERSION="$(version_from_pubspec)"
DEB_VERSION="$(deb_safe_version "$VERSION")"

if [[ ! -x "$FLUTTER" ]]; then
  printf 'Flutter tool not found: %s\n' "$FLUTTER" >&2
  exit 1
fi
if [[ ! -x "$UV" ]]; then
  printf 'uv tool not found: %s\n' "$UV" >&2
  exit 1
fi

if [[ "${KIRIGLYPH_REUSE_FLUTTER_BUILD:-0}" == "1" ]]; then
  printf 'Reusing existing Kiriglyph %s release bundle...\n' "$VERSION"
else
  printf 'Building Kiriglyph %s release bundle...\n' "$VERSION"
  (cd "$APP_DIR" && "$FLUTTER" build linux --release)
fi

printf 'Staging Debian package...\n'
DEB_PATH="$(build_package)"
printf 'Built %s\n' "$DEB_PATH"
