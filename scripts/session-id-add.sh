#!/usr/bin/env bash
# Usage: session-id-add.sh <spec.md> <session id>
# Adds the id last in the session_ids list. Exit 1 no such file, 2 usage, 3 the id is not a UUID.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/lib/frontmatter.sh"

[ "$#" -eq 2 ] || { echo "usage: session-id-add.sh <spec.md> <session id>" >&2; exit 2; }
spec="$1"; session_id="$2"
[ -f "$spec" ] || { echo "no such file: $spec" >&2; exit 1; }
uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
[[ "$session_id" =~ $uuid_pattern ]] || { echo "not a session id: $session_id" >&2; exit 3; }

current="$(fm_get "$spec" session_ids)"
updated="$(jq -c --arg id "$session_id" '. + [$id] | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)' <<<"${current:-[]}")"
fm_set "$spec" session_ids "$updated"
