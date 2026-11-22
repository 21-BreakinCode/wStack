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

# A1-2 CRLF line ends
crlf="$work_dir/crlf.md"; sed 's/$/\r/' "$fixture" >"$crlf"
assert "fm_get strips CR" '[ "$(fm_get "$crlf" status)" = "drafting" ]'
assert "fm_to_json strips CR" '[ "$(fm_to_json "$crlf" | jq -r .status)" = "drafting" ]'
fm_set "$crlf" status executing
assert "fm_set edits a CRLF file" '[ "$(fm_get "$crlf" status)" = "executing" ]'

# A1-7 mode is kept
mode_file="$work_dir/mode.md"; cp "$fixture" "$mode_file"; chmod 644 "$mode_file"
fm_set "$mode_file" status executing
assert "fm_set keeps mode 644" '[ "$(stat -f %Lp "$mode_file" 2>/dev/null || stat -c %a "$mode_file")" = 644 ]'

# A3-9: a failed write leaves no temp file next to the file
mkdir -p "$work_dir/failbin" "$work_dir/failcase"
printf '#!/bin/sh\nexit 1\n' > "$work_dir/failbin/awk"; chmod +x "$work_dir/failbin/awk"
cp "$fixture" "$work_dir/failcase/spec.md"
rc=0; (PATH="$work_dir/failbin:$PATH"; fm_set "$work_dir/failcase/spec.md" status executing) 2>/dev/null || rc=$?
assert "failed fm_set returns non-zero" '[ "$rc" != "0" ]'
assert "failed fm_set leaves no temp file" '[ "$(ls "$work_dir/failcase")" = "spec.md" ]'
finish
