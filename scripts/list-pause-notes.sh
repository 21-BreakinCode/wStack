#!/usr/bin/env bash
# Usage: list-pause-notes.sh <abs folder>
# Prints the unresumed session pause notes of that folder, newest first.
# A note is ~/.wstack/pauses/<folder name>-<YYYYMMDD-HHMMSS>.md with the line "- folder: <abs folder>".
set -euo pipefail

[ "$#" -eq 1 ] && [[ "$1" = /* ]] || { echo "usage: list-pause-notes.sh <abs folder>" >&2; exit 2; }
folder="$1"
pauses_dir="$HOME/.wstack/pauses"
[ -d "$pauses_dir" ] || exit 0

for note in "$pauses_dir"/*.md; do
  [ -f "$note" ] || continue
  name="$(basename "$note" .md)"
  [[ "$name" != *.resumed-* && "$name" =~ -[0-9]{8}-[0-9]{6}$ ]] || continue
  grep -qxF -- "- folder: $folder" "$note" || continue
  printf '%s\t%s\n' "${name: -15}" "$note"
done | sort -r | cut -f2
