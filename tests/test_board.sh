#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/board.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"; mkdir -p "$HOME"
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export FAKE_LOG="$work_dir/log"
unset HERDR_ENV  # never ask the live herdr session
vault="$work_dir/My Vault"; mkdir -p "$vault"

new_task() {  # <slug> <status> [date]
  local folder
  folder="$(bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug "$1" --date "${3:-$(date +%Y-%m-%d)}" --idea "$1" | tail -n 1)"
  fm_set "$folder/spec.md" status "$2"
  echo "$folder"
}
field() {  # <slug> <jq field> <rows>
  jq -r --arg slug "$1" "select(.slug == \$slug) | $2" <<<"$3"
}

new_task need-idle drafting >/dev/null
new_task need-blocked executing >/dev/null
new_task need-deliver awaiting-deliver-approval >/dev/null
new_task gone-one executing >/dev/null
new_task busy-verify verifying >/dev/null
new_task busy-unknown executing >/dev/null
new_task rest-paused paused >/dev/null
step_folder="$(new_task need-idle2 drafting)"
printf -- '- 2026-11-23T01:00:00Z step spec drafted\n- 2026-11-23T02:00:00Z step last one\n' >> "$step_folder/run-log.md"
fm_set "$step_folder/spec.md" created_at "$(date -v-3H +%Y-%m-%dT%H:%M:%S%z | sed 's/\([0-9][0-9]\)$/:\1/')"
new_task done-here delivered >/dev/null
new_task done-closed delivered >/dev/null
new_task old-done delivered 2020-01-01 >/dev/null
new_task paused-none paused >/dev/null
new_task herdr-error executing >/dev/null
z_folder="$(new_task z-stamp executing)"
fm_set "$z_folder/spec.md" created_at 2020-01-01T00:00:00Z
crlf_folder="$(new_task crlf-goal executing)"
sed -i.bak 's/$/\r/' "$crlf_folder/spec.md"; rm -f "$crlf_folder/spec.md.bak"
new_task odd-one planning >/dev/null
empty_goal="$(new_task empty-goal executing)"
printf -- '---\ntask_id: %s\nstatus: executing\nworkspace_cwd:\ncreated_at: 2026-11-23T01:00:00+00:00\n---\n\n## Goal\n\n## Scope\n' "$(basename "$empty_goal")" > "$empty_goal/spec.md"
rm -f "$empty_goal/run-log.md"

export HERDR_ENV=1 WSTACK_HERDR_SESSION=wstack-test
export FAKE_AGENT_STATES="need-idle=idle,need-idle2=done,need-blocked=blocked,need-deliver=working,busy-verify=working,busy-unknown=unknown,rest-paused=idle,odd-one=weird,empty-goal=working,herdr-error=error,z-stamp=working,crlf-goal=working"
export FAKE_WORKSPACES="done-here=w7,other-label=w8,old-done=w9"
rows="$(/bin/bash "$script" --vault "$vault" --tasks-dir T)"
assert "every row is one JSON line" '[ "$(jq -c . <<<"$rows" | wc -l | tr -d " ")" = "$(wc -l <<<"$rows" | tr -d " ")" ]'
assert "drafting with idle needs you" '[ "$(field need-idle .group "$rows")" = "needs you" ]'
assert "drafting with done needs you" '[ "$(field need-idle2 .group "$rows")" = "needs you" ]'
assert "executing with blocked needs you" '[ "$(field need-blocked .group "$rows")" = "needs you" ]'
assert "awaiting-deliver-approval with working needs you" '[ "$(field need-deliver .group "$rows")" = "needs you" ]'
assert "executing with no agent is stopped" '[ "$(field gone-one .group "$rows")" = stopped ] && [ "$(field gone-one .herdr "$rows")" = none ]'
assert "verifying with working is working" '[ "$(field busy-verify .group "$rows")" = working ]'
assert "executing with unknown is working and says unknown" '[ "$(field busy-unknown .group "$rows")" = working ] && [ "$(field busy-unknown .herdr "$rows")" = unknown ]'
assert "paused status is paused" '[ "$(field rest-paused .group "$rows")" = paused ]'
assert "a row that matches no group is other" '[ "$(field odd-one .group "$rows")" = other ]'
assert "workspace id comes from agent get" '[ "$(field need-blocked .workspace_id "$rows")" = w-need-blocked ]'
assert "delivered task with an open workspace is finished with its id" '[ "$(field done-here .group "$rows")" = finished ] && [ "$(field done-here .workspace_id "$rows")" = w7 ]'
assert "delivered task with no open workspace has no row" '[ -z "$(field done-closed .group "$rows")" ]'
assert "delivered task from long ago with an open workspace is finished" '[ "$(field old-done .group "$rows")" = finished ] && [ "$(field old-done .workspace_id "$rows")" = w9 ]'
assert "paused with no agent is paused, not stopped" '[ "$(field paused-none .group "$rows")" = paused ] && [ "$(field paused-none .herdr "$rows")" = none ]'
assert "a herdr error that is not agent_not_found shows unknown and works" '[ "$(field herdr-error .herdr "$rows")" = unknown ] && [ "$(field herdr-error .group "$rows")" = working ]'
assert "a Z time stamp gives an age in days" '[[ "$(field z-stamp .age "$rows")" =~ ^[0-9]+d$ ]]'
assert "a CRLF spec gives a goal with no carriage return" '[ "$(field crlf-goal .goal "$rows")" = "Rough idea from launch: crlf-goal" ]'
assert "groups follow the design order" '[ "$(jq -r .group <<<"$rows" | uniq | tr "\n" ,)" = "needs you,stopped,working,paused,finished,other," ]'
assert "rows inside a group are sorted by task_id" '[ "$(jq -r "select(.group == \"needs you\") | .slug" <<<"$rows" | tr "\n" ,)" = "need-blocked,need-deliver,need-idle,need-idle2," ]'
assert "goal is the first line under Goal" '[ "$(field need-idle .goal "$rows")" = "Rough idea from launch: need-idle" ]'
assert "last_step is the last Steps line" '[ "$(field need-idle2 .last_step "$rows")" = "- 2026-11-23T02:00:00Z step last one" ]'
assert "age is in hours" '[ "$(field need-idle2 .age "$rows")" = 3h ]'
assert "folder is absolute" '[ "$(field need-idle .folder "$rows")" = "$vault/T/$(date +%Y-%m-%d)-need-idle" ]'
assert "empty Goal and no run-log print an empty goal and last_step" '[ "$(field empty-goal .goal "$rows")" = "" ] && [ "$(field empty-goal .last_step "$rows")" = "" ] && [ "$(field empty-goal .group "$rows")" = working ]'
assert "an old spec with no session_ids still has an age" '[ "$(field empty-goal .age "$rows")" != "" ]'

unset HERDR_ENV
rows="$(/bin/bash "$script" --vault "$vault" --tasks-dir T)"
assert "outside herdr: n/a fields on every row" '[ "$(jq -r "select(.herdr != \"n/a\" or .workspace_id != \"n/a\") | .slug" <<<"$rows" | wc -l | tr -d " ")" = 0 ]'
assert "outside herdr: no finished row" '[ -z "$(jq -r "select(.group == \"finished\")" <<<"$rows")" ]'
assert "outside herdr: every open task is printed" '[ "$(wc -l <<<"$rows" | tr -d " ")" = 14 ]'
assert "outside herdr: paused goes to paused, waiting to needs you, rest to other" '[ "$(field rest-paused .group "$rows")" = paused ] && [ "$(field need-deliver .group "$rows")" = "needs you" ] && [ "$(field gone-one .group "$rows")" = other ]'

# last_tool and subagents come from the newest transcript in session_ids
vault="$work_dir/Activity Vault"; mkdir -p "$vault"
fixture_ids="aaaaaaaa-0000-4000-8000-000000000001 aaaaaaaa-0000-4000-8000-000000000002 aaaaaaaa-0000-4000-8000-000000000003 aaaaaaaa-0000-4000-8000-000000000004"
mkdir -p "$HOME/.claude/projects/-fake-project"
cp -R "$repo_root/tests/fixtures/board-transcripts/." "$HOME/.claude/projects/-fake-project/"
touch -t "$(date -v-2H +%Y%m%d%H%M)" "$HOME"/.claude/projects/-fake-project/aaaaaaaa-0000-4000-8000-000000000001/subagents/agent-stale.jsonl
slug_index=0
for session_id in $fixture_ids; do
  slug_index=$((slug_index + 1))
  bash "$repo_root/scripts/session-id-add.sh" "$(new_task "rd-$slug_index" executing)/spec.md" "$session_id"
done
new_task rd-none executing >/dev/null
twice_folder="$(new_task rd-twice executing)"
bash "$repo_root/scripts/session-id-add.sh" "$twice_folder/spec.md" aaaaaaaa-0000-4000-8000-000000000003
bash "$repo_root/scripts/session-id-add.sh" "$twice_folder/spec.md" aaaaaaaa-0000-4000-8000-000000000002
rows="$(/bin/bash "$script" --vault "$vault" --tasks-dir T)"
assert "last_tool is the last tool_use, with its description as hint" '[ "$(field rd-1 .last_tool.tool "$rows")" = Bash ] && [ "$(field rd-1 .last_tool.hint "$rows")" = "Run the unit tests" ] && [ "$(field rd-1 .last_tool.at "$rows")" = 2026-11-23T01:01:00Z ]'
assert "a Bash command with no description shows its first word only" '[ "$(field rd-2 .last_tool.hint "$rows")" = curl ] && ! grep -q abc123 <<<"$rows"'
assert "a Read shows the base name as hint" '[ "$(field rd-3 .last_tool.hint "$rows")" = login.ts ]'
assert "a hint is 60 characters at most with no newline or tab" '[ "$(field rd-4 .last_tool.hint "$rows" | wc -l | tr -d " ")" = 1 ] && [ "$(field rd-4 .last_tool.hint "$rows" | tr -d "\n" | wc -c | tr -d " ")" = 60 ] && ! field rd-4 .last_tool.hint "$rows" | grep -q "$(printf "\t")"'
assert "only the running subagent is listed, with type, description and its tool" '[ "$(field rd-1 "[.subagents[] | .type + \"|\" + .description + \"|\" + .last_tool.tool] | join(\",\")" "$rows")" = "Explore|Find the login handlers|Grep" ]'
assert "a subagent tool hint cuts a pattern to 40 characters" '[ "$(field rd-1 ".subagents[0].last_tool.hint | length" "$rows")" = 40 ]'
assert "idle_seconds is a small number for a fresh subagent" '[ "$(field rd-1 ".subagents[0].idle_seconds < 60" "$rows")" = true ]'
assert "a task with no session_ids has no tool and no subagents" '[ "$(field rd-none .last_tool "$rows")" = null ] && [ "$(field rd-none ".subagents | length" "$rows")" = 0 ]'
assert "the newest session id is the one read" '[ "$(field rd-twice .last_tool.hint "$rows")" = curl ]'
rows="$(WSTACK_BOARD_ACTIVE_MINUTES=100000 /bin/bash "$script" --vault "$vault" --tasks-dir T)"
assert "a long active window brings the stale subagent back" '[ "$(field rd-1 "[.subagents[].type] | sort | join(\",\")" "$rows")" = "Explore,Plan" ]'
assert "a finished subagent never shows" '[ "$(field rd-1 "[.subagents[].type] | index(\"code-reviewer\")" "$rows")" = null ]'
finish
