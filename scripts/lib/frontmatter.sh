#!/usr/bin/env bash
# Frontmatter helpers. Format: one "key: value" per line between two "---" lines.
# List values are one-line JSON. Source this file.
set -euo pipefail

fm_tmp_like() {  # <file>: print a new temp file next to <file> with the same mode
  local tmp
  tmp="$(mktemp "${1}.XXXXXX")"
  if [ -e "$1" ]; then cp -p "$1" "$tmp"; fi
  printf '%s\n' "$tmp"
}

fm_get() {  # <file> <key>
  awk -v key="$2" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ":") == 1 { v = substr($0, length(key) + 2); sub(/^ /, "", v); print v; exit }
  ' "$1"
}

fm_set() {  # <file> <key> <value>
  local file="$1" tmp
  tmp="$(fm_tmp_like "$file")"
  FM_VALUE="$3" awk -v key="$2" '
    { sub(/\r$/, "") }
    NR == 1 { print; inside = 1; next }
    inside && $0 == "---" { if (!done) print key ": " ENVIRON["FM_VALUE"]; inside = 0; done = 1; print; next }
    inside && index($0, key ":") == 1 && !done { print key ": " ENVIRON["FM_VALUE"]; done = 1; next }
    { print }
  ' "$file" >"$tmp" && mv "$tmp" "$file"
}

fm_append() {  # <file> <key> <json-object>
  local current updated
  current="$(fm_get "$1" "$2")"
  updated="$(jq -c --argjson item "$3" '. + [$item]' <<<"${current:-[]}")"
  fm_set "$1" "$2" "$updated"
}

fm_to_json() {  # <file>
  tr -d '\r' <"$1" | awk 'NR == 1 { next } $0 == "---" { exit } { print }' | jq -Rn '
    [inputs | capture("^(?<k>[^:]+):[ ]*(?<v>.*)$")]
    | map({key: .k, value: (if .v == "" then null
                            elif (.v | test("^[\\[{]")) then (.v | fromjson)
                            else .v end)})
    | from_entries'
}
