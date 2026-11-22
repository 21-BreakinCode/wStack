#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/session-id-add.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
first_id=0f8fad5b-d9cb-469f-a165-70867728950e
second_id=1b4e28ba-2fa1-11d2-883f-0016d3cca427
spec="$work_dir/spec.md"
sed -e 's/{{task_id}}/2026-11-23-demo/' -e 's/{{work_type}}/code/' -e 's/{{repo}}/o\/r/' \
    -e 's/{{mobile}}/false/' -e 's/{{created_at}}/2026-11-23T10:00:00+08:00/' \
    "$repo_root/templates/spec.md" >"$spec"

bash "$script" "$spec" "$first_id"
assert "adds the first id" '[ "$(fm_get "$spec" session_ids)" = "[\"$first_id\"]" ]'
bash "$script" "$spec" "$second_id"
assert "appends a second id last" '[ "$(fm_get "$spec" session_ids)" = "[\"$first_id\",\"$second_id\"]" ]'
bash "$script" "$spec" "$first_id"
assert "skips a duplicate" '[ "$(fm_get "$spec" session_ids)" = "[\"$first_id\",\"$second_id\"]" ]'

before="$(cat "$spec")"
rc=0; bash "$script" "$spec" '${CLAUDE_SESSION_ID}' 2>/dev/null || rc=$?
assert "literal placeholder exits 3 and leaves the list" '[ "$rc" = 3 ] && [ "$(cat "$spec")" = "$before" ]'
rc=0; bash "$script" "$spec" ABC 2>/dev/null || rc=$?
assert "short id exits 3" '[ "$rc" = 3 ]'
rc=0; bash "$script" "$spec" "${first_id:1}" 2>/dev/null || rc=$?
assert "35-character id exits 3" '[ "$rc" = 3 ] && [ "${#first_id}" = 36 ]'
rc=0; bash "$script" "$spec" "$(echo "$first_id" | tr a-f A-F)" 2>/dev/null || rc=$?
assert "upper case id exits 3" '[ "$rc" = 3 ]'

old_spec="$work_dir/old.md"
grep -v '^session_ids:' "$spec" >"$old_spec"
others_before="$(grep -v '^session_ids:' "$old_spec")"
bash "$script" "$old_spec" "$first_id"
assert "old spec gets the field" '[ "$(fm_get "$old_spec" session_ids)" = "[\"$first_id\"]" ]'
assert "old spec keeps its other fields" '[ "$(grep -v "^session_ids:" "$old_spec")" = "$others_before" ]'

rc=0; bash "$script" "$work_dir/none.md" "$first_id" 2>/dev/null || rc=$?
assert "missing file exits 1" '[ "$rc" = 1 ]'
finish
