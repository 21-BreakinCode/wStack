#!/usr/bin/env bash
# Usage: board.sh --vault <abs> --tasks-dir <rel>
# Prints one JSON object per line: every open task, then finished tasks whose workspace is still open.
# Sorted by group (needs you, stalled, stopped, working, paused, finished, other), then by task_id.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
source "$script_dir/lib/herdr.sh"
source "$script_dir/lib/transcripts.sh"
fail() { echo "board: $1" >&2; exit 1; }

vault="" tasks_dir=""
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || fail "missing value for $1"
  case "$1" in
    --vault) vault="$2" ;;
    --tasks-dir) tasks_dir="$2" ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done
[[ "$vault" = /* ]] || fail "--vault must be an absolute path"
[ -d "$vault/$tasks_dir" ] || exit 0

in_herdr=false
[ "${HERDR_ENV:-}" = 1 ] && in_herdr=true

section_lines() {  # <file> <heading>: the lines under "## <heading>", up to the next heading
  [ -f "$1" ] || return 0
  awk -v heading="## $2" '{ sub(/\r$/, "") } $0 == heading { on = 1; next } /^## / { on = 0 } on' "$1"
}

age_of() {  # <created_at>: m, h, or d since then, "" if unreadable
  local stamp seconds
  stamp="$(sed -e 's/Z$/+0000/' -e 's/:\([0-9][0-9]\)$/\1/' <<<"$1")"
  seconds="$(date -j -f %Y-%m-%dT%H:%M:%S%z "$stamp" +%s 2>/dev/null)" || return 0
  seconds=$(( $(date +%s) - seconds ))
  if [ "$seconds" -lt 3600 ]; then echo "$((seconds / 60))m"
  elif [ "$seconds" -lt 86400 ]; then echo "$((seconds / 3600))h"
  else echo "$((seconds / 86400))d"; fi
}

group_of() {  # <status> <herdr state>: the first group that matches
  case "$1:$2" in
    *:blocked|awaiting-approval:*|waiting-user:*|awaiting-deliver-approval:*|drafting:idle|drafting:done) echo "needs you" ;;
    executing:idle|executing:done|verifying:idle|verifying:done) echo stalled ;;
    paused:none) echo paused ;;
    *:none) echo stopped ;;
    *:working|*:unknown) echo working ;;
    paused:*) echo paused ;;
    *) echo other ;;
  esac
}

active_minutes="${WSTACK_BOARD_ACTIVE_MINUTES:-15}"
if ! [[ "$active_minutes" =~ ^[1-9][0-9]*$ ]]; then
  echo "board: WSTACK_BOARD_ACTIVE_MINUTES must be a positive integer, using 15" >&2
  active_minutes=15
fi

# jq definitions: clean cuts a text to one line of 60 characters, last_tool_of reads transcript lines.
# A Bash call shows only its description, never its command text, because a command can hold a secret.
transcript_jq_defs='
  def filled: strings | select(length > 0);
  def clean: gsub("[[:cntrl:][:space:]]+"; " ") | gsub("^ +| +$"; "") | .[:60];
  def last_tool_of:
    [.[] | fromjson? | select(type == "object" and .type == "assistant")
      | .timestamp as $at | .message.content | arrays | .[] | select(.type? == "tool_use")
      | {tool: .name, at: $at, input: ((.input | objects) // {})}] | last
    | if . == null then null else
        {tool, at, hint: (((.input.description | filled)
          // (.input.file_path | filled | split("/") | last)
          // (.input.pattern | filled | .[:40]) // "")
          | clean)}
      end;'

last_tool_of() {  # <transcript file>: {tool, hint, at} of the last tool_use in its last 200 lines, or null
  tail -n 200 "$1" | jq -Rsc "$transcript_jq_defs"' split("\n") | last_tool_of'
}

# Prints {last_tool, subagents} for the newest session id of a spec.
activity_json() {  # <spec file>
  local id main_file last_tool sub_dir sub_file modified_at now
  id="$(fm_get "$1" session_ids)"  # a JSON list such as ["id1","id2"]
  id="${id//[\[\]\" ]/}"; id="${id##*,}"
  if ! session_id_ok "$id"; then echo '{"last_tool":null,"subagents":[]}'; return 0; fi
  main_file="$(transcript_main_files "$id")"; main_file="${main_file%%$'\n'*}"
  last_tool=null
  [ -z "$main_file" ] || last_tool="$(last_tool_of "$main_file")"
  now="$(date +%s)"
  transcript_subagent_dirs "$id" | while IFS= read -r sub_dir; do
    find "$sub_dir" -name 'agent-*.jsonl' -mmin "-$active_minutes" -exec stat -f '%m %N' {} +
  done | while IFS=' ' read -r modified_at sub_file; do
    # One jq call per agent. A missing or non-JSON meta file makes --slurpfile fail, and that skips the agent.
    # A finished agent stops at the first select, before the transcript is read.
    tail -n 200 "$sub_file" | jq -Rsc --slurpfile meta "${sub_file%.jsonl}.meta.json" --argjson idle "$(( now - modified_at ))" \
      "$transcript_jq_defs"' . as $raw | $meta[0] | select(.finished != true)
      | {type: (.agentType // "" | clean), description: (.description // "" | clean), idle_seconds: $idle}
        + {last_tool: ($raw | split("\n") | last_tool_of)}' 2>/dev/null || true
  done | jq -sc --argjson last_tool "$last_tool" '{last_tool: $last_tool, subagents: .}'
}

board_now="$(date +%s)"

# One jq object per task. Add a row field here and nowhere else.
changes_of() {  # <dir>: "<n> files +<ins> -<del>" against the merge base with origin, or "-"
  local dir="$1" base_ref merge_base stat
  [ -d "$dir" ] || { echo -; return; }
  base_ref="$(git -C "$dir" rev-parse --abbrev-ref origin/HEAD 2>/dev/null)" || base_ref=origin/main
  merge_base="$(git -C "$dir" merge-base HEAD "$base_ref" 2>/dev/null)" || { echo -; return; }
  # diff-index gives the counts of git diff, but it never refreshes and rewrites the index of the worktree.
  stat="$(git -C "$dir" diff-index --shortstat "$merge_base" 2>/dev/null)" || { echo -; return; }
  local files=0 inserted=0 deleted=0
  [[ "$stat" =~ ([0-9]+)\ file ]] && files="${BASH_REMATCH[1]}"
  [[ "$stat" =~ ([0-9]+)\ insertion ]] && inserted="${BASH_REMATCH[1]}"
  [[ "$stat" =~ ([0-9]+)\ deletion ]] && deleted="${BASH_REMATCH[1]}"
  echo "$files files +$inserted -$deleted"
}

row_json() {  # <group> <task_id> <slug> <status> <herdr> <workspace_id> <folder>
  local spec="$7/spec.md"
  jq -nc --arg group "$1" --arg task_id "$2" --arg slug "$3" --arg status "$4" --arg herdr "$5" --arg workspace_id "$6" --arg folder "$7" \
    --arg goal "$(section_lines "$spec" Goal | awk 'NF { print; exit }')" \
    --arg last_step "$(section_lines "$7/run-log.md" Steps | awk 'NF { last = $0 } END { print last }')" \
    --arg age "$(age_of "$(fm_get "$spec" created_at)")" \
    --arg changes "$(changes_of "$(fm_get "$spec" workspace_cwd)")" \
    --argjson activity "$(activity_json "$spec")" \
    --argjson now "$board_now" \
    'def idle_minutes_of: try ((($now - (.at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) / 60) | floor) catch "-";
     # A running background subagent means the RD is not stalled.
     (if $group == "stalled" and ($activity.subagents | length) > 0 then "working" else $group end) as $group
     | {group: $group, task_id: $task_id, slug: $slug, status: $status,
      herdr: $herdr, workspace_id: $workspace_id, goal: $goal, last_step: $last_step, age: $age, changes: $changes, folder: $folder} + $activity
    + (if $group == "stalled" then {idle_minutes: ($activity.last_tool | if . == null then "-" else idle_minutes_of end)} else {} end)'
}

rows="$(
  while IFS=$'\t' read -r task_id status workspace_cwd_and_folder; do
    folder="${workspace_cwd_and_folder##*$'\t'}"  # read would merge the tabs of an empty workspace_cwd
    slug="${task_id:11}"
    herdr_state=n/a workspace_id=n/a
    if $in_herdr; then
      if agent_reply="$(herdr_cmd agent get "$slug" 2>&1)"; then
        herdr_state="$(json_field "$agent_reply" .result.agent.agent_status 2>/dev/null || echo unknown)"
        workspace_id="$(json_field "$agent_reply" .result.agent.workspace_id 2>/dev/null || echo n/a)"
      elif [[ "$agent_reply" == *agent_not_found* ]]; then herdr_state=none
      else herdr_state=unknown; fi
    fi
    row_json "$(group_of "$status" "$herdr_state")" "$task_id" "$slug" "$status" "$herdr_state" "$workspace_id" "$folder"
  done < <(bash "$script_dir/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir")

  if $in_herdr; then
    while IFS=$'\t' read -r workspace_id label; do
      for folder in "$vault/$tasks_dir"/????-??-??-"$label" "$vault/$tasks_dir"/_archive/*/????-??-??-"$label"; do
        [ -f "$folder/spec.md" ] || continue
        status="$(fm_get "$folder/spec.md" status)"
        case "$status" in (delivered|cancelled) ;; (*) continue ;; esac
        task_id="$(basename "$folder")"
        row_json finished "$task_id" "${task_id:11}" "$status" n/a "$workspace_id" "$folder"
      done
    done < <(herdr_cmd workspace list 2>/dev/null | jq -r '.result.workspaces[]? | [.workspace_id, .label] | @tsv' 2>/dev/null || true)
  fi
)"
[ -n "$rows" ] || exit 0
jq -sc '
  ["needs you", "stalled", "stopped", "working", "paused", "finished", "other"] as $order
  | sort_by([(.group as $group | $order | index($group)), .task_id]) | .[]' <<<"$rows"
