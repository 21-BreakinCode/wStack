#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/session-tokens.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"

# Claude Code names the project folder after the cwd with every non-alphanumeric character as "-".
work_cwd="$work_dir/my proj.v2"
mkdir -p "$work_cwd"
real_cwd="$(cd "$work_cwd" && pwd -P)"
encoded_cwd="$(printf '%s' "$real_cwd" | sed 's/[^A-Za-z0-9]/-/g')"
project_dir="$HOME/.claude/projects/$encoded_cwd"
mkdir -p "$project_dir"

# Older session: 1000 tokens. Must be ignored.
echo '{"message":{"id":"old","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}' > "$project_dir/old.jsonl"
touch -t 202001010000 "$project_dir/old.jsonl"

# Newest session. Message m1 repeats on 2 lines (counted once: 10+20+30+40 = 100). m2 = 1+2+3+4 = 10.
cat > "$project_dir/new.jsonl" <<'JSON'
{"type":"user","message":{"role":"user"}}
{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":5}}}
{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40}}}
{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}
JSON

status=0; out="$(bash "$script" "$work_cwd")" || status=$?
assert "exits 0" '[ "$status" -eq 0 ]'
assert "total counts m1 once and ignores the older session (110)" '[ "$out" = 110 ]'

status=0; out="$(bash "$script" "$work_dir/no-such-dir")" || status=$?
assert "unknown cwd exits 2" '[ "$status" -eq 2 ]'
assert "unknown cwd prints nothing" '[ -z "$out" ]'

status=0; out="$(bash "$script")" 2>/dev/null || status=$?
assert "no argument exits 2" '[ "$status" -eq 2 ]'

# --session mode: lookup by session id across project folders, subagents apart.
id_a=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa; id_b=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb; id_c=cccccccc-cccc-cccc-cccc-cccccccccccc
other_dir="$HOME/.claude/projects/-other-project"
mkdir -p "$other_dir"
usage_line() { echo "{\"message\":{\"id\":\"$1\",\"usage\":{\"input_tokens\":$2,\"output_tokens\":0}}}"; }
usage_line ma 100 > "$project_dir/$id_a.jsonl"
usage_line mb 10 > "$project_dir/$id_b.jsonl"
usage_line mc 5 > "$other_dir/$id_c.jsonl"

out="$(bash "$script" --session "$id_a")"
assert "--session prints main total then 0 without subagents" '[ "$out" = "$(printf "100\n0")" ]'
out="$(bash "$script" --session "$id_a" --session "$id_c")"
assert "--session sums ids across project folders" '[ "$out" = "$(printf "105\n0")" ]'

mkdir -p "$project_dir/$id_a/subagents"
usage_line sx 3 > "$project_dir/$id_a/subagents/agent-x.jsonl"
usage_line sx 7 >> "$project_dir/$id_a/subagents/agent-x.jsonl"
out="$(bash "$script" --session "$id_a")"
assert "subagent total is line 2, repeated message id counts once, line 1 unchanged" '[ "$out" = "$(printf "100\n7")" ]'

status=0; out="$(bash "$script" --session dddddddd-dddd-dddd-dddd-dddddddddddd)" || status=$?
assert "unknown session id exits 2" '[ "$status" -eq 2 ]'
assert "unknown session id prints nothing" '[ -z "$out" ]'
status=0; out="$(bash "$script" --session not-a-uuid 2>/dev/null)" || status=$?
assert "bad session id exits 2" '[ "$status" -eq 2 ]'
assert "bad session id prints nothing" '[ -z "$out" ]'

# A second subagent file in another project folder: line 2 sums across files and folders.
mkdir -p "$other_dir/$id_c/subagents"
usage_line sy 20 > "$other_dir/$id_c/subagents/agent-y.jsonl"
out="$(bash "$script" --session "$id_a" --session "$id_c")"
assert "subagent total sums both files in both folders (7+20)" '[ "$out" = "$(printf "105\n27")" ]'

# A missing id warns on stderr while the found total stays on stdout.
out="$(bash "$script" --session "$id_a" --session dddddddd-dddd-dddd-dddd-dddddddddddd 2>"$work_dir/warn.txt")"
assert "missing id keeps the found total on stdout" '[ "$out" = "$(printf "100\n7")" ]'
assert "missing id warns on stderr" 'grep -qx "session-tokens: no transcript for dddddddd-dddd-dddd-dddd-dddddddddddd" "$work_dir/warn.txt"'

# A cut-off line is skipped in both modes.
id_e=eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
{ usage_line me 40; echo '{"message":{"id":"cut","usa'; } > "$project_dir/$id_e.jsonl"
out="$(bash "$script" --session "$id_e")"
assert "--session skips a cut-off line" '[ "$out" = "$(printf "40\n0")" ]'
{ cat "$project_dir/new.jsonl"; echo '{"message":{"id":"cut","usa'; } > "$project_dir/new2.jsonl"
touch -t 203001010000 "$project_dir/new2.jsonl"  # newest even on a file system with whole-second times
out="$(bash "$script" "$work_cwd")"
assert "cwd mode skips a cut-off line" '[ "$out" = 110 ]'

# transcript_subagent_dirs prints each existing subagents folder.
source "$repo_root/scripts/lib/transcripts.sh"
dirs="$(transcript_subagent_dirs "$id_a" "$id_c" "$id_b")"
assert "transcript_subagent_dirs lists the folders that exist" '[ "$dirs" = "$(printf "%s\n%s" "$project_dir/$id_a/subagents" "$other_dir/$id_c/subagents")" ]'
finish
