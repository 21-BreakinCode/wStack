#!/usr/bin/env bash
# Usage: transcript-stats.sh <session-id>...
# Prints one JSON object of tool use, errors, compactions, user turns and time range for the given sessions.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/transcripts.sh"

for session_id in "$@"; do
  session_id_ok "$session_id" || { echo "transcript-stats: bad session id: $session_id" >&2; exit 1; }
done

main_files="$(transcript_main_files "$@")"
subagent_files="$(transcript_subagent_files "$@")"

slurp_files() {  # <newline list of files>: print one JSON array of all lines
  [ -n "$1" ] || { echo '[]'; return 0; }
  printf '%s\n' "$1" | tr '\n' '\0' | xargs -0 cat | jq -s '.'
}

subagent_tool_calls="$(slurp_files "$subagent_files" | jq -c '
  [.[] | select(.type == "assistant") | .message.content[]? | select(.type? == "tool_use") | .name]
  | group_by(.) | map({key: .[0], value: length}) | from_entries')"

slurp_files "$main_files" | jq \
  --argjson sessions "$#" \
  --argjson found "$(printf '%s' "$main_files" | grep -c . || true)" \
  --argjson subagent_tool_calls "$subagent_tool_calls" '
  def items($line_type; $item_type):
    [.[] | select(.type == $line_type) | .message.content | arrays | .[] | select(.type? == $item_type)];
  items("assistant"; "tool_use") as $tool_uses
  | ([.[].timestamp | strings] | sort) as $times
  | {
      sessions: $sessions,
      found: $found,
      tool_calls: ($tool_uses | group_by(.name) | map({key: .[0].name, value: length}) | from_entries),
      tool_errors: (items("user"; "tool_result") | map(select(.is_error == true)) | length),
      top_bash: ([$tool_uses[] | select(.name == "Bash") | .input.command | strings | split(" ") | map(select(. != "")) | .[:2] | join(" ")]
        | group_by(.) | map({command: .[0], count: length})
        | sort_by([-.count, .command]) | .[:10]),
      compactions: ([.[] | select(.type == "system" and .subtype == "compact_boundary")] | length),
      user_turns: ([.[] | select(.type == "user" and (.isMeta | not) and (.isCompactSummary | not)
        and (((.message.content | arrays | map(select(.type? == "tool_result")) | length) // 0) == 0))] | length),
      started_at: ($times[0]),
      ended_at: ($times[-1]),
      subagent_tool_calls: $subagent_tool_calls
    }'
