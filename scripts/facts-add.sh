#!/usr/bin/env bash
# facts-add.sh <facts_file> <fact|not> <YYYY-MM-DD> <evidence> <text>
# Adds one entry to the project facts file next to the contract. Exit 0 written, 1 bad input, 2 lock busy or folder missing.
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -eq 5 ] || { echo "usage: facts-add.sh <facts_file> <fact|not> <YYYY-MM-DD> <evidence> <text>" >&2; exit 1; }
facts_file="$1"; kind="$2"; entry_date="$3"; evidence="$4"; text="$5"

case "$kind" in fact|not) ;; *) echo "facts-add.sh: kind must be fact or not: $kind" >&2; exit 1 ;; esac
[[ "$entry_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "facts-add.sh: bad date: $entry_date" >&2; exit 1; }
[ -n "$text" ] || { echo "facts-add.sh: text is empty" >&2; exit 1; }
for value in "$evidence" "$text"; do
  case "$value" in *$'\n'*) echo "facts-add.sh: a value holds a newline" >&2; exit 1 ;; esac
done

contract_file="${facts_file%.facts.md}.md"
service="$(basename "$facts_file" .facts.md)"
lock_status=0
bash "$plugin_root/scripts/contract-edit.sh" lock "$contract_file" || lock_status=$?
[ "$lock_status" -eq 0 ] || exit 2
trap 'bash "$plugin_root/scripts/contract-edit.sh" unlock "$contract_file"' EXIT

if [ ! -f "$facts_file" ]; then
  sed "s/{{service}}/$service/g" "$plugin_root/templates/facts.md" > "$facts_file"
fi

if [ "$kind" = fact ]; then
  highest="$(sed -n 's/^- F\([0-9][0-9]*\) .*/\1/p' "$facts_file" | sort -n | tail -n 1)"
  entry_line="- F$(( ${highest:-0} + 1 )) $text"
  detail_line="  Confirmed $entry_date. Evidence: $evidence"
  section="## Facts"
else
  entry_line="- $text"
  detail_line="  Rejected $entry_date."
  section="## Not facts"
fi

# Insert the two lines after the last non-blank line of the section, so blank lines stay before the next heading.
tmp_file="$(mktemp "$facts_file.XXXXXX")"
ENTRY="$entry_line" DETAIL="$detail_line" SECTION="$section" awk '
  function flush() { if (inside && !done) { print ENVIRON["ENTRY"]; print ENVIRON["DETAIL"]; printf "%s", held; done = 1 } held = "" }
  /^## / { flush(); inside = ($0 == ENVIRON["SECTION"]) }
  inside && /^[ \t]*$/ { held = held $0 "\n"; next }
  { printf "%s", held; held = ""; print }
  END { flush() }
' "$facts_file" > "$tmp_file"
mv "$tmp_file" "$facts_file"
printf '%s\n' "$entry_line"
