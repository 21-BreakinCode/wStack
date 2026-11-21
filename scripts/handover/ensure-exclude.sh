#!/usr/bin/env bash
set -euo pipefail
repo_dir="${1:?usage: ensure-exclude.sh <repo_dir>}"
git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree: $repo_dir" >&2; exit 2; }
repo_dir="$(git -C "$repo_dir" rev-parse --show-toplevel)"
if git -C "$repo_dir" check-ignore -q --no-index handover; then
  echo "already present"
  exit 0
fi
exclude_file="$(git -C "$repo_dir" rev-parse --path-format=absolute --git-path info/exclude)"
mkdir -p "$(dirname "$exclude_file")"
if [ -s "$exclude_file" ] && [ -n "$(tail -c1 "$exclude_file")" ]; then
  echo >> "$exclude_file"
fi
echo "/handover" >> "$exclude_file"
echo "added"
