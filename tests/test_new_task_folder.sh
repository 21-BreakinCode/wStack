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

mkdir "$vault/Workflow/Tasks/2026-11-17-fix-login"
other_day="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug fix-login --date 2026-11-18 | tail -n 1)"
assert "slug taken by an earlier day gets -2" '[ "$other_day" = "$vault/Workflow/Tasks/2026-11-18-fix-login-2" ]'

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

contract_folder="$(bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug set-contract --date 2026-11-18 --work-type contract --repo owner/repo | tail -n 1)"
assert "work type contract accepted" '[ "$(fm_get "$contract_folder/spec.md" work_type)" = "contract" ]'
rc=0; bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug bad-contract --work-type contracts >/dev/null 2>&1 || rc=$?
assert "work type contracts rejected" '[ "$rc" = "1" ]'

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

# A3-5: a live herdr agent name also counts as a taken slug
mkdir -p "$work_dir/bin"
cat > "$work_dir/bin/herdr" <<'FAKE'
#!/usr/bin/env bash
args=("$@"); [ "${args[0]}" = "--session" ] && args=("${args[@]:2}")
[ "${args[0]} ${args[1]}" = "agent get" ] || exit 9
case " $TAKEN " in *" ${args[2]} "*) exit 0 ;; *) exit 1 ;; esac
FAKE
chmod +x "$work_dir/bin/herdr"
agent_run() {  # <herdr env> <taken agents> <slug>
  PATH="$work_dir/bin:$PATH" WSTACK_HERDR_SESSION=wstack-test HERDR_ENV="$1" TAKEN="$2" \
    bash "$script" --vault "$vault" --tasks-dir Workflow/Tasks --slug "$3" --date 2026-11-18 | tail -n 1
}
assert "free agent name keeps the slug" '[ "$(agent_run 1 "" agent-free)" = "$vault/Workflow/Tasks/2026-11-18-agent-free" ]'
assert "taken agent names get the next number" '[ "$(agent_run 1 "agent-busy agent-busy-2" agent-busy)" = "$vault/Workflow/Tasks/2026-11-18-agent-busy-3" ]'
long="abcdefghijklmnopqrstuvwxyz-abcdef"
long_out="$(agent_run 1 "${long:0:32}" "${long:0:32}")"
assert "suffix keeps the slug at 32 characters" '[ "${long_out##*/}" = "2026-11-18-${long:0:30}-2" ]'
assert "outside herdr a taken agent name is ignored" '[ "$(agent_run "" "agent-out" agent-out)" = "$vault/Workflow/Tasks/2026-11-18-agent-out" ]'

headings="$(grep '^## ' "$folder/spec.md" | tr '\n' '|')"
assert "spec has seven sections in order" '[ "$headings" = "## Goal|## Scope|## Verification plan|## Non-undoable steps|## Deliver targets|## Contract changes|## Decisions|" ]'
assert "contract template frontmatter" 'grep -qx "pending: \[\]" "$repo_root/templates/contract.md" && grep -qx "base_branch: {{base_branch}}" "$repo_root/templates/contract.md"'
assert "plan template" '[ -f "$repo_root/templates/plan.md" ]'
assert "decision template" 'grep -qx "status: accepted" "$repo_root/templates/decision.md"'
finish
