#!/bin/bash
# Runs INSIDE the clean rootfs. Phase C: upgrade, remove, purge.
set -uo pipefail
UP=${1:-/tmp/kiriglyph_upgrade.deb}
fail=0
ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }
CONF=/etc/xdg/autostart/dev.kiriglyph.Kiriglyph.desktop

before=$(dpkg-query -W -f='${Version}' kiriglyph)
echo "== upgrade from $before, with a locally edited autostart entry"
printf '# edited by the administrator\n' >>"$CONF"
apt-get install -y -o Dpkg::Options::=--force-confold "$UP" >/tmp/apt-upgrade.log 2>&1 \
  && ok "upgrade succeeded" || { bad "upgrade failed"; tail -20 /tmp/apt-upgrade.log; }
after=$(dpkg-query -W -f='${Version}' kiriglyph)
[ "$after" != "$before" ] && ok "version changed $before -> $after" || bad "version did not change"
grep -q 'edited by the administrator' "$CONF" && ok "edited autostart entry (a conffile) was kept" || bad "conffile edit was lost"
kiriglyph --version >/dev/null && ok "launcher works after upgrade" || bad "launcher broken after upgrade"
[ -z "$(find /usr/lib/kiriglyph -name '*.dpkg-*' 2>/dev/null)" ] && ok "no leftover .dpkg-old/.dpkg-new files" || bad "leftover dpkg files"

echo "== remove"
apt-get remove -y kiriglyph >/tmp/apt-remove.log 2>&1 && ok "remove succeeded" || { bad "remove failed"; tail -10 /tmp/apt-remove.log; }
[ ! -e /usr/lib/kiriglyph ] && ok "/usr/lib/kiriglyph is gone" || bad "/usr/lib/kiriglyph still exists"
[ ! -e /usr/bin/kiriglyph ] && ok "/usr/bin/kiriglyph is gone" || bad "/usr/bin/kiriglyph still exists"
[ ! -e /usr/share/applications/dev.kiriglyph.Kiriglyph.desktop ] && ok "desktop entry is gone" || bad "desktop entry still exists"
[ -e "$CONF" ] && ok "the conffile stays after remove (normal)" || bad "conffile vanished on remove"

echo "== purge"
apt-get purge -y kiriglyph >/tmp/apt-purge.log 2>&1 && ok "purge succeeded" || { bad "purge failed"; tail -10 /tmp/apt-purge.log; }
[ ! -e "$CONF" ] && ok "the conffile is gone after purge" || bad "conffile left after purge"
left=$(find / -xdev \( -path /proc -o -path /tmp -o -path /var/lib/apt -o -path /var/cache -o -path /var/log \) -prune -o -iname '*kiriglyph*' -print 2>/dev/null | head)
[ -z "$left" ] && ok "no Kiriglyph files anywhere on the system" || { bad "files left behind:"; echo "$left"; }
dpkg --audit && ok "dpkg --audit is clean" || bad "dpkg --audit reported problems"
exit $fail
