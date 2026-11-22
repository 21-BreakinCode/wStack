#!/usr/bin/env bash
# Print the total token count of the newest Claude Code session for a directory (decision S8).
# usage: session-tokens.sh <cwd>
#        session-tokens.sh --session <id> [--session <id>]...
# Reads ~/.claude/projects/<cwd with every non-alphanumeric character as "-">/*.jsonl, newest file by mtime.
# The transcript repeats each assistant message, so usage is grouped by message.id (last line wins).
# The --session form prints two lines: the main-transcript total, then the subagent total (0 if none).
# Exit 2 with no output when the folder or transcript is missing or holds no usage.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/lib/transcripts.sh"

# <file>...: sum the usage of all files, each message.id once (last line wins). Prints nothing when no usage.
sum_usage() {
  jq -s '[.[]|select(.message.usage!=null)]|group_by(.message.id)|map(.[-1].message.usage)|map((.input_tokens//0)+(.cache_creation_input_tokens//0)+(.cache_read_input_tokens//0)+(.output_tokens//0))|add // empty' "$@"
}

if [ "${1:-}" = "--session" ]; then
  session_ids=()
  while [ $# -gt 0 ]; do
    [ "$1" = "--session" ] && [ $# -ge 2 ] && session_id_ok "$2" || { echo "usage: session-tokens.sh --session <id> [--session <id>]..." >&2; exit 2; }
    session_ids+=("$2"); shift 2
  done
  main_files=(); while IFS= read -r f; do main_files+=("$f"); done < <(transcript_main_files "${session_ids[@]}")
  [ ${#main_files[@]} -gt 0 ] || exit 2
  subagent_files=(); while IFS= read -r f; do subagent_files+=("$f"); done < <(transcript_subagent_files "${session_ids[@]}")
  main_total="$(sum_usage "${main_files[@]}")"
  [ -n "$main_total" ] || exit 2
  subagent_total=0
  [ ${#subagent_files[@]} -eq 0 ] || subagent_total="$(sum_usage "${subagent_files[@]}")"
  echo "$main_total"; echo "${subagent_total:-0}"
  exit 0
fi


[ $# -eq 1 ] || { echo "usage: session-tokens.sh <cwd>" >&2; exit 2; }
real_cwd="$(cd "$1" 2>/dev/null && pwd -P)" || exit 2
project_dir="$HOME/.claude/projects/$(printf '%s' "$real_cwd" | sed 's/[^A-Za-z0-9]/-/g')"
[ -d "$project_dir" ] || exit 2
transcript="$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -n 1 || true)"
[ -n "$transcript" ] || exit 2

total="$(sum_usage "$transcript")"
[ -n "$total" ] || exit 2
echo "$total"
