#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v playwright-cli >/dev/null 2>&1; then
  echo "SKIP test_evidence_capture: playwright-cli not installed"
  exit 0
fi
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
server_pid=""
cleanup() {
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
  playwright-cli -s wstack-test close >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

port=18765
mkdir -p "$work_dir/site" "$work_dir/evidence"
echo '<!doctype html><title>fixture</title><h1>wStack fixture</h1>' > "$work_dir/site/index.html"
python3 -m http.server --bind 127.0.0.1 "$port" --directory "$work_dir/site" >/dev/null 2>&1 &
server_pid=$!
sleep 1

playwright-cli -s wstack-test open "http://127.0.0.1:$port/"
playwright-cli -s wstack-test video-start "$work_dir/evidence/flow.webm"
playwright-cli -s wstack-test screenshot --filename="$work_dir/evidence/check-1.webp"
playwright-cli -s wstack-test video-stop
playwright-cli -s wstack-test close

mp4="$(bash "$repo_root/scripts/compress-media.sh" --target r2 "$work_dir/evidence/flow.webm" "$work_dir/evidence" | tail -n 1)"
assert "webp screenshot exists" '[ -s "$work_dir/evidence/check-1.webp" ]'
assert "r2 mp4 is hevc" '[ "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$mp4")" = "hevc" ]'
finish
