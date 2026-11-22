#!/usr/bin/env bash
# Usage: board-watch.sh --vault <abs> --tasks-dir <rel> [--interval <seconds>] [--once]
# Prints a live frame of every open RD, its tool now, and its running subagents. Ctrl-C ends the loop.
# --once prints one frame without clearing the screen.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fail() { echo "board-watch: $1" >&2; exit 1; }

vault="" tasks_dir="" interval=3 once=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --once) once=true; shift; continue ;;
  esac
  [ "$#" -ge 2 ] || fail "missing value for $1"
  case "$1" in
    --vault) vault="$2" ;;
    --tasks-dir) tasks_dir="$2" ;;
    --interval) interval="$2" ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done
[[ "$vault" = /* ]] || fail "--vault must be an absolute path"
[[ "$interval" =~ ^[1-9][0-9]*$ ]] || fail "--interval must be a positive integer"

print_frame() {
  local rows
  local errors_file status=0
  errors_file="$(mktemp)"
  rows="$(bash "$script_dir/board.sh" --vault "$vault" --tasks-dir "$tasks_dir" 2>"$errors_file")" || status=$?
  if [ "$status" != 0 ] || [ -s "$errors_file" ]; then cat "$errors_file"; fi
  rm -f "$errors_file"
  [ "$status" = 0 ] || { echo "board-watch: board.sh failed"; return 1; }
  [ -n "$rows" ] || { echo "no RD is open"; return 0; }
  jq -r '
    def hint_of: if . == null then "-" else "\(.tool)  \(.hint)" end;
    "\(.group | .[:11] + "           " | .[:11]) \(.slug)  \(.status)  herdr:\(.herdr)  \(.age)",
    "  tool: \(.last_tool | hint_of)",
    (.subagents[] | "  subagent: \(.type)  \(.description)  \(.last_tool | hint_of)  idle \(.idle_seconds)s")' <<<"$rows"
}

if $once; then print_frame; exit; fi
while true; do
  frame="$(print_frame || true)"
  printf '\033[H\033[2J%s\n' "$frame"
  sleep "$interval"
done
