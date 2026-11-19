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
finish
