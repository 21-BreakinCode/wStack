#!/usr/bin/env bash
# Usage: collect-week.sh --vault <abs> --tasks-dir <rel> [--today YYYY-MM-DD]
# Prints a JSON array, one object per dated task folder whose spec has no retro_read mark. _archive/ is never read.
# Each object holds frontmatter, state (finished or open), age_days, facts_file, retro-note flag, and transcript stats.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
source "$script_dir/lib/transcripts.sh"
fail() { echo "collect-week: $1" >&2; exit 1; }

vault="" tasks_dir="" today="$(date +%Y-%m-%d)"
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || fail "missing value for $1"
  case "$1" in
    --vault) vault="$2" ;;
    --tasks-dir) tasks_dir="$2" ;;
    --today) today="$2" ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done

[[ "$vault" = /* ]] && [ -d "$vault/$tasks_dir" ] || fail "tasks folder not found: $vault/$tasks_dir"
[[ "$today" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "bad today: $today"
# Midnight is explicit: date -j fills a missing time of day from the clock, which can tick between two calls.
day_epoch() { TZ=UTC date -j -f '%Y-%m-%d %H:%M:%S' "$1 00:00:00" +%s; }
today_epoch="$(day_epoch "$today")"

frontmatter_or_empty() {  # <file>
  if [ -f "$1" ]; then fm_to_json "$1"; else echo '{}'; fi
}

for folder in "$vault/$tasks_dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*/; do
  [ -d "$folder" ] || continue
  folder="${folder%/}"
  task_id="$(basename "$folder")"
  task_date="${task_id:0:10}"
  [ -z "$(fm_get "$folder/spec.md" retro_read 2>/dev/null)" ] || continue
  state=open
  case "$(fm_get "$folder/spec.md" status 2>/dev/null)" in delivered|cancelled) state=finished ;; esac
  age_days="$(( (today_epoch - $(day_epoch "$task_date")) / 86400 ))"
  facts_file=null
  contract_file="$(fm_get "$folder/contract-brief.md" contract_file 2>/dev/null || true)"
  contract_stem="${contract_file%.contract.yaml}"
  contract_stem="${contract_stem%.md}"  # task folders from before the YAML contract name <app>.md
  [ -z "$contract_file" ] || facts_file="$(jq -n --arg file "$contract_stem.facts.md" '$file')"
  has_retro_note=false
  [ -f "$folder/retro-note.md" ] && has_retro_note=true
  transcript_stats=null
  session_ids=()
  while IFS= read -r session_id; do
    session_id_ok "$session_id" && session_ids+=("$session_id")
  done < <(frontmatter_or_empty "$folder/spec.md" | jq -r '.session_ids[]? // empty')
  if [ "${#session_ids[@]}" -gt 0 ]; then
    transcript_stats="$(bash "$script_dir/transcript-stats.sh" "${session_ids[@]}")" || {
      echo "collect-week: transcript stats failed for $task_id" >&2
      transcript_stats=null
    }
  fi
  jq -n --arg task_id "$task_id" --arg folder "$folder" --arg state "$state" --argjson age_days "$age_days" --argjson facts_file "$facts_file" \
    --argjson spec "$(frontmatter_or_empty "$folder/spec.md")" \
    --argjson run_log "$(frontmatter_or_empty "$folder/run-log.md")" \
    --argjson review "$(frontmatter_or_empty "$folder/review.md")" \
    --argjson report "$(frontmatter_or_empty "$folder/report.md")" \
    --argjson has_retro_note "$has_retro_note" \
    --argjson transcript_stats "$transcript_stats" \
    '{task_id: $task_id, folder: $folder, spec: $spec, run_log: $run_log, review: $review, report: $report,
      state: $state, age_days: $age_days, facts_file: $facts_file,
      has_retro_note: $has_retro_note, transcript_stats: $transcript_stats}'
done | jq -s '.'
