#!/usr/bin/env bash
# Remove secrets from an API log. This script is the security boundary for evidence logs.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: redact-log.sh <in> <out>" >&2; exit 2; }
input="$1"; output="$2"
[ -r "$input" ] && [ ! -d "$input" ] || { echo "input not found: $input" >&2; exit 1; }

# One name list for headers, URL parameters, and JSON keys.
secret_names='[A-Za-z0-9_-]*(authorization|cookie|token|secret|password|api[_-]?key|signature|credential|private[_-]?key)[A-Za-z0-9_-]*|key'

# Write to a temp file first so a failed run never leaves a half-redacted output.
temp_output="$(mktemp)"
trap 'rm -f "$temp_output"' EXIT
LC_ALL=C sed -E \
  -e "s/(^|[^A-Za-z0-9_-])((${secret_names})[[:space:]]*:)[[:space:]]*.*/\1\2 [REDACTED]/I" \
  -e "s/([?&;#[:space:]\"](${secret_names})=)[^&[:space:]\"']*/\1[REDACTED]/Ig" \
  -e "s/(\"(${secret_names})\"[[:space:]]*:[[:space:]]*)\"([^\"\\\\]|\\\\.)*\"/\1\"[REDACTED]\"/Ig" \
  -e "s/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig" \
  "$input" > "$temp_output"
cp "$temp_output" "$output"
