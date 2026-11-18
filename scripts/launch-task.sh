#!/usr/bin/env bash
# Usage: launch-task.sh --task-dir <abs> [--repo-path <abs>] [--mobile]
# Opens a herdr workspace named after the task and starts a claude session there.
# Exit codes:
#   1 bad input
#   3 not running inside herdr
#   4 agent name taken
#   5 the claude agent did not start or take the prompt. The workspace stays open and
#     stderr prints the workspace id and the cleanup commands. Nothing is closed automatically.
#   6 herdr could not create the workspace or worktree ("could not create workspace: <herdr stderr>")
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
  create_args=(worktree create --cwd "$repo_path" --branch "wstack/$slug" --label "$slug" --no-focus)
else
  cwd="$HOME/.wstack/tasks/$task_id"
  mkdir -p "$cwd"
  create_args=(workspace create --cwd "$cwd" --label "$slug" --no-focus)
fi
created="$(herdr_cmd "${create_args[@]}" 2>&1)" || fail "could not create workspace: $created" 6
[ "${create_args[0]}" != worktree ] || cwd="$(jq -r '.result.worktree.path' <<<"$created")"
workspace_id="$(jq -r '.result.workspace.workspace_id' <<<"$created")"
pane_id="$(jq -r '.result.root_pane.pane_id' <<<"$created")"
fm_set "$task_dir/spec.md" workspace_cwd "$cwd"

cli="$(herdr_cli_prefix)"
abort_with_cleanup_hint() {  # <reason>
  {
    echo "launch-task: $1"
    echo "workspace $workspace_id is still open. To clean up:"
    echo "  $cli workspace close $workspace_id"
    if [ "${create_args[0]}" = worktree ]; then
      echo "  $cli worktree remove --workspace $workspace_id"
      echo "  git -C $repo_path branch -D wstack/$slug"
    fi
  } >&2
  exit 5
}

herdr_start_claude "$slug" "$pane_id" || abort_with_cleanup_hint "agent $slug did not start"
prompt="/wstack:start-task --task $task_id"
[ "$mobile" = false ] || prompt="$prompt --mobile"
herdr_cmd agent prompt "$slug" "$prompt" >/dev/null || abort_with_cleanup_hint "agent $slug did not take the prompt"
herdr_cmd workspace focus "$workspace_id" >/dev/null || abort_with_cleanup_hint "could not focus workspace $workspace_id"
jq -nc --arg w "$workspace_id" --arg a "$slug" --arg c "$cwd" '{workspace_id: $w, agent: $a, cwd: $c}'
