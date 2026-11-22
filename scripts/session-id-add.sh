#!/usr/bin/env bash
# Usage: session-id-add.sh <spec.md> <session id>
# Adds the id last in the session_ids list.
# Exit 1 no such file, 2 usage, 3 the id is not a UUID, 4 the stored session_ids is a block-style list or not valid JSON.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/lib/frontmatter.sh"
source "$(dirname "${BASH_SOURCE[0]:-$0}")/lib/transcripts.sh"

[ "$#" -eq 2 ] || { echo "usage: session-id-add.sh <spec.md> <session id>" >&2; exit 2; }
spec="$1"; session_id="$2"
[ -f "$spec" ] || { echo "no such file: $spec" >&2; exit 1; }
session_id_ok "$session_id" || { echo "not a session id: $session_id" >&2; exit 3; }

! fm_has_block_list "$spec" session_ids || { echo "session_ids in $spec must be a one-line JSON list, like session_ids: []" >&2; exit 4; }
current="$(fm_get "$spec" session_ids)"
updated="$(jq -c --arg id "$session_id" '. + [$id] | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)' <<<"${current:-[]}" 2>/dev/null)" \
  || { echo "session_ids in $spec is not a valid JSON list: $current" >&2; exit 4; }
fm_set "$spec" session_ids "$updated"
