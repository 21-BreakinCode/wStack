#!/usr/bin/env bash
# Usage: frontmatter-set.sh <file> <key> <value>
#        frontmatter-set.sh --append <file> <key> <json-object>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/lib/frontmatter.sh"

mode=set
if [ "${1:-}" = "--append" ]; then mode=append; shift; fi
if [ "$#" -ne 3 ]; then echo "usage: frontmatter-set.sh [--append] <file> <key> <value>" >&2; exit 2; fi
file="$1"; key="$2"; value="$3"
[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }

if [ "$mode" = append ]; then
  jq -e 'type == "object"' <<<"$value" >/dev/null || { echo "not a JSON object: $value" >&2; exit 1; }
  fm_append "$file" "$key" "$value"
  exit 0
fi

if [ "$key" = status ]; then
  case "$value" in
    drafting|awaiting-approval|executing|waiting-user|verifying|awaiting-deliver-approval|delivered|cancelled) ;;
    *) echo "invalid status: $value" >&2; exit 1 ;;
  esac
fi
fm_set "$file" "$key" "$value"
