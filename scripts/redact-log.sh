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
# A counter is a name ending in "tokens" or "count" (max_tokens=4096, token_count: 12) with a number of at most 6 digits.
# The header form "Token: 5 requests" is a counter too. Every other secret name is redacted whatever its value.
# Step 1 puts a marker after the name of a counter, so the rules below skip it. The last step removes the marker.
# The second URL rule runs twice: the first pass eats the "&" that the next counter needs in front of it.
counter_names='[A-Za-z0-9_-]*(tokens|count)'
mark=$'\001'
number_end='([^0-9.eE]|$)'
LC_ALL=C sed -E \
  -e "s/(^|[^A-Za-z0-9_-])((${counter_names}|token))([[:space:]]*:[[:space:]]*[0-9]{1,6}([[:space:]]+[A-Za-z]+)?[[:space:]]*\$)/\1\2${mark}\5/I" \
  -e "s/([?&;#[:space:]\"](${counter_names}))(=[0-9]{1,6}([&[:space:]\"']|\$))/\1${mark}\4/Ig" \
  -e "s/([?&;#[:space:]\"](${counter_names}))(=[0-9]{1,6}([&[:space:]\"']|\$))/\1${mark}\4/Ig" \
  -e "s/(\"(${counter_names})\")([[:space:]]*:[[:space:]]*[0-9]{1,6}${number_end})/\1${mark}\4/Ig" \
  -e "s/(^|[^A-Za-z0-9_-])((${secret_names})[[:space:]]*:)[[:space:]]*.*/\1\2 [REDACTED]/I" \
  -e "s/([?&;#[:space:]\"](${secret_names})=)[^&[:space:]\"']*/\1[REDACTED]/Ig" \
  -e "s/(\"(${secret_names})\"[[:space:]]*:[[:space:]]*)\"([^\"\\\\]|\\\\.)*\"/\1\"[REDACTED]\"/Ig" \
  -e "s/(\"(${secret_names})\"[[:space:]]*:[[:space:]]*)(-?[0-9][0-9.eE+-]*|true|false)/\1\"[REDACTED]\"/Ig" \
  -e "s/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig" \
  -e "s/${mark}//g" \
  "$input" > "$temp_output"
cp "$temp_output" "$output"
