#!/usr/bin/env bash
# Task folder lookup. Source this file.
# A task folder is <vault>/<tasks_dir>/<task_id>/, or <vault>/<tasks_dir>/_archive/<YYYY-Www>/<task_id>/ after the weekly retro archives it.
set -euo pipefail

task_dir_of() {  # <vault> <tasks_dir> <task_id>: print the folder (top level first, then the archive) and return 0, or print nothing and return 1
  [ -d "$1/$2/$3" ] && { printf '%s\n' "$1/$2/$3"; return 0; }
  # In zsh a glob with no match is a fatal error. The subshell keeps it from ending the caller's shell.
  ( for folder in "$1/$2"/_archive/*/"$3"; do
      [ -d "$folder" ] && { printf '%s\n' "$folder"; exit 0; }
    done
    exit 1 ) 2>/dev/null
}
