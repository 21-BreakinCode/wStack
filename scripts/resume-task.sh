#!/usr/bin/env bash
# Usage: resume-task.sh --task-dir <abs>
# Prints "focused" if the task agent is live, "restarted" if it started a new one
# (claude --resume <last id> when session_ids has ids, else claude --continue).
# Exit: 1 working directory gone or bad input, 5 agent did not start or the workspace could
# not be focused (a restarted workspace stays open, stderr prints the cleanup command),
# 6 herdr could not create the workspace or printed unexpected output.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
source "$script_dir/lib/herdr.sh"
source "$script_dir/lib/transcripts.sh"
fail() { echo "resume-task: $1" >&2; exit "${2:-1}"; }

[ "${1:-}" = --task-dir ] && [ "$#" -eq 2 ] || fail "usage: resume-task.sh --task-dir <abs>"
task_dir="$2"
[[ "$task_dir" = /* ]] && [ -f "$task_dir/spec.md" ] || fail "no spec.md in task dir: $task_dir"
task_id="$(fm_get "$task_dir/spec.md" task_id)"
slug="${task_id:11}"
[[ "$slug" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail "bad slug in task_id: $task_id"

if agent_json="$(herdr_cmd agent get "$slug" 2>/dev/null)"; then
  live_workspace_id="$(json_field "$agent_json" '.result.agent.workspace_id')" || fail "agent $slug has no workspace id" 5
  herdr_cmd workspace focus "$live_workspace_id" >/dev/null || fail "could not focus workspace $live_workspace_id" 5
  echo focused
  exit 0
fi

cwd="$(fm_get "$task_dir/spec.md" workspace_cwd)"
[ -n "$cwd" ] && [ -d "$cwd" ] || fail "working directory $cwd is gone; start a new task"
created="$(herdr_cmd workspace create --cwd "$cwd" --label "$slug" --no-focus 2>&1)" || fail "could not create workspace: $created" 6
workspace_id="$(json_field "$created" '.result.workspace.workspace_id')" || fail "unexpected herdr output: $created" 6
pane_id="$(json_field "$created" '.result.root_pane.pane_id')" || fail "unexpected herdr output: $created" 6
abort_with_cleanup_hint() {  # <reason>
  echo "resume-task: $1" >&2
  echo "workspace $workspace_id is still open. To clean up: $(herdr_cli_prefix) workspace close $workspace_id" >&2
  exit 5
}
last_session_id=""
session_ids_value="$(fm_get "$task_dir/spec.md" session_ids)"
if [ -z "$session_ids_value" ] && fm_has_block_list "$task_dir/spec.md" session_ids; then session_ids_value="(block-style list)"; fi
if [ -n "$session_ids_value" ]; then
  last_session_id="$(jq -r 'if type == "array" then (.[-1] // empty) else error("not an array") end' <<<"$session_ids_value" 2>/dev/null)" || last_session_id="bad"
  if [ -n "$last_session_id" ] && ! session_id_ok "$last_session_id"; then
    echo "resume-task: session_ids is not a list of session ids, using --continue: $session_ids_value" >&2
    last_session_id=""
  fi
fi
if [ -n "$last_session_id" ]; then resume_flags=(--resume "$last_session_id"); else resume_flags=(--continue); fi
herdr_start_claude "$slug" "$pane_id" "${resume_flags[@]}" || abort_with_cleanup_hint "agent $slug did not start"
herdr_cmd workspace focus "$workspace_id" >/dev/null || abort_with_cleanup_hint "could not focus workspace $workspace_id"
echo restarted
