#!/usr/bin/env bash
# contract-edit.sh <subcommand> ...  The only writer of contract files.
#   lock|unlock <contract_file>
#   apply <target_file> <patch_file> [--sections "A,B"]
#   delete-section <target_file> <heading>
#   pending-add <contract_file> <pr> <task_id> | pending-remove <contract_file> <pr>
#   set-verified <contract_file> <commit>
#   next-decision-id <decisions_dir>
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/frontmatter.sh"
lock_tries=10

usage() { echo "usage: contract-edit.sh <lock|unlock|apply|delete-section|pending-add|pending-remove|set-verified|next-decision-id> ..." >&2; exit 2; }
subcommand="${1:-}"; [ -n "$subcommand" ] || usage
shift

case "$subcommand" in
  lock)
    lock_dir="${1:?usage: contract-edit.sh lock <contract_file>}.lock"
    for ((try = 1; try <= lock_tries; try++)); do
      mkdir "$lock_dir" 2>/dev/null && exit 0
      [ "$try" -eq "$lock_tries" ] || sleep 1
    done
    echo "contract-edit.sh: lock is busy: $lock_dir. If no task runs, remove the lock folder." >&2
    exit 4 ;;

  unlock)
    rmdir "${1:?usage: contract-edit.sh unlock <contract_file>}.lock" 2>/dev/null || true ;;

  apply)
    target_file="${1:?usage: contract-edit.sh apply <target_file> <patch_file> [--sections \"A,B\"]}"
    patch_file="${2:?usage: contract-edit.sh apply <target_file> <patch_file> [--sections \"A,B\"]}"
    only_sections=""
    [ "${3:-}" != "--sections" ] || only_sections="${4:?--sections needs a value}"
    [ -s "$patch_file" ] || { echo "contract-edit.sh: patch is empty or missing: $patch_file" >&2; exit 2; }
    tmp_file="$(mktemp "$target_file.XXXXXX")"
    # Patch pass fills body[name]; target pass swaps matching sections; unmatched names append at the end.
    # Names print to stdout in patch order, after the target is written to tmp_file.
    applied="$(awk -v only="$only_sections" -v out="$tmp_file" '
      function trim(s) { sub(/[ \t]+$/, "", s); return s }
      function emit(name,   text) {
        text = body[name]; sub(/\n+$/, "\n", text)
        printf "%s", text > out
      }
      BEGIN { n = split(only, wanted_list, ","); for (i = 1; i <= n; i++) wanted[wanted_list[i]] = 1 }
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
        if (name in body) { emit(name); seen[name] = 1; skipping = 1; next }
      }
      skipping { next }
      { print > out }
      END {
        for (i = 1; i <= count; i++) {
          name = order[i]
          if (!(name in seen)) { print "" > out; emit(name) }
          print name
        }
      }
    ' "$patch_file" "$target_file")" || { rm -f "$tmp_file"; exit 2; }
    if [ -z "$applied" ]; then rm -f "$tmp_file"; echo "contract-edit.sh: patch holds no section to apply: $patch_file" >&2; exit 2; fi
    mv "$tmp_file" "$target_file"
    printf '%s\n' "$applied" ;;

  delete-section)
    target_file="${1:?usage: contract-edit.sh delete-section <target_file> <heading>}"
    heading="${2:?usage: contract-edit.sh delete-section <target_file> <heading>}"
    tmp_file="$(mktemp "$target_file.XXXXXX")"
    found="$(awk -v heading="$heading" -v out="$tmp_file" '
      /^## / { name = substr($0, 4); sub(/[ \t]+$/, "", name); skipping = (name == heading); if (skipping) found = 1 }
      !skipping { print > out }
      END { print found + 0 }
    ' "$target_file")"
    if [ "$found" != 1 ]; then rm -f "$tmp_file"; echo "contract-edit.sh: no section: $heading" >&2; exit 1; fi
    mv "$tmp_file" "$target_file" ;;

  pending-add)
    contract_file="${1:?usage: contract-edit.sh pending-add <contract_file> <pr> <task_id>}"
    pending_pr="${2:?pr}"; pending_task="${3:?task_id}"
    [[ "$pending_pr" =~ ^[0-9]+$ ]] || { echo "contract-edit.sh: pr is not an integer: $pending_pr" >&2; exit 2; }
    new_item="$(jq -cn --argjson pr "$pending_pr" --arg task "$pending_task" '{pr: $pr, task: $task}')"
    fm_append "$contract_file" pending "$new_item" ;;

  pending-remove)
    contract_file="${1:?usage: contract-edit.sh pending-remove <contract_file> <pr>}"
    pending_pr="${2:?pr}"
    [[ "$pending_pr" =~ ^[0-9]+$ ]] || { echo "contract-edit.sh: pr is not an integer: $pending_pr" >&2; exit 2; }
    current="$(fm_get "$contract_file" pending)"
    remaining="$(jq -c --argjson pr "$pending_pr" 'map(select(.pr != $pr))' <<<"${current:-[]}")"
    fm_set "$contract_file" pending "$remaining" ;;

  set-verified)
    contract_file="${1:?usage: contract-edit.sh set-verified <contract_file> <commit>}"
    fm_set "$contract_file" verified_commit "${2:?commit}"
    fm_set "$contract_file" verified_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ;;

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
