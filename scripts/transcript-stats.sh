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

slurp_files() {  # <newline list of files>: print one JSON array of every parsable object line
  local file
  while IFS= read -r file; do
    if [ -n "$file" ]; then jq -R 'fromjson? // empty | select(type == "object")' "$file"; fi
  done <<<"$1" | jq -s '.'
}

found=0
for session_id in "$@"; do
  [ -n "$(transcript_main_files "$session_id")" ] && found=$((found + 1))
done

subagent_tool_calls="$(slurp_files "$subagent_files" | jq -c '
  [.[] | select(.type == "assistant") | .message.content[]? | select(.type? == "tool_use") | .name]
  | group_by(.) | map({key: .[0], value: length}) | from_entries')"

slurp_files "$main_files" | jq \
  --argjson sessions "$#" \
  --argjson found "$found" \
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
      # Secrets stay out. Escaped characters go first, then quoted text. A command that still holds a quote
      # or a backslash drops out. Leading NAME=value words drop. The first word must be a plain command name.
      # A second word stays only after a tool that takes subcommands, and only in the shape of a subcommand.
      top_bash: ([$tool_uses[] | select(.name == "Bash") | .input.command | strings
          | gsub("\\\\."; "") | gsub("\"[^\"]*\"|\u0027[^\u0027]*\u0027"; "")
          | select(test("[\"\u0027\\\\]") | not)
          | [scan("\\S+")] | until(.[0] // "" | test("^[A-Za-z_][A-Za-z0-9_]*=") | not; .[1:])
          | select(.[0] // "" | test("^[A-Za-z0-9_./+-]+$"))
          | if (.[0] | IN("git", "gh", "herdr", "claude", "docker", "kubectl", "npm", "pnpm", "yarn", "cargo",
                "go", "brew", "make", "just", "uv", "security", "aws", "gcloud", "terraform"))
              and (.[1] // "" | test("^[a-z][a-z0-9-]{0,24}$"))
            then .[:2] else .[:1] end | join(" ")]
        | group_by(.) | map({command: .[0], count: length})
        | sort_by([-.count, .command]) | .[:10]),
      compactions: ([.[] | select(.type == "system" and .subtype == "compact_boundary")] | length),
      user_turns: ([.[] | select(.type == "user" and (.isMeta | not) and (.isCompactSummary | not)
        and (((.message.content | arrays | map(select(.type? == "tool_result")) | length) // 0) == 0))] | length),
      started_at: ($times[0]),
      ended_at: ($times[-1]),
      subagent_tool_calls: $subagent_tool_calls
    }'
