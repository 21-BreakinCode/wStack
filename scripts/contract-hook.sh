#!/usr/bin/env bash
# SessionStart and PostToolUse hook: tells the agent when the service contract is stale.
# Never blocks, no network, prints nothing unless the contract check exits 1.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git_pattern='(^|[;&|[:space:]])(git (pull|merge|rebase|switch|checkout|reset)|gh pr checkout)([[:space:]]|$)'

vault="${WSTACK_VAULT_PATH:-${CLAUDE_PLUGIN_OPTION_VAULT_PATH:-}}"
[ -n "$vault" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null)" || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)" || exit 0
command_text="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0
[ -n "$cwd" ] || exit 0
if [ "$event" = PostToolUse ] && ! [[ "$command_text" =~ $git_pattern ]]; then exit 0; fi

contract="$(bash "$script_dir/contract-path.sh" --vault "$vault" "$cwd" 2>/dev/null)" || exit 0
set +e
report="$(bash "$script_dir/contract-check.sh" "$cwd" "$contract" 2>/dev/null)"
check_rc=$?
set -e
[ "$check_rc" -eq 1 ] || exit 0

field() { printf '%s\n' "$report" | sed -n "s/^$1: //p"; }
app_name="$(basename "$contract" .md)"
sections="$(field stale_sections | jq -r 'join(", ")')" || exit 0
message="wStack: $app_name contract is $(field behind) commits behind $(field base). Stale: $sections. A new spec runs the contract gate first."
jq -nc --arg event "$event" --arg message "$message" \
  '{hookSpecificOutput:{hookEventName:$event,additionalContext:$message}}'
