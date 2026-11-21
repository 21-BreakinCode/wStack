#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-hook.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset WSTACK_VAULT_PATH CLAUDE_PLUGIN_OPTION_VAULT_PATH
source "$(bash "$repo_root/tests/fixtures/contract/setup.sh" "$work_dir/world")"

hook() {  # <event> <cwd> <command>
  jq -nc --arg e "$1" --arg c "$2" --arg m "${3:-}" '{hook_event_name:$e,cwd:$c,tool_input:{command:$m}}' | bash "$script"
}
export WSTACK_VAULT_PATH="$VAULT"

out="$(hook SessionStart "$REPO" "")"
assert "session start, fresh: no output" '[ -z "$out" ]'

mkdir -p "$REPO/api"; echo x > "$REPO/api/new.go"
git -C "$REPO" add -A; git -C "$REPO" commit -q -m "api change"; git -C "$REPO" push -q origin main 2>/dev/null

out="$(hook SessionStart "$REPO" "")"
context="$(printf '%s' "$out" | jq -r .hookSpecificOutput.additionalContext)"
assert "session start, stale: one line" '[ "$(printf "%s\n" "$out" | wc -l | tr -d " ")" = 1 ]'
assert "session start, stale: behind" '[[ "$context" == *"1 commits behind origin/main"* ]]'
assert "session start, stale: section" '[[ "$context" == *"Stale: Interfaces"* ]]'

out="$(hook PostToolUse "$REPO" "git pull --ff-only")"
assert "after git pull" '[ "$(printf "%s" "$out" | jq -r .hookSpecificOutput.hookEventName)" = PostToolUse ]'

out="$(hook PostToolUse "$REPO" "ls -la")"
assert "other command: no output" '[ -z "$out" ]'

other="$work_dir/other"; git init -q "$other"
out="$(hook SessionStart "$other" "")"
assert "unmapped: no output" '[ -z "$out" ]'

unset WSTACK_VAULT_PATH
out="$(hook SessionStart "$REPO" "")"
assert "no vault: no output" '[ -z "$out" ]'

out="$(CLAUDE_PLUGIN_OPTION_VAULT_PATH="$VAULT" hook SessionStart "$REPO" "")"
assert "plugin option: one line" '[[ "$out" == *"Stale: Interfaces"* ]]'
finish
