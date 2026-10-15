#!/usr/bin/env bash
# Removes what install-desktop.sh installed and the app's stored screenshot
# grant. It never changes GNOME settings; remove the custom shortcut yourself.
# Also cleans up leftovers from the pre-Kiriglyph Live Text install if present.
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

OLD_APP_ID="dev.livetext.LiveText"
NEW_APP_ID="dev.kiriglyph.Kiriglyph"
OLD_LAUNCHER="$HOME/.local/bin/live-text"
NEW_LAUNCHER="$HOME/.local/bin/kiriglyph"

delete_screenshot_permission() {
  local app_id="$1"
  if gdbus call --session \
    --dest org.freedesktop.impl.portal.PermissionStore \
    --object-path /org/freedesktop/impl/portal/PermissionStore \
    --method org.freedesktop.impl.portal.PermissionStore.DeletePermission \
    screenshot screenshot "$app_id" >/dev/null 2>&1; then
    printf 'Removed the screenshot permission for %s.\n' "$app_id"
  else
    printf 'No screenshot permission was stored for %s.\n' "$app_id"
  fi
}

instance_running() {
  local app_id="$1"
  gdbus call --session --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner "$app_id" 2>/dev/null |
    grep -q true
}

stop_instance() {
  local app_id="$1"
  local launcher="$2"
  local label="$3"
  if [[ -x "$launcher" ]] && instance_running "$app_id"; then
    printf 'Stopping the running %s instance...\n' "$label"
    timeout 10 "$launcher" --quit >/dev/null 2>&1 || true
    for _ in $(seq 50); do
      instance_running "$app_id" || break
      sleep 0.1
    done
  fi
}

remove_identity() {
  local app_id="$1"
  local launcher="$2"
  local data_subdir="$3"
  local desktop_file="$DATA_HOME/applications/$app_id.desktop"
  local autostart_file="$CONFIG_HOME/autostart/$app_id.desktop"

  rm -f "$autostart_file" "$desktop_file" "$launcher"
  rm -rf "$DATA_HOME/$data_subdir"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$(dirname "$desktop_file")" >/dev/null 2>&1 || true
  fi

  delete_screenshot_permission "$app_id"
}

stop_instance "$OLD_APP_ID" "$OLD_LAUNCHER" "Live Text"
remove_identity "$OLD_APP_ID" "$OLD_LAUNCHER" "live-text"

stop_instance "$NEW_APP_ID" "$NEW_LAUNCHER" "Kiriglyph"
remove_identity "$NEW_APP_ID" "$NEW_LAUNCHER" "kiriglyph"

printf 'Kiriglyph is uninstalled. Remove its GNOME custom shortcut in Settings if you added one.\n'
