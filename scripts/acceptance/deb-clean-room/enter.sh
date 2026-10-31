#!/usr/bin/env bash
# Runs one command inside the throwaway Ubuntu 26.04 rootfs, rootless.
# A user namespace maps the current user to root and the user's sub-IDs to the other IDs, so
# dpkg's chown calls behave as on a real install.
# usage: enter.sh <rootfs> <command> [args...]
set -euo pipefail
ROOTFS=$1
shift
exec unshare --map-root-user --map-auto --mount --pid --fork --kill-child \
  --mount-proc="$ROOTFS/proc" "$(dirname "$0")/chroot-step.sh" "$ROOTFS" "$@"
