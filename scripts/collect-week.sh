#!/usr/bin/env bash
# Usage: collect-week.sh --vault <abs> --tasks-dir <rel> [--days 7] [--today YYYY-MM-DD]
# Prints a JSON array, one object per task folder dated today or in the --days - 1 days before (frontmatter only).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"
fail() { echo "collect-week: $1" >&2; exit 1; }

vault="" tasks_dir="" days=7 today="$(date +%Y-%m-%d)"
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || fail "missing value for $1"
  case "$1" in
    --vault) vault="$2" ;;
    --tasks-dir) tasks_dir="$2" ;;
    --days) days="$2" ;;
    --today) today="$2" ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done

[[ "$vault" = /* ]] && [ -d "$vault/$tasks_dir" ] || fail "tasks folder not found: $vault/$tasks_dir"
[[ "$days" =~ ^[1-9][0-9]*$ ]] || fail "bad days: $days"
[[ "$today" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "bad today: $today"
cutoff="$(date -j -v-"$((days - 1))"d -f %Y-%m-%d "$today" +%Y-%m-%d)"  # today counts as day 1

frontmatter_or_empty() {  # <file>
  if [ -f "$1" ]; then fm_to_json "$1"; else echo '{}'; fi
}

for folder in "$vault/$tasks_dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*/; do
  [ -d "$folder" ] || continue
  folder="${folder%/}"
  task_id="$(basename "$folder")"
  task_date="${task_id:0:10}"
  { [[ "$task_date" > "$cutoff" || "$task_date" = "$cutoff" ]] && [[ "$task_date" < "$today" || "$task_date" = "$today" ]]; } || continue
  jq -n --arg task_id "$task_id" --arg folder "$folder" \
    --argjson spec "$(frontmatter_or_empty "$folder/spec.md")" \
    --argjson run_log "$(frontmatter_or_empty "$folder/run-log.md")" \
    --argjson review "$(frontmatter_or_empty "$folder/review.md")" \
    --argjson report "$(frontmatter_or_empty "$folder/report.md")" \
    '{task_id: $task_id, folder: $folder, spec: $spec, run_log: $run_log, review: $review, report: $report}'
done | jq -s '.'
