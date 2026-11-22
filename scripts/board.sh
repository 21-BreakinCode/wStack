#!/usr/bin/env bash
# Usage: board.sh --vault <abs> --tasks-dir <rel>
# Prints one JSON object per line: every open task, then finished tasks whose workspace is still open.
# Sorted by group (needs you, stopped, working, paused, finished, other), then by task_id.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
source "$script_dir/lib/herdr.sh"
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
  awk -v heading="## $2" '$0 == heading { on = 1; next } /^## / { on = 0 } on' "$1"
}

age_of() {  # <created_at>: m, h, or d since then, "" if unreadable
  local stamp seconds
  stamp="$(sed 's/:\([0-9][0-9]\)$/\1/' <<<"$1")"
  seconds="$(date -j -f %Y-%m-%dT%H:%M:%S%z "$stamp" +%s 2>/dev/null)" || return 0
  seconds=$(( $(date +%s) - seconds ))
  if [ "$seconds" -lt 3600 ]; then echo "$((seconds / 60))m"
  elif [ "$seconds" -lt 86400 ]; then echo "$((seconds / 3600))h"
  else echo "$((seconds / 86400))d"; fi
}

group_of() {  # <status> <herdr state>: the first group that matches
  case "$1:$2" in
    *:blocked|awaiting-approval:*|waiting-user:*|awaiting-deliver-approval:*|drafting:idle|drafting:done) echo "needs you" ;;
    paused:none) echo paused ;;
    *:none) echo stopped ;;
    *:working|*:unknown) echo working ;;
    paused:*) echo paused ;;
    *) echo other ;;
  esac
}

# One jq object per task. Add a row field here and nowhere else.
row_json() {  # <group> <task_id> <status> <herdr> <workspace_id> <folder>
  local spec="$6/spec.md"
  jq -nc --arg group "$1" --arg task_id "$2" --arg status "$3" --arg herdr "$4" --arg workspace_id "$5" --arg folder "$6" \
    --arg goal "$(section_lines "$spec" Goal | awk 'NF { print; exit }')" \
    --arg last_step "$(section_lines "$6/run-log.md" Steps | awk 'NF { last = $0 } END { print last }')" \
    --arg age "$(age_of "$(fm_get "$spec" created_at)")" \
    '{group: $group, task_id: $task_id, slug: ($task_id | sub("^[0-9]{4}-[0-9]{2}-[0-9]{2}-"; "")), status: $status,
      herdr: $herdr, workspace_id: $workspace_id, goal: $goal, last_step: $last_step, age: $age, folder: $folder}'
}

rows="$(
  while IFS=$'\t' read -r task_id status workspace_cwd_and_folder; do
    folder="${workspace_cwd_and_folder##*$'\t'}"  # read would merge the tabs of an empty workspace_cwd
    slug="${task_id#????-??-??-}"
    herdr_state=n/a workspace_id=n/a
    if $in_herdr; then
      if agent_reply="$(herdr_cmd agent get "$slug" 2>&1)"; then
        herdr_state="$(json_field "$agent_reply" .result.agent.agent_status 2>/dev/null || echo unknown)"
        workspace_id="$(json_field "$agent_reply" .result.agent.workspace_id 2>/dev/null || echo n/a)"
      elif [[ "$agent_reply" == *agent_not_found* ]]; then herdr_state=none
      else herdr_state=unknown; fi
    fi
    row_json "$(group_of "$status" "$herdr_state")" "$task_id" "$status" "$herdr_state" "$workspace_id" "$folder"
  done < <(bash "$script_dir/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir")

  if $in_herdr; then
    workspaces="$(herdr_cmd workspace list 2>/dev/null || true)"
    cutoff="$(date -j -v-13d +%Y-%m-%d)"  # today counts as day 1
    for folder in "$vault/$tasks_dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*/; do
      [ -f "$folder/spec.md" ] || continue
      folder="${folder%/}"
      task_id="$(basename "$folder")"
      status="$(fm_get "$folder/spec.md" status)"
      case "$status" in delivered|cancelled) ;; *) continue ;; esac
      [[ "${task_id:0:10}" > "$cutoff" || "${task_id:0:10}" = "$cutoff" ]] || continue
      workspace_id="$(jq -r --arg slug "${task_id#????-??-??-}" '[.result.workspaces[]? | select(.label == $slug) | .workspace_id] | first // empty' <<<"$workspaces" 2>/dev/null || true)"
      [ -n "$workspace_id" ] || continue
      row_json finished "$task_id" "$status" n/a "$workspace_id" "$folder"
    done
  fi
)"
[ -n "$rows" ] || exit 0
jq -sc '
  ["needs you", "stopped", "working", "paused", "finished", "other"] as $order
  | sort_by([(.group as $group | $order | index($group)), .task_id]) | .[]' <<<"$rows"
