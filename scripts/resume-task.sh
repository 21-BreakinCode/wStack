#!/usr/bin/env bash
# Usage: resume-task.sh --task-dir <abs>
# Prints "focused" if the task agent is live, "restarted" if it started a new one.
# Exit: 1 working directory gone or bad input, 5 agent not ready.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
source "$script_dir/lib/herdr.sh"
fail() { echo "resume-task: $1" >&2; exit "${2:-1}"; }

[ "${1:-}" = --task-dir ] && [ "$#" -eq 2 ] || fail "usage: resume-task.sh --task-dir <abs>"
task_dir="$2"
[[ "$task_dir" = /* ]] && [ -f "$task_dir/spec.md" ] || fail "no spec.md in task dir: $task_dir"
task_id="$(fm_get "$task_dir/spec.md" task_id)"
slug="${task_id:11}"
[[ "$slug" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail "bad slug in task_id: $task_id"

if agent_json="$(herdr_cmd agent get "$slug" 2>/dev/null)"; then
  herdr_cmd workspace focus "$(jq -r '.result.agent.workspace_id' <<<"$agent_json")" >/dev/null
  echo focused
  exit 0
fi

cwd="$(fm_get "$task_dir/spec.md" workspace_cwd)"
[ -n "$cwd" ] && [ -d "$cwd" ] || fail "working directory $cwd is gone; start a new task"
created="$(herdr_cmd workspace create --cwd "$cwd" --label "$slug" --no-focus)"
workspace_id="$(jq -r '.result.workspace.workspace_id' <<<"$created")"
herdr_start_claude "$slug" "$(jq -r '.result.root_pane.pane_id' <<<"$created")" --continue || exit $?
herdr_cmd workspace focus "$workspace_id" >/dev/null
echo restarted
