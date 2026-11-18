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
session="wstack-test"
cleanup() {
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
  playwright-cli -s "$session" close >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

# Layout from skills/evidence/SKILL.md: raw captures in raw/, R2 copies in the task folder, GitHub copies in gh/.
task_dir="$work_dir/wstack-evidence/task-1"
mkdir -p "$task_dir/raw" "$task_dir/gh" "$work_dir/site"

# S2: video-start needs Playwright's own ffmpeg. Preflight checks for it. Without it, skip the video steps only.
have_ffmpeg=1
preflight_output="$(bash "$repo_root/scripts/preflight.sh" plan web 2>&1)" || true
case "$preflight_output" in
  *"MISSING playwright ffmpeg"*)
    have_ffmpeg=0
    echo "SKIP video steps: playwright ffmpeg missing. Run: playwright-cli install-browser ffmpeg" ;;
esac

port=18765
echo '<!doctype html><meta charset="utf-8"><title>fixture</title><h1>wStack fixture</h1>' > "$work_dir/site/index.html"
python3 -m http.server --bind 127.0.0.1 "$port" --directory "$work_dir/site" >/dev/null 2>&1 &
server_pid=$!
sleep 1

playwright-cli -s "$session" open "http://127.0.0.1:$port/" >/dev/null
playwright-cli -s "$session" resize 375 800 >/dev/null
page_width="$(playwright-cli -s "$session" --raw eval "() => document.documentElement.scrollWidth")"
[ "$have_ffmpeg" = "0" ] || playwright-cli -s "$session" video-start "$task_dir/raw/flow.webm" >/dev/null
playwright-cli -s "$session" screenshot --filename="$task_dir/raw/check-1.webp" >/dev/null
[ "$have_ffmpeg" = "0" ] || playwright-cli -s "$session" video-stop >/dev/null
playwright-cli -s "$session" close >/dev/null

r2_webp="$(bash "$repo_root/scripts/compress-media.sh" --target r2 "$task_dir/raw/check-1.webp" "$task_dir" | tail -n 1)"
video_codec() { ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$1"; }

assert "page width at 375 is 375" '[ "$page_width" = "375" ]'
assert "raw webp screenshot exists" '[ -s "$task_dir/raw/check-1.webp" ]'
assert "r2 webp is in the task folder" '[ "$(dirname "$r2_webp")" = "$task_dir" ] && [ -s "$r2_webp" ]'
if [ "$have_ffmpeg" = "1" ]; then
  r2_mp4="$(bash "$repo_root/scripts/compress-media.sh" --target r2 "$task_dir/raw/flow.webm" "$task_dir" | tail -n 1)"
  gh_mp4="$(bash "$repo_root/scripts/compress-media.sh" --target gh --max-mb 5 "$task_dir/raw/flow.webm" "$task_dir/gh" | tail -n 1)"
  assert "raw webm video exists" '[ -s "$task_dir/raw/flow.webm" ]'
  assert "r2 mp4 is hevc" '[ "$(video_codec "$r2_mp4")" = "hevc" ]'
  assert "gh mp4 is h264 in gh/" '[ "$(dirname "$gh_mp4")" = "$task_dir/gh" ] && [ "$(video_codec "$gh_mp4")" = "h264" ]'
fi
finish
