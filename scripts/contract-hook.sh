#!/usr/bin/env bash
# SessionStart and PostToolUse hook: tells the agent when the service contract is stale.
# Never blocks, no network, prints nothing unless the contract check exits 1.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# git [-C dir | -c key=val]... <verb>, anywhere in a compound command; the verb ends at a space or ; & |
git_pattern='(^|[;&|[:space:]])((/?[^[:space:]"'"'"'/]+/)*git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+(pull|merge|rebase|switch|checkout|reset)|gh pr checkout)([[:space:];&|]|$)'

vault="${WSTACK_VAULT_PATH:-${CLAUDE_PLUGIN_OPTION_VAULT_PATH:-}}"
[ -n "$vault" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# One jq call; fields are joined with the unit separator so empty fields stay empty.
fields="$(jq -r '[.hook_event_name // "", .cwd // "", .tool_input.command // ""] | join("\u001f")' 2>/dev/null)" || exit 0
IFS=$'\037' read -r -d '' event cwd command_text <<<"$fields" || true
[ -n "$event" ] && [ -n "$cwd" ] || exit 0
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
unclaimed_count="$(field unclaimed_count)"
detail=""
[ -z "$sections" ] || detail=" Stale: $sections."
if [ "$unclaimed_count" = 1 ]; then detail="$detail 1 unclaimed file changed."; elif [ "$unclaimed_count" != 0 ]; then detail="$detail $unclaimed_count unclaimed files changed."; fi
message="wStack: $app_name contract is $(field behind) commits behind $(field base).$detail A new spec runs the contract gate first."
jq -nc --arg event "$event" --arg message "$message" \
  '{hookSpecificOutput:{hookEventName:$event,additionalContext:$message}}'
