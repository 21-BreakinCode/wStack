#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/compress-media.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
out_dir="$work_dir/out"; r2_dir="$out_dir/r2"; gh_dir="$out_dir/gh"
mkdir -p "$r2_dir" "$gh_dir"

ffmpeg -loglevel error -f lavfi -i testsrc=duration=3:size=1280x720:rate=30 -c:v libvpx "$work_dir/clip.webm"
ffmpeg -loglevel error -f lavfi -i testsrc=duration=1:size=640x360:rate=1 -frames:v 1 "$work_dir/shot.png"

probe() { ffprobe -v error -select_streams v:0 -show_entries stream=$1 -of default=nw=1:nk=1 "$2"; }

r2_video="$(bash "$script" --target r2 "$work_dir/clip.webm" "$r2_dir" | tail -n 1)"
assert "r2 video exists" '[ -f "$r2_video" ]'
assert "r2 video hevc" '[ "$(probe codec_name "$r2_video")" = "hevc" ]'
assert "r2 video hvc1 tag" '[ "$(probe codec_tag_string "$r2_video")" = "hvc1" ]'

gh_video="$(bash "$script" --target gh "$work_dir/clip.webm" "$gh_dir" | tail -n 1)"
assert "gh video h264" '[ "$(probe codec_name "$gh_video")" = "h264" ]'

r2_image="$(bash "$script" --target r2 "$work_dir/shot.png" "$r2_dir" | tail -n 1)"
assert "r2 image webp" '[[ "$(file "$r2_image")" == *"Web/P"* ]]'

gh_image="$(bash "$script" --target gh "$work_dir/shot.png" "$gh_dir" | tail -n 1)"
assert "gh image jpeg" '[[ "$(file "$gh_image")" == *"JPEG"* ]]'

status=0
message="$(bash "$script" --target gh --max-mb 0.001 "$work_dir/clip.webm" "$gh_dir" 2>&1)" || status=$?
assert "too large exits 1" '[ "$status" -eq 1 ]'
assert "too large message" '[[ "$message" == *"cannot fit"* ]]'
finish
