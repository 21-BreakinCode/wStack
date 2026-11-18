#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/new-task-folder.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
vault="$work_dir/My Vault"
mkdir -p "$vault"

folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug test-idea --date 2026-11-18 | tail -n 1)"
assert "folder path" '[ "$folder" = "$vault/Workflow/Tasks/2026-11-18-test-idea" ]'
for name in spec run-log review report; do
  assert "$name.md exists" '[ -f "$folder/$name.md" ]'
  assert "$name.md task_id" '[ "$(fm_get "$folder/$name.md" task_id)" = "2026-11-18-test-idea" ]'
done
assert "no placeholder left" '! grep -rq "{{" "$folder"'
assert "status drafting" '[ "$(fm_get "$folder/spec.md" status)" = "drafting" ]'
assert "mobile false" '[ "$(fm_get "$folder/spec.md" mobile)" = "false" ]'
assert "work_type default code" '[ "$(fm_get "$folder/spec.md" work_type)" = "code" ]'
assert "created_at format" '[[ "$(fm_get "$folder/spec.md" created_at)" =~ ^2026-11-18T[0-9:]{8}[+-][0-9]{2}:[0-9]{2}$ ]]'

second="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug test-idea --date 2026-11-18 | tail -n 1)"
assert "collision suffix" '[ "$second" = "$vault/Workflow/Tasks/2026-11-18-test-idea-2" ]'
assert "suffix task_id" '[ "$(fm_get "$second/spec.md" task_id)" = "2026-11-18-test-idea-2" ]'

rc=0; bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug Test_Idea >/dev/null 2>&1 || rc=$?
assert "bad slug exits 1" '[ "$rc" = "1" ]'
rc=0; bash "$script" --vault /nonexistent --tasks-dir Workflow/Tasks --slug ok >/dev/null 2>&1 || rc=$?
assert "bad vault exits 1" '[ "$rc" = "1" ]'

long_slug="a23456789012345678901234567890bc"
bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug "$long_slug" --date 2026-11-18 >/dev/null
long_second="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug "$long_slug" --date 2026-11-18 | tail -n 1)"
long_second_slug="$(basename "$long_second" | cut -c12-)"
assert "long collision slug valid" '[[ "$long_second_slug" =~ ^[a-z][a-z0-9-]{0,31}$ ]] && [ "$long_second_slug" != "$long_slug" ]'

mobile_folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug phone --date 2026-11-18 --mobile --work-type ops --repo owner/repo | tail -n 1)"
assert "mobile true" '[ "$(fm_get "$mobile_folder/spec.md" mobile)" = "true" ]'
assert "work type and repo" '[ "$(fm_get "$mobile_folder/spec.md" work_type)" = "ops" ] && [ "$(fm_get "$mobile_folder/spec.md" repo)" = "owner/repo" ]'
finish
