#!/usr/bin/env bash
# Usage: archive-candidates.sh --vault <abs> --tasks-dir <rel>
# Prints the ids of top-level tasks that are delivered or cancelled and have a retro_read value.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$script_dir/lib/frontmatter.sh"

vault="" tasks_dir=""
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || { echo "archive-candidates: missing value for $1" >&2; exit 1; }
  case "$1" in
    --vault) vault="$2" ;;
    --tasks-dir) tasks_dir="$2" ;;
    *) echo "archive-candidates: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift 2
done
[ -d "$vault/$tasks_dir" ] || exit 0

for folder in "$vault/$tasks_dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*/; do
  folder="${folder%/}"
  [ -f "$folder/spec.md" ] || continue
  case "$(fm_get "$folder/spec.md" status)" in delivered|cancelled) ;; *) continue ;; esac
  [ -n "$(fm_get "$folder/spec.md" retro_read)" ] || continue
  basename "$folder"
done | sort
