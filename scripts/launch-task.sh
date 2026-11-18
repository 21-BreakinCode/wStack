#!/usr/bin/env bash
# Usage: launch-task.sh --task-dir <abs> [--repo-path <abs>] [--mobile]
# Opens a herdr workspace named after the task and starts a claude session there.
# Exit: 1 bad input, 3 not inside herdr, 4 agent name taken, 5 agent not ready.
# Prints {"workspace_id","agent","cwd"} on success.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
source "$script_dir/lib/herdr.sh"
fail() { echo "launch-task: $1" >&2; exit "${2:-1}"; }

task_dir="" repo_path="" mobile=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mobile) mobile=true; shift ;;
    --task-dir|--repo-path) [ "$#" -ge 2 ] || fail "missing value for $1"
      if [ "$1" = --task-dir ]; then task_dir="$2"; else repo_path="$2"; fi; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[ "${HERDR_ENV:-}" = 1 ] || fail "not running inside herdr" 3
[[ "$task_dir" = /* ]] && [ -f "$task_dir/spec.md" ] || fail "no spec.md in task dir: $task_dir"
task_id="$(fm_get "$task_dir/spec.md" task_id)"
work_type="$(fm_get "$task_dir/spec.md" work_type)"
slug="${task_id:11}"
[[ "$slug" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail "bad slug in task_id: $task_id"

if herdr_cmd agent get "$slug" >/dev/null 2>&1; then fail "agent name taken: $slug" 4; fi

if [ "$work_type" = code ] && [ -n "$repo_path" ]; then
  created="$(herdr_cmd worktree create --cwd "$repo_path" --branch "wstack/$slug" --label "$slug" --no-focus)"
  cwd="$(jq -r '.result.worktree.path' <<<"$created")"
else
  cwd="$HOME/.wstack/tasks/$task_id"
  mkdir -p "$cwd"
  created="$(herdr_cmd workspace create --cwd "$cwd" --label "$slug" --no-focus)"
fi
workspace_id="$(jq -r '.result.workspace.workspace_id' <<<"$created")"
pane_id="$(jq -r '.result.root_pane.pane_id' <<<"$created")"
fm_set "$task_dir/spec.md" workspace_cwd "$cwd"

herdr_start_claude "$slug" "$pane_id" || exit $?
prompt="/wstack:start-task --task $task_id"
[ "$mobile" = false ] || prompt="$prompt --mobile"
herdr_cmd agent prompt "$slug" "$prompt" >/dev/null
herdr_cmd workspace focus "$workspace_id" >/dev/null
jq -nc --arg w "$workspace_id" --arg a "$slug" --arg c "$cwd" '{workspace_id: $w, agent: $a, cwd: $c}'
