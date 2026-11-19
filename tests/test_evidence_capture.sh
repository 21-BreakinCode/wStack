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

# Test seam: WSTACK_PREFLIGHT replaces scripts/preflight.sh so a test can fake a missing ffmpeg.
preflight_script="${WSTACK_PREFLIGHT:-$repo_root/scripts/preflight.sh}"

mkdir -p "$work_dir/site"
port=18765
echo '<!doctype html><meta charset="utf-8"><title>fixture</title><h1>wStack fixture</h1>' > "$work_dir/site/index.html"
python3 -m http.server --bind 127.0.0.1 "$port" --directory "$work_dir/site" >/dev/null 2>&1 &
server_pid=$!
sleep 1

# Runs the capture path from skills/evidence/SKILL.md into <task_dir> and sets task_dir, page_width, capture_output.
# Layout: raw captures in raw/, R2 copies in the task folder. pr-attach.sh makes the GitHub copies in gh/ from the top-level files.
capture() {  # <preflight script> <name>
  local preflight="$1" have_ffmpeg=1 preflight_output
  task_dir="$work_dir/wstack-evidence/$2"
  mkdir -p "$task_dir/raw" "$task_dir/gh"
  capture_output=""
  # S2: video-start needs Playwright's own ffmpeg. Preflight checks for it. Without it, skip the video steps only.
  preflight_output="$(bash "$preflight" plan web 2>&1)" || true
  case "$preflight_output" in
    *"MISSING playwright ffmpeg"*)
      have_ffmpeg=0
      capture_output="SKIP video steps: playwright ffmpeg missing. Run: playwright-cli install-browser ffmpeg"
      echo "$capture_output" ;;
  esac
  playwright-cli -s "$session" open "http://127.0.0.1:$port/" >/dev/null
  playwright-cli -s "$session" resize 375 800 >/dev/null
  page_width="$(playwright-cli -s "$session" --raw eval "() => document.documentElement.scrollWidth")"
  [ "$have_ffmpeg" = "0" ] || playwright-cli -s "$session" video-start "$task_dir/raw/flow.webm" >/dev/null
  playwright-cli -s "$session" screenshot --filename="$task_dir/raw/check-1.webp" >/dev/null
  [ "$have_ffmpeg" = "0" ] || playwright-cli -s "$session" video-stop >/dev/null
  playwright-cli -s "$session" close >/dev/null
  r2_webp="$(bash "$repo_root/scripts/compress-media.sh" --target r2 "$task_dir/raw/check-1.webp" "$task_dir" | tail -n 1)"
  if [ "$have_ffmpeg" = "1" ]; then
    r2_mp4="$(bash "$repo_root/scripts/compress-media.sh" --target r2 "$task_dir/raw/flow.webm" "$task_dir" | tail -n 1)"
    gh_mp4="$(bash "$repo_root/scripts/compress-media.sh" --target gh --max-mb 5 "$r2_mp4" "$task_dir/gh" | tail -n 1)"
  fi
}
video_codec() { ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$1"; }

# Case 1: preflight as configured (the real one by default). If it reports ffmpeg missing, the video asserts are skipped.
capture "$preflight_script" real
real_task_dir="$task_dir"
assert "page width at 375 is 375" '[ "$page_width" = "375" ]'
assert "raw webp screenshot exists" '[ -s "$real_task_dir/raw/check-1.webp" ]'
assert "r2 webp is in the task folder" '[ "$(dirname "$r2_webp")" = "$real_task_dir" ] && [ -s "$r2_webp" ]'
if [ -z "$capture_output" ]; then
  assert "raw webm video exists" '[ -s "$real_task_dir/raw/flow.webm" ]'
  assert "r2 mp4 is hevc" '[ "$(video_codec "$r2_mp4")" = "hevc" ]'
  assert "gh mp4 from the top-level hevc copy is h264 in gh/" '[ "$(dirname "$gh_mp4")" = "$real_task_dir/gh" ] && [ "$(video_codec "$gh_mp4")" = "h264" ]'
fi

# Case 2: a stub preflight says ffmpeg is missing. Only the video steps are skipped.
stub_preflight="$work_dir/preflight-missing-ffmpeg.sh"
printf '#!/usr/bin/env bash\necho "MISSING playwright ffmpeg: playwright-cli install-browser ffmpeg"\nexit 1\n' > "$stub_preflight"
capture "$stub_preflight" stub > "$work_dir/stub.out"
stub_task_dir="$task_dir"
stub_stdout="$(cat "$work_dir/stub.out")"
assert "stub: SKIP line names the install command" '[ "$stub_stdout" = "SKIP video steps: playwright ffmpeg missing. Run: playwright-cli install-browser ffmpeg" ]'
assert "stub: no video file is written" '[ -z "$(find "$stub_task_dir" -name "*.webm" -o -name "*.mp4")" ]'
assert "stub: page width at 375 is 375" '[ "$page_width" = "375" ]'
assert "stub: screenshot still captured" '[ -s "$stub_task_dir/raw/check-1.webp" ]'
assert "stub: r2 webp still made" '[ -s "$r2_webp" ]'
finish
