#!/usr/bin/env bash
# Remove secrets from an API log. This script is the security boundary for evidence logs.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: redact-log.sh <in> <out>" >&2; exit 2; }
input="$1"; output="$2"
[ -r "$input" ] && [ ! -d "$input" ] || { echo "input not found: $input" >&2; exit 1; }

header_names='authorization|proxy-authorization|cookie|set-cookie|x-api-key|x-auth-token'
query_names='api_key|apikey|token|access_token|key'
json_keys='authorization|proxy-authorization|cookie|set-cookie|x-api-key|x-auth-token|api_key|apikey|token|access_token|key|refresh_token|id_token|client_secret|password'

# Write to a temp file first so a failed run never leaves a half-redacted output.
temp_output="$(mktemp)"
trap 'rm -f "$temp_output"' EXIT
sed -E \
  -e "s/(^|[^A-Za-z0-9_-])((${header_names})[[:space:]]*:)[[:space:]]*.*/\1\2 [REDACTED]/I" \
  -e "s/([?&;#[:space:]\"](${query_names})=)[^&[:space:]\"']*/\1[REDACTED]/Ig" \
  -e "s/(\"(${json_keys})\"[[:space:]]*:[[:space:]]*)\"([^\"\\\\]|\\\\.)*\"/\1\"[REDACTED]\"/Ig" \
  -e "s/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig" \
  "$input" > "$temp_output"
cp "$temp_output" "$output"
