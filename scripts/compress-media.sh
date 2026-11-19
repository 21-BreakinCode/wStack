#!/usr/bin/env bash
# Compress one evidence file for R2 (WebP, H.265) or GitHub (JPEG, H.264). Prints the output path.
# If the output path equals the input path (for example a .webp or .mp4 input
# compressed into its own folder), it exits 1 and leaves the input untouched.
set -euo pipefail

usage() { echo "usage: compress-media.sh --target r2|gh [--max-mb <n>] <input> <out-dir>" >&2; exit 2; }

target=""; max_mb=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || usage; target="$2"; shift 2 ;;
    --max-mb) [ $# -ge 2 ] || usage; max_mb="$2"; shift 2 ;;
    --*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 2 ] || usage
input="$1"; out_dir="$2"
case "$target" in r2|gh) ;; *) usage ;; esac
[ -f "$input" ] || { echo "input not found: $input" >&2; exit 1; }
mkdir -p "$out_dir"

file_name="$(basename "$input")"
base_name="${file_name%.*}"
extension="$(printf '%s' "${file_name##*.}" | tr '[:upper:]' '[:lower:]')"

is_too_large() {  # <file>; false when no --max-mb is set
  [ -n "$max_mb" ] || return 1
  local size_bytes
  size_bytes="$(wc -c < "$1" | tr -d ' ')"
  awk -v size="$size_bytes" -v max="$max_mb" 'BEGIN { exit !(size > max * 1048576) }'
}

fail_if_output_is_input() {  # <output>
  if [ "$1" -ef "$input" ]; then
    echo "output would overwrite input: $1 (use a different out-dir)" >&2
    exit 1
  fi
}

case "$extension" in
  gif) echo "GIF is not supported: record the terminal as .webm or .mp4 ($file_name)" >&2; exit 1 ;;
  png|jpg|jpeg|webp)
    if [ "$target" = "r2" ]; then
      output="$out_dir/$base_name.webp"
      fail_if_output_is_input "$output"
      cwebp -quiet -q 80 "$input" -o "$output"
    else
      output="$out_dir/$base_name.jpg"
      fail_if_output_is_input "$output"
      sips -s format jpeg "$input" --out "$output" >/dev/null
    fi
    echo "$output"
    ;;
  webm|mov|mp4)
    output="$out_dir/$base_name.mp4"
    fail_if_output_is_input "$output"
    if [ "$target" = "r2" ]; then
      ffmpeg -y -loglevel error -i "$input" -c:v libx265 -preset veryfast -crf 28 -tag:v hvc1 "$output"
      echo "$output"
      exit 0
    fi
    encode_h264() {  # [filter args...]
      ffmpeg -y -loglevel error -i "$input" "$@" -c:v libx264 -preset veryfast -crf 28 -movflags +faststart "$output"
    }
    encode_h264
    if is_too_large "$output"; then
      fitted=0
      for height in 1080 720 480 360; do
        encode_h264 -vf "scale=-2:$height"
        if ! is_too_large "$output"; then fitted=1; break; fi
      done
      if [ "$fitted" -eq 0 ]; then
        echo "cannot fit $file_name under $max_mb MB" >&2
        exit 1
      fi
    fi
    echo "$output"
    ;;
  *) echo "unsupported file type: $file_name" >&2; exit 1 ;;
esac
