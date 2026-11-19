#!/usr/bin/env bash
# Usage: list-open-tasks.sh --vault <abs> --tasks-dir <rel>
# Prints task_id<TAB>status<TAB>workspace_cwd<TAB>folder for tasks not delivered or cancelled.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"

vault="" tasks_dir=""
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || { echo "list-open-tasks: missing value for $1" >&2; exit 1; }
  case "$1" in
    --vault) vault="$2" ;;
    --tasks-dir) tasks_dir="$2" ;;
    *) echo "list-open-tasks: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift 2
done
[ -d "$vault/$tasks_dir" ] || exit 0

for folder in "$vault/$tasks_dir"/*/; do
  folder="${folder%/}"
  [ -f "$folder/spec.md" ] || continue
  status="$(fm_get "$folder/spec.md" status)"
  case "$status" in delivered|cancelled) continue ;; esac
  printf '%s\t%s\t%s\t%s\n' "$(fm_get "$folder/spec.md" task_id)" "$status" "$(fm_get "$folder/spec.md" workspace_cwd)" "$folder"
done | sort
