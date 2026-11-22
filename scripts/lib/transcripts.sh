#!/usr/bin/env bash
# Transcript lookup by session id. Source this file.
# Transcripts live in $HOME/.claude/projects/<encoded cwd>/<id>.jsonl, subagents in <id>/subagents/*.jsonl.
set -euo pipefail

session_id_ok() {  # <id>: succeed when the id is a lowercase UUID
  [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

transcript_main_files() {  # <id>...: print each existing main transcript, one per line
  local id file
  for id in "$@"; do
    for file in "$HOME"/.claude/projects/*/"$id".jsonl; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done
  done
  return 0
}

transcript_subagent_files() {  # <id>...: print each existing subagent transcript, one per line
  local id file
  for id in "$@"; do
    for file in "$HOME"/.claude/projects/*/"$id"/subagents/*.jsonl; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done
  done
  return 0
}

transcript_subagent_dirs() {  # <id>...: print each existing subagents folder, one per line
  local id dir
  for id in "$@"; do
    for dir in "$HOME"/.claude/projects/*/"$id"/subagents; do
      [ -d "$dir" ] && printf '%s\n' "$dir"
    done
  done
  return 0
}
