#!/usr/bin/env bash
# Usage: free-agent-slug.sh <slug>
# Prints the first free herdr agent name: <slug>, <slug>-2, <slug>-3, ... (32 characters at most).
# Outside herdr (HERDR_ENV is not 1) it prints <slug> unchanged.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/herdr.sh"

slug="${1:-}"
[[ "$slug" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || { echo "free-agent-slug: bad slug: $slug" >&2; exit 1; }
if [ "${HERDR_ENV:-}" != 1 ]; then echo "$slug"; exit 0; fi

candidate="$slug"
attempt=1
while herdr_cmd agent get "$candidate" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -le 99 ] || { echo "free-agent-slug: no free name for $slug" >&2; exit 1; }
  suffix="-$attempt"
  trimmed="${slug:0:$((32 - ${#suffix}))}"
  while [ "${trimmed%-}" != "$trimmed" ]; do trimmed="${trimmed%-}"; done
  candidate="$trimmed$suffix"
done
echo "$candidate"
