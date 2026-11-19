#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
render="$repo_root/scripts/render-excalidraw.sh"
fixture="$repo_root/tests/fixtures/review/diagram.excalidraw"

# input checks need no browser
echo '{}' > "$work_dir/empty.excalidraw"
empty_exit=0
bash "$render" "$work_dir/empty.excalidraw" "$work_dir/empty.svg" >/dev/null 2>&1 || empty_exit=$?
assert "{} exits 1" '[ "$empty_exit" -eq 1 ]'
echo 'not json' > "$work_dir/bad.excalidraw"
bad_exit=0
bash "$render" "$work_dir/bad.excalidraw" "$work_dir/bad.svg" >/dev/null 2>&1 || bad_exit=$?
assert "invalid JSON exits 1" '[ "$bad_exit" -eq 1 ]'
assert "no svg written on input error" '[ ! -e "$work_dir/empty.svg" ] && [ ! -e "$work_dir/bad.svg" ]'

if ! command -v playwright-cli >/dev/null 2>&1; then
  echo "SKIP render cases: playwright-cli not found"
elif ! curl -fs -m 20 -r 0-0 -o /dev/null "https://cdn.jsdelivr.net/npm/@excalidraw/utils@0.1.8/dist/prod/index.js"; then
  echo "SKIP render cases: cdn.jsdelivr.net not reachable"
else
  ok_exit=0
  bash "$render" "$fixture" "$work_dir/out.svg" >/dev/null 2>&1 || ok_exit=$?
  assert "fixture renders and exits 0" '[ "$ok_exit" -eq 0 ]'
  assert "svg starts with <svg" '[ "$(head -c 4 "$work_dir/out.svg")" = "<svg" ]'
  assert "svg holds the fixture label" 'grep -q ">wStack<" "$work_dir/out.svg"'
fi

# unreachable bundle URL: exit 2 with a cause
if command -v playwright-cli >/dev/null 2>&1; then
  net_exit=0
  net_output="$(WSTACK_EXCALIDRAW_BUNDLE_URL="http://127.0.0.1:1/none.js" bash "$render" "$fixture" "$work_dir/net.svg" 2>&1)" || net_exit=$?
  assert "unreachable bundle exits 2" '[ "$net_exit" -eq 2 ]'
  assert "unreachable bundle names a cause" '[[ "$net_output" == *"render-excalidraw: render failed"* ]]'
else
  echo "SKIP network-failure case: playwright-cli not found"
fi
finish
