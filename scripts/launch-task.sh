#!/usr/bin/env bash
# Usage: launch-task.sh --task-dir <abs> [--repo-path <abs>] [--mobile]
# Opens a herdr workspace named after the task and starts a claude session there.
# Exit codes:
#   1 bad input
#   3 not running inside herdr (sets workspace_cwd first: for a code task with a repository, a new
#     worktree at <herdr worktrees root>/<repo>/<branch slug> on branch wstack/<slug>; else the repository or the current folder)
#   4 agent name taken
#   5 the claude agent did not start or take the prompt. The workspace stays open and
#     stderr prints the workspace id and the cleanup commands. Nothing is closed automatically.
#   6 herdr (or git, outside herdr) could not create the workspace or worktree ("could not create workspace: <stderr>")
# Exit 4 and 6 set status to cancelled first, so the task leaves the open list.
# Prints {"workspace_id","agent","cwd"} on success.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
source "$script_dir/lib/herdr.sh"
fail() { echo "launch-task: $1" >&2; exit "${2:-1}"; }
cancel_and_fail() {  # <message> <exit code>
  fm_set "$task_dir/spec.md" status cancelled
  fail "$1" "$2"
}

herdr_worktree_root() {  # the [worktrees] directory of the herdr config, or ~/.herdr/worktrees
  local config_file="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}" root=""
  if [ -f "$config_file" ]; then
    root="$(awk '
      /^[[:space:]]*\[/ { in_worktrees = ($0 ~ /^[[:space:]]*\[worktrees\][[:space:]]*(#.*)?$/); next }
      in_worktrees && /^[[:space:]]*directory[[:space:]]*=/ {
        value = $0; sub(/^[^=]*=[[:space:]]*/, "", value)
        if (match(value, /^"[^"]*"/) || match(value, /^'"'"'[^'"'"']*'"'"'/)) value = substr(value, 2, RLENGTH - 2)
        else { sub(/[[:space:]]*#.*$/, "", value); sub(/[[:space:]]+$/, "", value) }
        print value; exit
      }' "$config_file")"
  fi
  case "$root" in
    "~") root="$HOME" ;;
    "~/"*) root="$HOME/${root#"~/"}" ;;
  esac
  [[ "$root" = /* ]] || root="$HOME/.herdr/worktrees"
  printf '%s\n' "$root"
}

task_dir="" repo_path="" mobile=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mobile) mobile=true; shift ;;
    --task-dir|--repo-path) [ "$#" -ge 2 ] || fail "missing value for $1"
      if [ "$1" = --task-dir ]; then task_dir="$2"; else repo_path="$2"; fi; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ "$task_dir" = /* ]] && [ -f "$task_dir/spec.md" ] || fail "no spec.md in task dir: $task_dir"
task_id="$(fm_get "$task_dir/spec.md" task_id)"
work_type="$(fm_get "$task_dir/spec.md" work_type)"
if [ "${HERDR_ENV:-}" != 1 ]; then  # this session does the work in session_cwd
  session_cwd="$PWD"
  if [ -n "$repo_path" ] && { [ "$work_type" = code ] || [ "$work_type" = contract ]; }; then session_cwd="$repo_path"; fi
  if [ -n "$repo_path" ] && [ "$work_type" = code ]; then  # a worktree keeps two tasks in one repository apart
    task_branch="wstack/${task_id:11}"
    repo_name="$(basename "$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null || echo "$repo_path")")"
    session_cwd="$(herdr_worktree_root)/$repo_name/${task_branch//\//-}"  # herdr turns the branch slash into a dash
    if [ ! -e "$session_cwd/.git" ]; then
      mkdir -p "$(dirname "$session_cwd")"
      worktree_output="$(git -C "$repo_path" worktree add -b "$task_branch" "$session_cwd" 2>&1)" \
        || cancel_and_fail "could not create worktree: $worktree_output" 6
    fi
  fi
  fm_set "$task_dir/spec.md" workspace_cwd "$session_cwd"
  fail "not running inside herdr" 3
fi
slug="${task_id:11}"
[[ "$slug" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail "bad slug in task_id: $task_id"

if herdr_cmd agent get "$slug" >/dev/null 2>&1; then cancel_and_fail "agent name taken: $slug" 4; fi

if [ "$work_type" = code ] && [ -n "$repo_path" ]; then
  create_args=(worktree create --cwd "$repo_path" --branch "wstack/$slug" --label "$slug" --no-focus)
elif [ "$work_type" = contract ] && [ -n "$repo_path" ]; then
  cwd="$repo_path"  # a contract task only reads origin/<base_branch>, so it needs no worktree
  create_args=(workspace create --cwd "$cwd" --label "$slug" --no-focus)
else
  cwd="$HOME/.wstack/tasks/$task_id"
  mkdir -p "$cwd"
  create_args=(workspace create --cwd "$cwd" --label "$slug" --no-focus)
fi
created="$(herdr_cmd "${create_args[@]}" 2>&1)" || cancel_and_fail "could not create workspace: $created" 6
workspace_id="$(json_field "$created" '.result.workspace.workspace_id')" || cancel_and_fail "unexpected herdr output: $created" 6
pane_id="$(json_field "$created" '.result.root_pane.pane_id')" || cancel_and_fail "unexpected herdr output: $created" 6
if [ "${create_args[0]}" = worktree ]; then
  cwd="$(json_field "$created" '.result.worktree.path')" || cancel_and_fail "unexpected herdr output: $created" 6
fi

cli="$(herdr_cli_prefix)"
abort_with_cleanup_hint() {  # <reason>
  {
    echo "launch-task: $1"
    echo "workspace $workspace_id is still open. To clean up:"
    echo "  $cli workspace close $workspace_id"
    if [ "${create_args[0]}" = worktree ]; then
      echo "  $cli worktree remove --workspace $workspace_id"
      echo "  git -C \"$repo_path\" branch -D wstack/$slug"
    fi
  } >&2
  exit 5
}

fm_set "$task_dir/spec.md" workspace_cwd "$cwd" || abort_with_cleanup_hint "could not write workspace_cwd"
herdr_start_claude "$slug" "$pane_id" || abort_with_cleanup_hint "agent $slug did not start"
prompt="/wstack:start-task --task $task_id"
[ "$mobile" = false ] || prompt="$prompt --mobile"
herdr_cmd agent prompt "$slug" "$prompt" >/dev/null || abort_with_cleanup_hint "agent $slug did not take the prompt"
herdr_cmd workspace focus "$workspace_id" >/dev/null || abort_with_cleanup_hint "could not focus workspace $workspace_id"
jq -nc --arg w "$workspace_id" --arg a "$slug" --arg c "$cwd" '{workspace_id: $w, agent: $a, cwd: $c}'
