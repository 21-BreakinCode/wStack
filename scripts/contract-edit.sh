#!/usr/bin/env bash
# contract-edit.sh <subcommand> ...  The only writer of contract files.
#   lock|unlock <contract_file>
#   apply <target_file> <patch_file> [--sections "A,B"] [--section "A, with comma"]...
#   delete-section <target_file> <heading>
#   pending-add <contract_file> <pr> <task_id> | pending-remove <contract_file> <pr>
#   set-verified <contract_file> <commit>
#   next-decision-id <decisions_dir>
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/frontmatter.sh"
lock_tries=10

usage() { echo "usage: contract-edit.sh <lock|unlock|apply|delete-section|pending-add|pending-remove|set-verified|next-decision-id> ..." >&2; exit 2; }
require_pr() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "contract-edit.sh: pr is not an integer: $1" >&2; exit 2; }; }
pending_array() {  # <contract_file>: print the pending list as one-line JSON, exit 2 when it is not an array
  local current
  current="$(fm_get "$1" pending)"
  jq -ce 'select(type == "array")' <<<"${current:-[]}" 2>/dev/null || { echo "contract-edit.sh: pending is not a JSON array: $1" >&2; exit 2; }
}
subcommand="${1:-}"; [ -n "$subcommand" ] || usage
shift

case "$subcommand" in
  lock)
    lock_dir="${1:?usage: contract-edit.sh lock <contract_file>}.lock"
    [ -d "$(dirname "$lock_dir")" ] || { echo "contract-edit.sh: folder missing: $(dirname "$lock_dir")" >&2; exit 2; }
    for ((try = 1; try <= lock_tries; try++)); do
      mkdir "$lock_dir" 2>/dev/null && exit 0
      [ "$try" -eq "$lock_tries" ] || sleep 1
    done
    echo "contract-edit.sh: lock is busy: $lock_dir. If no task runs, remove the lock folder." >&2
    exit 4 ;;

  unlock)
    lock_dir="${1:?usage: contract-edit.sh unlock <contract_file>}.lock"
    [ -e "$lock_dir" ] || exit 0
    rmdir "$lock_dir" || { echo "contract-edit.sh: cannot remove the lock folder: $lock_dir" >&2; exit 1; } ;;

  apply)
    target_file="${1:?usage: contract-edit.sh apply <target_file> <patch_file> [--sections \"A,B\"] [--section \"A\"]...}"
    patch_file="${2:?usage: contract-edit.sh apply <target_file> <patch_file> [--sections \"A,B\"] [--section \"A\"]...}"
    shift 2
    only_sections=""   # one name per line
    while [ $# -gt 0 ]; do
      case "$1" in
        --sections) only_sections="$only_sections$(printf '%s' "${2:?--sections needs a value}" | tr ',' '\n')"$'\n' ;;
        --section) only_sections="$only_sections${2:?--section needs a value}"$'\n' ;;
        *) usage ;;
      esac
      shift 2
    done
    [ -s "$patch_file" ] || { echo "contract-edit.sh: patch is empty or missing: $patch_file" >&2; exit 2; }
    tmp_file="$(mktemp "$target_file.XXXXXX")"
    # Patch pass fills body[name]; target pass swaps matching sections; unmatched names append at the end.
    # Names print to stdout in patch order, after the target is written to tmp_file.
    applied="$(ONLY_SECTIONS="$only_sections" awk -v out="$tmp_file" '
      { sub(/\r$/, "") }   # LF out, like fm_set
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      function emit(name,   text) {
        text = body[name]; sub(/\n+$/, "\n", text)
        printf "%s", text > out
      }
      BEGIN {
        only = ENVIRON["ONLY_SECTIONS"]
        n = split(only, wanted_list, "\n")
        for (i = 1; i <= n; i++) if (trim(wanted_list[i]) != "") wanted[trim(wanted_list[i])] = 1
      }
      NR == FNR {
        if ($0 ~ /^## /) {
          current = trim(substr($0, 4)); keep = (current != "Remove from plan") && (only == "" || (current in wanted))
          if (keep && !(current in body)) order[++count] = current
          if (keep) body[current] = ""
          else current = ""
        }
        if (current != "") body[current] = body[current] $0 "\n"
        next
      }
      /^## / {
        if (skipping) { print "" > out; skipping = 0 }
        name = trim(substr($0, 4))
        if (name in body) { while (held > 0) { print "" > out; held-- }; emit(name); seen[name] = 1; skipping = 1; next }
      }
      skipping { next }
      /^$/ { held++; next }
      { while (held > 0) { print "" > out; held-- }; print > out }
      END {
        held = 0
        for (i = 1; i <= count; i++) {
          name = order[i]
          if (!(name in seen)) {
            print "" > out; emit(name)
            print "contract-edit.sh: warning: no section named \"" name "\" in the target, so it was added at the end" > "/dev/stderr"
          }
          print name
        }
      }
    ' "$patch_file" "$target_file")" || { rm -f "$tmp_file"; exit 2; }
    if [ -z "$applied" ]; then rm -f "$tmp_file"; echo "contract-edit.sh: patch holds no section to apply: $patch_file" >&2; exit 2; fi
    fm_replace "$tmp_file" "$target_file"
    printf '%s\n' "$applied" ;;

  delete-section)
    target_file="${1:?usage: contract-edit.sh delete-section <target_file> <heading>}"
    heading="${2:?usage: contract-edit.sh delete-section <target_file> <heading>}"
    tmp_file="$(mktemp "$target_file.XXXXXX")" || exit 2  # exit 1 means only "no section"
    found="$(DELETE_HEADING="$heading" awk -v out="$tmp_file" '
      { sub(/\r$/, "") }
      /^## / { name = substr($0, 4); sub(/[ \t]+$/, "", name); skipping = (name == ENVIRON["DELETE_HEADING"]); if (skipping) found = 1 }
      !skipping { print > out }
      END { print found + 0 }
    ' "$target_file")" || { rm -f "$tmp_file"; exit 2; }
    if [ "$found" != 1 ]; then rm -f "$tmp_file"; echo "contract-edit.sh: no section: $heading" >&2; exit 1; fi
    fm_replace "$tmp_file" "$target_file" || { rm -f "$tmp_file"; echo "contract-edit.sh: could not write: $target_file" >&2; exit 2; } ;;

  pending-add)
    contract_file="${1:?usage: contract-edit.sh pending-add <contract_file> <pr> <task_id>}"
    pending_pr="${2:?pr}"; pending_task="${3:?task_id}"
    require_pr "$pending_pr"
    already_listed="$(pending_array "$contract_file" | jq --argjson pr "$pending_pr" 'any(.[]; .pr == $pr)')"
    [ "$already_listed" = false ] || exit 0
    new_item="$(jq -cn --argjson pr "$pending_pr" --arg task "$pending_task" '{pr: $pr, task: $task}')"
    fm_append "$contract_file" pending "$new_item" ;;

  pending-remove)
    contract_file="${1:?usage: contract-edit.sh pending-remove <contract_file> <pr>}"
    pending_pr="${2:?pr}"
    require_pr "$pending_pr"
    remaining="$(pending_array "$contract_file" | jq -c --argjson pr "$pending_pr" 'map(select(.pr != $pr))')"
    fm_set "$contract_file" pending "$remaining" ;;

  set-verified)
    contract_file="${1:?usage: contract-edit.sh set-verified <contract_file> <commit>}"
    verified_commit="${2:?commit}"
    staged_file="$(mktemp "$contract_file.XXXXXX")"
    { cp "$contract_file" "$staged_file" && chmod 600 "$staged_file" \
      && fm_set "$staged_file" verified_commit "$verified_commit" \
      && fm_set "$staged_file" verified_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      && fm_replace "$staged_file" "$contract_file"; } || { rm -f "$staged_file"; exit 2; } ;;

  next-decision-id)
    decisions_dir="${1:?usage: contract-edit.sh next-decision-id <decisions_dir>}"
    highest=0
    for decision_file in "$decisions_dir"/[0-9][0-9][0-9][0-9]-*.md; do
      [ -e "$decision_file" ] || continue
      decision_id="$(basename "$decision_file")"; decision_id=$((10#${decision_id:0:4}))
      [ "$decision_id" -le "$highest" ] || highest="$decision_id"
    done
    printf '%04d\n' $((highest + 1)) ;;

  *) usage ;;
esac
