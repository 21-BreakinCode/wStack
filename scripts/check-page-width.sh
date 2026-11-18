#!/usr/bin/env bash
# Usage: check-page-width.sh <page.html> [width=375]
# Prints the page's scrollWidth at <width> px. Exit 0 fits, 1 too wide, 2 bad input or browser failure.
# Method of decision S2: serve the page over http (Playwright blocks file://), then read scrollWidth.
# Needs playwright-cli on PATH (Node 26 first).
set -euo pipefail

page="${1:-}" width="${2:-375}"
[ -f "$page" ] || { echo "check-page-width: no such page: $page" >&2; exit 2; }
[[ "$width" =~ ^[0-9]+$ ]] || { echo "check-page-width: bad width: $width" >&2; exit 2; }
command -v playwright-cli >/dev/null 2>&1 || { echo "check-page-width: playwright-cli not found. install: npm i -g @playwright/cli@0.1.24" >&2; exit 2; }

page_dir="$(cd "$(dirname "$page")" && pwd)"
page_name="$(basename "$page")"
session="wstack-width-$$"
server_pid=""
cleanup() {
  playwright-cli -s "$session" close >/dev/null 2>&1 || true
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

# Ask the OS for a free port. Two runs at once get two ports. Another process can still grab it before the server binds.
port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')" || { echo "check-page-width: could not pick a port" >&2; exit 2; }
python3 -m http.server --bind 127.0.0.1 --directory "$page_dir" "$port" >/dev/null 2>&1 &
server_pid=$!

server_up=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fs -o /dev/null "http://127.0.0.1:$port/$page_name"; then server_up=true; break; fi
  sleep 0.5
done
$server_up || { echo "check-page-width: the local server did not start (python3 -m http.server on 127.0.0.1:$port)" >&2; exit 2; }

browser_output="$(playwright-cli -s "$session" open "http://127.0.0.1:$port/$page_name" 2>&1)" || { echo "check-page-width: could not open the page: $browser_output" >&2; exit 2; }
browser_output="$(playwright-cli -s "$session" resize "$width" 800 2>&1)" || { echo "check-page-width: resize failed: $browser_output" >&2; exit 2; }
scroll_width="$(playwright-cli -s "$session" --raw eval "() => document.documentElement.scrollWidth" 2>&1)" || { echo "check-page-width: eval failed: $scroll_width" >&2; exit 2; }
[[ "$scroll_width" =~ ^[0-9]+$ ]] || { echo "check-page-width: unexpected eval output: $scroll_width" >&2; exit 2; }

echo "$scroll_width"
[ "$scroll_width" -le "$width" ]
