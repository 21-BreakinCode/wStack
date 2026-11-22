#!/usr/bin/env bash
# Usage: new-task-folder.sh --vault <abs> --tasks-dir <rel> --slug <slug>
#          [--date YYYY-MM-DD] [--work-type code|ops|thinking|blog|video|contract] [--repo owner/repo] [--mobile]
#          [--idea <text>]   (written under ## Goal in spec.md as one line)
# Prints the absolute task folder path as the last stdout line.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/herdr.sh"
templates_dir="$script_dir/../templates"
fail() { echo "new-task-folder: $1" >&2; exit 1; }

vault="" tasks_dir="" slug="" date_stamp="$(date +%Y-%m-%d)" work_type=code repo="" idea="" mobile=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mobile) mobile=true; shift; continue ;;
    --vault|--tasks-dir|--slug|--date|--work-type|--repo|--idea) [ "$#" -ge 2 ] || fail "missing value for $1" ;;
    *) fail "unknown argument: $1" ;;
  esac
  case "$1" in
    --vault) vault="$2" ;;
    --tasks-dir) tasks_dir="$2" ;;
    --slug) slug="$2" ;;
    --date) date_stamp="$2" ;;
    --work-type) work_type="$2" ;;
    --repo) repo="$2" ;;
    --idea) idea="$2" ;;
  esac
  shift 2
done

[[ "$slug" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail "bad slug: $slug"
[[ "$date_stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "bad date: $date_stamp"
case "$work_type" in code|ops|thinking|blog|video|contract) ;; *) fail "bad work type: $work_type" ;; esac
[ -z "$repo" ] || [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || fail "bad repo: $repo"
[[ "$vault" = /* ]] && [ -d "$vault" ] || fail "vault is not an absolute existing directory: $vault"
[ -n "$tasks_dir" ] && [[ "$tasks_dir" != /* ]] && [[ "/$tasks_dir/" != *"/../"* ]] || fail "bad tasks dir: $tasks_dir"

tasks_root="$vault/$tasks_dir"
mkdir -p "$tasks_root"

candidate_slug="$slug"
attempt=1
# A slug is taken by a folder of any date or by a live herdr agent: the slug is also the agent name and the branch name.
until [ -z "$(find "$tasks_root" -maxdepth 1 -name "????-??-??-$candidate_slug" -print -quit)" ] \
  && { [ "${HERDR_ENV:-}" != 1 ] || ! herdr_cmd agent get "$candidate_slug" >/dev/null 2>&1; } \
  && mkdir "$tasks_root/$date_stamp-$candidate_slug" 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -le 999 ] || fail "too many folders for slug: $slug"
  suffix="-$attempt"
  trimmed="${slug:0:$((32 - ${#suffix}))}"
  while [ "${trimmed%-}" != "$trimmed" ]; do trimmed="${trimmed%-}"; done
  candidate_slug="$trimmed$suffix"
done
task_id="$date_stamp-$candidate_slug"
folder="$tasks_root/$task_id"

created_at="$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\([0-9][0-9]\)$/:\1/')"
for name in spec run-log review report; do
  sed -e "s|{{task_id}}|$task_id|g" -e "s|{{work_type}}|$work_type|g" -e "s|{{repo}}|$repo|g" \
      -e "s|{{mobile}}|$mobile|g" -e "s|{{created_at}}|$created_at|g" \
      "$templates_dir/$name.md" >"$folder/$name.md"
done
if [ -n "$idea" ]; then
  # ENVIRON keeps backslashes and & literal, unlike sed replacement or awk -v
  IDEA_TEXT="${idea//$'\n'/ }" awk '{ print } /^## Goal$/ && !done { print ""; print "Rough idea from launch: " ENVIRON["IDEA_TEXT"]; done = 1 }' \
    "$folder/spec.md" >"$folder/spec.md.tmp"
  mv "$folder/spec.md.tmp" "$folder/spec.md"
fi
echo "$folder"
