#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
fixture="$repo_root/tests/fixtures/spec-sample.md"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
sample="$work_dir/sample file.md"
cp "$fixture" "$sample"

assert "fm_get status" '[ "$(fm_get "$sample" status)" = "drafting" ]'
assert "fm_get empty value" '[ -z "$(fm_get "$sample" approved_at)" ]'

fm_set "$sample" status executing
assert "fm_set changes status" '[ "$(fm_get "$sample" status)" = "executing" ]'
assert "fm_set changes only that line" '[ "$(diff "$fixture" "$sample" | grep -c "^[<>]")" = "2" ]'
assert "fm_set keeps body" 'grep -q "^Body text with status: not frontmatter.$" "$sample"'

fm_set "$sample" workspace_cwd "/tmp/a b"
assert "fm_set adds missing key" '[ "$(fm_get "$sample" workspace_cwd)" = "/tmp/a b" ]'
assert "added key sits before closing ---" '[ "$(sed -n 8,9p "$sample" | tr "\n" "|")" = "workspace_cwd: /tmp/a b|---|" ]'

fm_append "$sample" stopped_for_user '{"at":"2026-11-18T23:00:00+08:00","reason":"merge"}'
assert "fm_append first item" '[ "$(fm_get "$sample" stopped_for_user | jq -c "length")" = "1" ]'
assert "list stays on one line" '[ "$(grep -c "^stopped_for_user:" "$sample")" = "1" ]'
fm_append "$sample" stopped_for_user '{"at":"2026-11-18T23:05:00+08:00","reason":"retry limit"}'
assert "fm_append second item" '[ "$(fm_get "$sample" stopped_for_user | jq -c "length")" = "2" ]'

json="$(fm_to_json "$sample")"
assert "fm_to_json retries is string" '[ "$(echo "$json" | jq -r ".retries == \"0\"")" = "true" ]'
assert "fm_to_json list parsed" '[ "$(echo "$json" | jq ".stopped_for_user | length")" = "2" ]'
assert "fm_to_json empty is null" '[ "$(echo "$json" | jq ".approved_at")" = "null" ]'

before="$(cat "$sample")"
rc=0; bash "$repo_root/scripts/frontmatter-set.sh" "$sample" status done 2>/dev/null || rc=$?
assert "set script rejects bad status" '[ "$rc" = "1" ]'
assert "file unchanged after bad status" '[ "$(cat "$sample")" = "$before" ]'
rc=0; bash "$repo_root/scripts/frontmatter-set.sh" "$sample" status "drafting awaiting-approval" 2>/dev/null || rc=$?
assert "set script rejects multi-word status" '[ "$rc" = "1" ] && [ "$(cat "$sample")" = "$before" ]'
rc=0; bash "$repo_root/scripts/frontmatter-set.sh" "$sample" status verifying || rc=$?
assert "set script accepts good status" '[ "$rc" = "0" ] && [ "$(fm_get "$sample" status)" = "verifying" ]'
bash "$repo_root/scripts/frontmatter-set.sh" --append "$sample" stopped_for_user '{"at":"x","reason":"y"}'
assert "set script --append" '[ "$(fm_get "$sample" stopped_for_user | jq length)" = "3" ]'
finish
