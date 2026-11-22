#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/transcript-stats.sh"
fixtures="$repo_root/tests/fixtures/transcripts"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"
session_a=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
session_b=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
session_c=cccccccc-cccc-4ccc-8ccc-cccccccccccc
unknown=dddddddd-dddd-4ddd-8ddd-dddddddddddd

folder_one="$HOME/.claude/projects/-proj-one"
folder_two="$HOME/.claude/projects/-proj-two"
mkdir -p "$folder_one/$session_a/subagents" "$folder_two"
cp "$fixtures/session-a.jsonl" "$folder_one/$session_a.jsonl"
cp "$fixtures/session-c.jsonl" "$folder_one/$session_c.jsonl"
cp "$fixtures/subagent-a.jsonl" "$folder_one/$session_a/subagents/agent-1.jsonl"
cp "$fixtures/session-b.jsonl" "$folder_two/$session_b.jsonl"

out="$(bash "$script" "$session_a" "$session_b" "$unknown")"
field() { jq -c "$1" <<<"$out"; }
assert "sessions counts every id" '[ "$(field .sessions)" = 3 ]'
assert "found counts transcripts that exist" '[ "$(field .found)" = 2 ]'
assert "tool_calls by name" '[ "$(field .tool_calls)" = "{\"Bash\":3,\"Read\":1}" ]'
assert "tool_errors counts is_error true only" '[ "$(field .tool_errors)" = 1 ]'
assert "top_bash row 1 is git status x2" '[ "$(field ".top_bash[0]")" = "{\"command\":\"git status\",\"count\":2}" ]'
assert "top_bash row 2 is ls -la x1" '[ "$(field ".top_bash[1]")" = "{\"command\":\"ls -la\",\"count\":1}" ]'
assert "top_bash has two rows" '[ "$(field ".top_bash | length")" = 2 ]'
assert "compactions" '[ "$(field .compactions)" = 1 ]'
assert "user_turns skips results and meta" '[ "$(field .user_turns)" = 3 ]'
assert "started_at is the earliest timestamp" '[ "$(field .started_at)" = "\"2026-11-22T10:20:00Z\"" ]'
assert "ended_at is the latest timestamp" '[ "$(field .ended_at)" = "\"2026-11-22T11:12:00Z\"" ]'
assert "subagent_tool_calls" '[ "$(field .subagent_tool_calls)" = "{\"Read\":1}" ]'
assert "session c is not counted" '[ "$(field .tool_calls.Read)" = 1 ]'

unknown_out="$(bash "$script" "$unknown")"
assert "unknown id gives found 0" '[ "$(jq -r .found <<<"$unknown_out")" = 0 ]'
assert "unknown id gives null times" '[ "$(jq -r .started_at <<<"$unknown_out")" = null ]'
assert "non-UUID argument exits 1" '! bash "$script" not-a-uuid 2>/dev/null'
finish
