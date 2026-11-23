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
assert "tool_calls by name" '[ "$(field .tool_calls)" = "{\"Bash\":5,\"Read\":1}" ]'
assert "tool_errors counts is_error true only" '[ "$(field .tool_errors)" = 1 ]'
assert "top_bash row 1 is git status x3 (newline splits words)" '[ "$(field ".top_bash[0]")" = "{\"command\":\"git status\",\"count\":3}" ]'
assert "top_bash tie: ab cd sorts before ls" '[ "$(field ".top_bash[1]")" = "{\"command\":\"ab cd\",\"count\":1}" ]'
assert "top_bash row 3 is ls x1 (option word dropped)" '[ "$(field ".top_bash[2]")" = "{\"command\":\"ls\",\"count\":1}" ]'
assert "top_bash has three rows" '[ "$(field ".top_bash | length")" = 3 ]'
assert "compactions" '[ "$(field .compactions)" = 1 ]'
assert "user_turns skips results, meta and compact summary" '[ "$(field .user_turns)" = 3 ]'
assert "started_at is the earliest timestamp" '[ "$(field .started_at)" = "\"2026-11-22T10:20:00Z\"" ]'
assert "ended_at is the latest timestamp" '[ "$(field .ended_at)" = "\"2026-11-22T11:12:00Z\"" ]'
assert "subagent_tool_calls" '[ "$(field .subagent_tool_calls)" = "{\"Read\":1}" ]'
assert "session c is not counted" '[ "$(field .tool_calls.Read)" = 1 ]'

# one id in two project folders: first file lacks a trailing newline, second ends in a truncated line
session_e=eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee
cp "$fixtures/session-e-part1.jsonl" "$folder_one/$session_e.jsonl"
cp "$fixtures/session-e-part2.jsonl" "$folder_two/$session_e.jsonl"
bad_out="$(bash "$script" "$session_e")"
assert "bad lines: exit 0 and good lines from both files count" '[ "$(jq -c .tool_calls <<<"$bad_out")" = "{\"Bash\":1,\"Read\":1}" ]'
assert "one id in two folders: sessions 1, found 1" '[ "$(jq -c "[.sessions, .found]" <<<"$bad_out")" = "[1,1]" ]'

# top_bash keeps no secrets: NAME=value words drop, odd second words drop
session_f=ffffffff-ffff-4fff-8fff-ffffffffffff
bash_line() { jq -nc --arg cmd "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:$cmd}}]}}'; }
{ bash_line 'TOKEN=abc git status'; bash_line 'secret=xyz curl -s https://u:p@h'; } >"$folder_one/$session_f.jsonl"
secret_out="$(bash "$script" "$session_f")"
assert "top_bash drops a leading NAME=value word" '[ "$(jq -r ".top_bash[].command" <<<"$secret_out" | grep -cx "git status")" = 1 ]'
assert "top_bash keeps only curl when the second word is an option" 'jq -r ".top_bash[].command" <<<"$secret_out" | grep -qx curl'
assert "no output holds the secrets" '! grep -q -e abc -e xyz -e "u:p" <<<"$secret_out"'

# top_bash keeps no secret from a quoted value, an escaped space, a literal second word, or a URL command
session_g=99999999-9999-4999-8999-999999999999
{ bash_line 'AUTH="Bearer ghp_QUOTED1" curl -H x'
  bash_line "X='one ghp_QUOTED2' run it"
  bash_line 'TOKEN=part\ tail2 make'
  bash_line 'echo ghp_LITERAL3 | gh auth login --with-token'
  bash_line 'wget host.example/path/LITERAL4'
  bash_line 'https://u:pw5@h/x'
  bash_line 'echo "unclosed LITERAL6'
} >"$folder_one/$session_g.jsonl"
shapes_out="$(bash "$script" "$session_g")"
assert "top_bash lists only safe words for the leak shapes" '[ "$(jq -c "[.top_bash[].command]" <<<"$shapes_out")" = "[\"echo\",\"curl\",\"make\",\"run it\",\"wget\"]" ]'
assert "no output holds the leak-shape secrets" '! grep -q -e ghp_ -e LITERAL -e tail2 -e pw5 -e Bearer <<<"$shapes_out"'

unknown_out="$(bash "$script" "$unknown")"
assert "unknown id gives found 0" '[ "$(jq -r .found <<<"$unknown_out")" = 0 ]'
assert "unknown id gives null times" '[ "$(jq -r .started_at <<<"$unknown_out")" = null ]'
assert "non-UUID argument exits 1" '! bash "$script" not-a-uuid 2>/dev/null'
finish
