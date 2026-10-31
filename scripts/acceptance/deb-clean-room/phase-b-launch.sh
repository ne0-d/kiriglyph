#!/bin/bash
# Runs INSIDE the clean rootfs. Phase B: the app starts, keeps its workers, and quits cleanly.
# Uses a virtual X display (the real desktop is Wayland, which cannot be faked here), so this
# proves the native libraries, Flutter assets, Dart code and worker start; it does not prove
# the Wayland-specific window behaviour.
set -uo pipefail
fail=0
ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

echo "== installing a virtual display and a session bus (test tooling only; GL, EGL and the\n   GNOME schemas must already come from the package, so they are not installed here)"
apt-get install -y xvfb xauth dbus dbus-x11 libgl1-mesa-dri >/tmp/apt-tools.log 2>&1 \
  && ok "test tooling installed" || { bad "test tooling install"; tail -15 /tmp/apt-tools.log; }

mkdir -p /tmp/xdg-run /tmp/home && chmod 700 /tmp/xdg-run
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/xdg-run XDG_CONFIG_HOME=/tmp/home/.config XDG_DATA_HOME=/tmp/home/.local/share
# Same reason as in phase A: no bytecode written under /usr/lib by a root-run test.
export PYTHONDONTWRITEBYTECODE=1
export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1

cat >/tmp/session.sh <<'SH'
#!/bin/bash
kiriglyph --background >/tmp/kiriglyph.out 2>&1 &
sleep 12
echo "--- processes after 12 s"
pgrep -a -f '/usr/lib/kiriglyph/kiriglyph' | cut -c1-110
pgrep -a -f 'worker-runtime' | cut -c1-140
echo "--- asking the resident instance to quit (a second launch forwards to it)"
kiriglyph --quit
sleep 4
echo "--- processes after --quit"
pgrep -a -f '/usr/lib/kiriglyph/' | cut -c1-110 || true
echo "(end)"
SH
chmod +x /tmp/session.sh

dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" /tmp/session.sh >/tmp/session.log 2>&1
cat /tmp/session.log

started=$(sed -n '/processes after 12 s/,/resident instance/p' /tmp/session.log | grep -c '/usr/lib/kiriglyph/kiriglyph')
worker=$(sed -n '/processes after 12 s/,/resident instance/p' /tmp/session.log | grep -c 'worker-runtime')
left=$(sed -n '/processes after --quit/,/(end)/p' /tmp/session.log | grep -c '/usr/lib/kiriglyph/')
[ "$started" -ge 1 ] && ok "the app stayed running after 12 s" || bad "the app did not stay running"
[ "$worker" -ge 1 ] && ok "its Python worker started from the bundled runtime" || bad "no worker process found"
[ "$left" -eq 0 ] && ok "--quit left no Kiriglyph or worker process" || bad "$left processes left after --quit"
if grep -q -E "Couldn't open lib|cannot open shared object" /tmp/kiriglyph.out; then bad "the app could not load a library"; else ok "no missing-library errors in the app output"; fi
if grep -q "Unhandled Exception" /tmp/kiriglyph.out; then bad "unhandled Dart exceptions in the app output"; else ok "no unhandled Dart exceptions in the app output"; fi
echo "--- app output"; head -20 /tmp/kiriglyph.out
exit $fail
