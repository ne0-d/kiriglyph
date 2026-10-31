#!/usr/bin/env bash
# Tries the Kiriglyph .deb on a clean Ubuntu, without root, Docker or a VM.
#
# It unpacks the official Ubuntu base image into a throwaway folder, enters it
# with a user namespace and chroot, and runs three phases there:
#   A  install with apt, then check libraries, models and offline OCR
#   B  start the app on a virtual display and quit it
#   C  upgrade, remove and purge
#
# What it proves: the declared dependencies are enough, the bundled Python
# runtime and models work from /usr/lib, and install, upgrade, removal and
# purge leave nothing behind. What it does not prove: anything about the real
# Wayland desktop (window placement, the portal, the top-bar icon). Phase B
# uses a virtual X display, so those still need a real session.
#
# Network use: it downloads the Ubuntu base image once (about 35 MB, checked
# against Ubuntu's signed checksums), and apt downloads packages inside the
# sandbox. Nothing is installed on this computer.
#
# Usage:
#   scripts/acceptance/deb-clean-room/run.sh [path/to/kiriglyph_amd64.deb]
#   scripts/acceptance/deb-clean-room/run.sh --clean     # delete the sandbox
#
# Needs: unshare, newuidmap, an /etc/subuid range for your user, ar, tar, xz,
# curl, gpgv, sha256sum, and ubuntu-keyring (all standard on Ubuntu).
set -euo pipefail
shopt -s inherit_errexit

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RELEASE="${KIRIGLYPH_BASE_RELEASE:-26.04}"
WORK="${KIRIGLYPH_CLEAN_ROOM_DIR:-$ROOT/scripts/acceptance/output/deb-clean-room}"
BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/$RELEASE/release"
TARBALL="ubuntu-base-$RELEASE-base-amd64.tar.gz"
KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
ROOTFS="$WORK/rootfs"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# The sandbox's files belong to IDs from your sub-ID range, so only a user
# namespace that maps them can delete them.
remove_in_namespace() {
  local target=$1
  [[ "$target" == */deb-clean-room/* || "$target" == */deb-clean-room ]] ||
    die "refusing to delete $target"
  [[ -e "$target" ]] || return 0
  unshare --map-root-user --map-auto -- /usr/bin/rm -rf -- "$target"
}

if [[ "${1:-}" == "--clean" ]]; then
  remove_in_namespace "$WORK"
  printf 'Removed %s\n' "$WORK"
  exit 0
fi

DEB="${1:-$ROOT/dist/kiriglyph_amd64.deb}"
[[ -f "$DEB" ]] || die "no package at $DEB (run scripts/build-deb.sh first)"

for tool in unshare newuidmap ar tar xz curl gpgv sha256sum; do
  command -v "$tool" >/dev/null || die "missing tool: $tool"
done
[[ -f "$KEYRING" ]] || die "missing $KEYRING (package ubuntu-keyring)"
grep -q "^$(id -un):" /etc/subuid || die "no /etc/subuid range for $(id -un)"
unshare --map-root-user --map-auto true 2>/dev/null ||
  die "this system does not allow unprivileged user namespaces"

mkdir -p "$WORK/download"

echo "== Ubuntu $RELEASE base image"
if [[ ! -f "$WORK/download/$TARBALL" ]]; then
  (cd "$WORK/download" &&
    curl -sS -f -O "$BASE_URL/$TARBALL" -O "$BASE_URL/SHA256SUMS" -O "$BASE_URL/SHA256SUMS.gpg")
fi
(cd "$WORK/download" &&
  gpgv --keyring "$KEYRING" SHA256SUMS.gpg SHA256SUMS 2>&1 | grep -E 'Good signature' &&
  grep " \*\?$TARBALL\$" SHA256SUMS | sha256sum -c -)

echo "== fresh root filesystem"
remove_in_namespace "$ROOTFS"
mkdir -p "$ROOTFS"
unshare --map-root-user --map-auto -- tar -xzf "$WORK/download/$TARBALL" \
  -C "$ROOTFS" --numeric-owner --exclude='./dev/*'
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
printf 'APT::Sandbox::User "root";\nAcquire::Languages "none";\nAPT::Install-Recommends "false";\n' \
  >"$ROOTFS/etc/apt/apt.conf.d/99sandbox"
printf '#!/bin/sh\nexit 101\n' >"$ROOTFS/usr/sbin/policy-rc.d"
chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"

enter() { "$HERE/enter.sh" "$ROOTFS" "$@"; }
enter /usr/bin/apt-get update >/dev/null

echo "== staging the package"
cp "$DEB" "$ROOTFS/tmp/kiriglyph_amd64.deb"
# An "upgrade" is the same package with a higher version, made by rewriting
# only the control member, so the 170 MB payload is not unpacked.
upgrade_dir="$(mktemp -d)"
trap '/usr/bin/rm -rf -- "$upgrade_dir"' EXIT
cp "$DEB" "$upgrade_dir/kiriglyph_upgrade.deb"
(
  cd "$upgrade_dir"
  ar x kiriglyph_upgrade.deb control.tar.xz
  mkdir control
  tar -xJf control.tar.xz -C control
  sed -i 's/^Version: .*/Version: 99.0.0+upgrade/' control/control
  tar -cJf control.tar.xz -C control .
  ar r kiriglyph_upgrade.deb control.tar.xz
)
cp "$upgrade_dir/kiriglyph_upgrade.deb" "$ROOTFS/tmp/kiriglyph_upgrade.deb"
for phase in phase-a-install.sh phase-b-launch.sh phase-c-lifecycle.sh; do
  install -m 755 "$HERE/$phase" "$ROOTFS/tmp/$phase"
done

status=0
run_phase() {
  local label=$1
  shift
  echo
  echo "################ $label"
  if "$@"; then
    echo "-------- $label: OK"
  else
    echo "-------- $label: FAILED"
    status=1
  fi
}
run_phase "Phase A: install and static checks" enter /tmp/phase-a-install.sh /tmp/kiriglyph_amd64.deb
run_phase "Phase B: start and quit on a virtual display" enter /tmp/phase-b-launch.sh
run_phase "Phase C: upgrade, remove, purge" enter /tmp/phase-c-lifecycle.sh /tmp/kiriglyph_upgrade.deb

echo
if ((status == 0)); then
  echo "CLEAN ROOM PASSED"
else
  echo "CLEAN ROOM FAILED"
fi
echo "The sandbox is kept in $WORK; delete it with: $0 --clean"
exit "$status"
