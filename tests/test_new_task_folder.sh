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
assert "created_at format" '[[ "$(fm_get "$folder/spec.md" created_at)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{2}:[0-9]{2}$ ]]'

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

goal_line_after_blank() { awk '/^## Goal$/{getline; getline; print; exit}' "$1/spec.md"; }
idea_folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug idea-zh --date 2026-11-18 --idea '修 login 逾時!' | tail -n 1)"
assert "idea line under Goal" '[ "$(goal_line_after_blank "$idea_folder")" = "Rough idea from launch: 修 login 逾時!" ]'
assert "Scope follows idea" '[ "$(awk "/^## Goal\$/{for(i=0;i<4;i++)getline; print; exit}" "$idea_folder/spec.md")" = "## Scope" ]'
assert "idea keeps no placeholder" '! grep -q "{{" "$idea_folder/spec.md"'

nasty_idea='cost $HOME `date` a|b x & y back\slash it'"'"'s "q" \1 !'
nasty_folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug idea-nasty --date 2026-11-18 --idea "$nasty_idea" | tail -n 1)"
assert "special chars literal" '[ "$(goal_line_after_blank "$nasty_folder")" = "Rough idea from launch: $nasty_idea" ]'

multi_folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug idea-multi --date 2026-11-18 --idea "$(printf 'line one\nline two')" | tail -n 1)"
assert "newline becomes space" '[ "$(goal_line_after_blank "$multi_folder")" = "Rough idea from launch: line one line two" ]'

plain_folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug idea-none --date 2026-11-18 | tail -n 1)"
empty_folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug idea-empty --date 2026-11-18 --idea '' | tail -n 1)"
assert "no idea: Goal empty" '! grep -q "Rough idea" "$plain_folder/spec.md" && [ "$(sed -n "/^## Goal$/,/^## Scope$/p" "$plain_folder/spec.md" | wc -l | tr -d " ")" = "3" ]'
assert "empty idea equals no idea" 'diff <(sed "/^created_at:/d;/^task_id:/d" "$plain_folder/spec.md") <(sed "/^created_at:/d;/^task_id:/d" "$empty_folder/spec.md") >/dev/null'
finish
