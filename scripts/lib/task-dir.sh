#!/usr/bin/env bash
# Task folder lookup. Source this file.
# A task folder is <vault>/<tasks_dir>/<task_id>/, or <vault>/<tasks_dir>/_archive/<YYYY-Www>/<task_id>/ after the weekly retro archives it.
set -euo pipefail

task_dir_of() {  # <vault> <tasks_dir> <task_id>: print the folder (top level first, then the archive) and return 0, or print nothing and return 1
  local folder
  for folder in "$1/$2/$3" "$1/$2"/_archive/*/"$3"; do
    [ -d "$folder" ] && { printf '%s\n' "$folder"; return 0; }
  done
  return 1
}
