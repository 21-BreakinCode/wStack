#!/usr/bin/env bash
# Print the total token count of the newest Claude Code session for a directory (decision S8).
# usage: session-tokens.sh <cwd>
# Reads ~/.claude/projects/<cwd with every non-alphanumeric character as "-">/*.jsonl, newest file by mtime.
# The transcript repeats each assistant message, so usage is grouped by message.id (last line wins).
# Exit 2 with no output when the folder or transcript is missing or holds no usage.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: session-tokens.sh <cwd>" >&2; exit 2; }
real_cwd="$(cd "$1" 2>/dev/null && pwd -P)" || exit 2
project_dir="$HOME/.claude/projects/$(printf '%s' "$real_cwd" | sed 's/[^A-Za-z0-9]/-/g')"
[ -d "$project_dir" ] || exit 2
transcript="$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -n 1 || true)"
[ -n "$transcript" ] || exit 2

total="$(jq -s '[.[]|select(.message.usage!=null)]|group_by(.message.id)|map(.[-1].message.usage)|map((.input_tokens//0)+(.cache_creation_input_tokens//0)+(.cache_read_input_tokens//0)+(.output_tokens//0))|add // empty' "$transcript")"
[ -n "$total" ] || exit 2
echo "$total"
