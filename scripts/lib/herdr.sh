#!/usr/bin/env bash
# herdr helpers shared by launch-task.sh, resume-task.sh and new-task-folder.sh. Source this file.
set -euo pipefail

herdr_cmd() {
  if [ -n "${WSTACK_HERDR_SESSION:-}" ]; then herdr --session "$WSTACK_HERDR_SESSION" "$@"; else herdr "$@"; fi
}

herdr_cli_prefix() {  # the herdr command a user types to reach the same session
  if [ -n "${WSTACK_HERDR_SESSION:-}" ]; then echo "herdr --session $WSTACK_HERDR_SESSION"; else echo herdr; fi
}

# Prints one field of herdr JSON. Fails when jq fails or the field is missing, so callers can handle it.
json_field() {  # <json> <jq path>
  local value
  value="$(jq -r "$2" <<<"$1")" || return 1
  [ -n "$value" ] && [ "$value" != null ] || return 1
  printf '%s\n' "$value"
}

# The one place that defines the claude flags of a task session. One flag per line.
claude_task_flags() {  # <slug>
  printf '%s\n' --remote-control "$1" --name "$1" --permission-mode bypassPermissions
}

# Starts claude in <pane> and accepts the folder-trust prompt. Call it only for a
# directory that the calling script created or that spec.md records.
# Exit 5 on any other start failure.
herdr_start_claude() {  # <slug> <pane> [extra claude flags...]
  local slug="$1" pane="$2" start_output pane_text waited=0 ready
  shift 2
  local flags=() flag
  while IFS= read -r flag; do flags+=("$flag"); done < <(claude_task_flags "$slug")

  start_output="$(herdr_cmd agent start "$slug" --kind claude --pane "$pane" -- "${flags[@]}" "$@" 2>&1)" && return 0
  case "$start_output" in
    *agent_not_ready*) ;;
    *) echo "agent start failed: $start_output" >&2; return 5 ;;
  esac

  pane_text="$(herdr_cmd agent read "$slug" --source recent-unwrapped --lines 40 2>&1 || true)"
  case "$pane_text" in
    *"Yes, I trust this folder"*) ;;
    *) echo "agent not ready: $pane_text" >&2; return 5 ;;
  esac
  herdr_cmd pane send-keys "$pane" Down Enter >/dev/null
  while [ "$waited" -lt "${WSTACK_TRUST_TIMEOUT:-60}" ]; do
    ready="$(herdr_cmd agent list | jq -r --arg name "$slug" '[.result.agents[] | select(.name == $name) | .interactive_ready] | first // false')"
    [ "$ready" = "true" ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  echo "agent $slug not ready ${WSTACK_TRUST_TIMEOUT:-60}s after the trust prompt" >&2
  return 5
}
