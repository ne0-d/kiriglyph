#!/usr/bin/env bash
# Second half of enter.sh: runs inside the new namespaces.
# Device nodes cannot be created in a user namespace, so bind the few the
# tools need from the host, one file each.
set -euo pipefail
ROOTFS=$1
shift
for node in null zero full random urandom tty; do
  [ -e "$ROOTFS/dev/$node" ] || : >"$ROOTFS/dev/$node"
  mount --bind "/dev/$node" "$ROOTFS/dev/$node"
done
# Shell features such as process substitution and /dev/stdin need these.
ln -sfn /proc/self/fd "$ROOTFS/dev/fd"
ln -sfn /proc/self/fd/0 "$ROOTFS/dev/stdin"
ln -sfn /proc/self/fd/1 "$ROOTFS/dev/stdout"
ln -sfn /proc/self/fd/2 "$ROOTFS/dev/stderr"
exec chroot "$ROOTFS" /usr/bin/env -i HOME=/root \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  TERM=dumb LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"
