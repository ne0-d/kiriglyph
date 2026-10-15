#!/usr/bin/env bash
set -euo pipefail

APP_PATTERN='dev.kiriglyph.Kiriglyph|kiriglyph'
WORKER_PATTERN='worker($| )|worker\.segmentation_worker|worker\.portal_capture'
INTERVAL='0.5'
ACTIVATIONS='50'
SETTLE_SECONDS='3'
OUTPUT_DIR='.scratch/ubuntu-live-text-v0/evidence/resource-runs'
AUTO='0'
SELF_TEST='0'

usage() {
  cat <<'EOF'
Usage: scripts/acceptance/measure-resources.sh [options]

Samples Kiriglyph, OCR worker, and segmentation worker process resources while
you trigger shortcut activations. By default it only prints prompts; it does
not launch the app or capture the screen.

Options:
  --activations N       Number of activations to measure (default: 50)
  --interval SECONDS    Sampling interval (default: 0.5)
  --settle SECONDS      Delay after each activation prompt (default: 3)
  --output-dir DIR      Directory for CSV and summary files
  --auto N              Run ~/.local/bin/kiriglyph --select N times.
                        This flashes the screen and requires the one-time
                        GNOME permission grant to already be accepted.
  --pattern REGEX       Override process match regex for the resident app
  --worker-pattern REGEX Override process match regex for workers
  --self-test           Run against dummy sleep processes; no app/capture
  --help                Show this help
EOF
}

while (($# > 0)); do
  case "$1" in
    --activations) ACTIVATIONS="${2:?}"; shift 2 ;;
    --interval) INTERVAL="${2:?}"; shift 2 ;;
    --settle) SETTLE_SECONDS="${2:?}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?}"; shift 2 ;;
    --auto) AUTO="${2:?}"; ACTIVATIONS="$AUTO"; shift 2 ;;
    --pattern) APP_PATTERN="${2:?}"; shift 2 ;;
    --worker-pattern) WORKER_PATTERN="${2:?}"; shift 2 ;;
    --self-test) SELF_TEST='1'; shift ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$SELF_TEST" == '1' ]]; then
  self_test_root="$(mktemp -d)"
  export XDG_RUNTIME_DIR="$self_test_root/runtime"
  export XDG_PICTURES_DIR="$self_test_root/Pictures"
  mkdir -p "$XDG_RUNTIME_DIR" "$XDG_PICTURES_DIR"
  APP_PATTERN='kiriglyph-resource-self-test'
  WORKER_PATTERN='kiriglyph-worker-self-test'
  bash -c 'exec -a kiriglyph-resource-self-test sleep 30' &
  app_dummy=$!
  bash -c 'exec -a kiriglyph-worker-self-test sleep 30' &
  worker_dummy=$!
  trap 'kill "$app_dummy" "$worker_dummy" 2>/dev/null || true; rm -rf "$self_test_root"' EXIT
  ACTIVATIONS='3'
  SETTLE_SECONDS='0.2'
fi

mkdir -p "$OUTPUT_DIR"
run_id="$(date +%s)"
csv="$OUTPUT_DIR/resources-$run_id.csv"
summary="$OUTPUT_DIR/resources-$run_id.summary.txt"
start_epoch="$(date +%s)"
pictures_dir="${XDG_PICTURES_DIR:-$HOME/Pictures}"
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$UID}"

process_pids() {
  local pattern="$1"
  pgrep -u "$UID" -f "$pattern" 2>/dev/null | sort -n || true
}

proc_value_kib() {
  local pid="$1" key="$2"
  awk -v key="$key" '$1 == key ":" {print $2}' "/proc/$pid/status" 2>/dev/null || printf '0\n'
}

proc_threads() {
  local pid="$1"
  awk '$1 == "Threads:" {print $2}' "/proc/$pid/status" 2>/dev/null || printf '0\n'
}

fd_count() {
  local pid="$1"
  local dir="/proc/$pid/fd"
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 1 -type l 2>/dev/null | wc -l
  else
    printf '0\n'
  fi
}

temp_count() {
  find "$runtime_dir" -maxdepth 2 \( -name 'kiriglyph-*' -o -name 'screen-capture-*.png' \) 2>/dev/null | wc -l
}

pictures_count() {
  find "$pictures_dir" -maxdepth 1 -name 'Screenshot*.png' -newermt "@$start_epoch" 2>/dev/null | wc -l
}

sample_once() {
  local activation="$1" phase="$2" now pids pid role
  now="$(date +%s.%N)"
  for role in app worker; do
    if [[ "$role" == app ]]; then
      mapfile -t pids < <(process_pids "$APP_PATTERN")
    else
      mapfile -t pids < <(process_pids "$WORKER_PATTERN")
    fi
    if ((${#pids[@]} == 0)); then
      printf '%s,%s,%s,%s,,,,,,%s,%s\n' "$now" "$activation" "$phase" "$role" "$(temp_count)" "$(pictures_count)" >>"$csv"
    fi
    for pid in "${pids[@]}"; do
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$now" "$activation" "$phase" "$role" "$pid" \
        "$(proc_value_kib "$pid" VmRSS)" "$(proc_value_kib "$pid" VmHWM)" \
        "$(fd_count "$pid")" "$(proc_threads "$pid")" "$(temp_count)" "$(pictures_count)" >>"$csv"
    done
  done
}

printf 'timestamp,activation,phase,role,pid,vmrss_kib,vmhwm_kib,fd_count,threads,runtime_temp_count,pictures_screenshot_count\n' >"$csv"
sample_once 0 baseline

for activation in $(seq 1 "$ACTIVATIONS"); do
  if [[ "$AUTO" != '0' ]]; then
    printf 'Activation %s/%s: running ~/.local/bin/kiriglyph --select (screen may flash)\n' "$activation" "$ACTIVATIONS"
    "$HOME/.local/bin/kiriglyph" --select || true
  elif [[ "$SELF_TEST" == '1' ]]; then
    printf 'Activation %s/%s: self-test sample\n' "$activation" "$ACTIVATIONS"
  else
    printf 'Activation %s/%s: press the Kiriglyph shortcut now, then wait.\n' "$activation" "$ACTIVATIONS"
  fi
  sample_once "$activation" triggered
  sleep "$SETTLE_SECONDS"
  sample_once "$activation" settled
  sleep "$INTERVAL"
done

python3 - "$csv" "$summary" <<'PY'
import csv
import sys
from collections import defaultdict
from pathlib import Path

csv_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
rows = list(csv.DictReader(csv_path.open(newline="", encoding="utf-8")))
settled = [r for r in rows if r["phase"] in {"baseline", "settled"} and r["pid"]]
by_activation = defaultdict(list)
for row in settled:
    by_activation[int(row["activation"])].append(row)

def total_rss(items):
    return sum(int(r["vmrss_kib"] or 0) for r in items)

baseline_pids = {r["pid"] for r in by_activation.get(0, [])}
last_key = max(by_activation) if by_activation else 0
last_pids = {r["pid"] for r in by_activation.get(last_key, [])}
after_five = min((key for key in by_activation if key >= 5), default=0)
rss_start = total_rss(by_activation.get(after_five, []))
rss_end = total_rss(by_activation.get(last_key, []))
rss_growth = 0.0 if rss_start == 0 else (rss_end - rss_start) / rss_start
max_temp = max((int(r["runtime_temp_count"] or 0) for r in rows), default=0)
max_pictures = max((int(r["pictures_screenshot_count"] or 0) for r in rows), default=0)
process_growth = len(last_pids - baseline_pids)
passed = process_growth == 0 and rss_growth < 0.10 and max_temp == 0 and max_pictures == 0
summary = [
    f"CSV: {csv_path}",
    f"Process growth after settle: {process_growth} (threshold: 0)",
    f"RSS growth after activation 5: {rss_growth:.2%} (threshold: <10%)",
    f"Max runtime session files: {max_temp} (threshold: 0 after dismissal)",
    f"New ~/Pictures Screenshot*.png: {max_pictures} (threshold: 0)",
    f"RESULT: {'PASS' if passed else 'FAIL'}",
]
summary_path.write_text("\n".join(summary) + "\n", encoding="utf-8")
print("\n".join(summary))
sys.exit(0 if passed else 1)
PY
