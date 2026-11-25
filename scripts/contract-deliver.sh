#!/usr/bin/env bash
# contract-deliver.sh write|undo|rehearse <task_dir> <contract_file> <task_id>
# Deliver "Contract files": copy <task_dir>/contract.draft.yaml and decisions.draft/* into the contract folder.
#   write     Check decision ids, take the lock, move the old root files to _archive/<task_id>/ (once, marker
#             .archived), copy the drafts, run set-verified (it renders). Safe to run again after a failure.
#             Prints one line per file: new:, replaced: (old copy: ...), moved: ... -> ..., unchanged:.
#             Exit 0 done, 4 lock busy, 1 a decision id clash or a failed step.
#   undo      Delete the contract, the note, the HTML page, and the copied decisions; move the archive back.
#             A restored old contract is not rendered again: undo prints "rebuild the page: <command>". Exit 0 or 1.
#   rehearse  Run write and undo on copies in a temp folder with a temp HOME, then diff -r against a clean copy.
#             Prints the diff. Exit 0 empty diff, 1 a diff or a failed run.
set -euo pipefail

usage_line="usage: contract-deliver.sh write|undo|rehearse <task_dir> <contract_file> <task_id>"
[ $# -eq 4 ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] || { echo "$usage_line" >&2; exit 1; }
action="$1"; task_dir="$2"; contract_file="$3"; task_id="$4"
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "contract-deliver.sh: $1" >&2; exit 1; }
[[ "$task_id" =~ ^[A-Za-z0-9._-]+$ ]] || fail "bad task_id: $task_id"
draft_file="$task_dir/contract.draft.yaml"
[ -f "$draft_file" ] || fail "no draft: $draft_file"
app_name="$(yq -r '.app_name // ""' "$draft_file")" || fail "cannot read YAML: $draft_file"
[[ "$app_name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "bad or missing app_name in $draft_file"
contract_folder="$(dirname "$contract_file")"
contract_name="$(basename "$contract_file")"
note_name="$app_name.md"
archive_dir="$contract_folder/_archive/$task_id"
copied_list="$task_dir/decisions.copied.txt"

print_written() {  # <root file name>
  if [ -e "$archive_dir/$1" ]; then echo "replaced: $contract_folder/$1 (old copy: $archive_dir/$1)"
  else echo "new: $contract_folder/$1"; fi
}

case "$action" in
  write)
    verified_commit="$(yq -r '.verified_commit // ""' "$draft_file")"
    [ -n "$verified_commit" ] || fail "contract.draft.yaml has no verified_commit"
    bash "$scripts/contract-validate.sh" "$draft_file" || fail "the draft fails contract-validate.sh, so nothing changed"
    mkdir -p "$contract_folder" || fail "cannot create $contract_folder"
    bash "$scripts/contract-edit.sh" lock "$contract_file" || { [ $? = 4 ] && exit 4; exit 1; }
    trap 'bash "$scripts/contract-edit.sh" unlock "$contract_file"' EXIT
    for draft_decision in "$task_dir/decisions.draft"/*; do
      [ -e "$draft_decision" ] || continue
      draft_name="$(basename "$draft_decision")"
      for same_id in "$contract_folder/decisions/${draft_name%%-*}"-*; do
        [ -e "$same_id" ] || continue
        # A file this task copied in an earlier run is not a clash.
        if [ "$(basename "$same_id")" = "$draft_name" ] && grep -qsxF "$draft_name" "$copied_list"; then continue; fi
        fail "decision id ${draft_name%%-*} already exists in decisions/: $(basename "$same_id")"
      done
    done
    mkdir -p "$archive_dir"
    if [ ! -e "$archive_dir/.archived" ]; then
      for old_file in "$contract_folder"/*; do  # the glob skips dot files, so they stay
        case "$(basename "$old_file")" in handover|decisions|_archive|*.lock|*.facts.md) continue ;; esac
        [ ! -e "$archive_dir/$(basename "$old_file")" ] || continue
        mv "$old_file" "$archive_dir/"
      done
      touch "$archive_dir/.archived"
    fi
    cp "$draft_file" "$contract_file"
    for draft_decision in "$task_dir/decisions.draft"/*; do
      [ -e "$draft_decision" ] || continue
      grep -qsxF "$(basename "$draft_decision")" "$copied_list" || basename "$draft_decision" >>"$copied_list"
      mkdir -p "$contract_folder/decisions"
      cp "$draft_decision" "$contract_folder/decisions/"
    done
    bash "$scripts/contract-edit.sh" set-verified "$contract_file" "$verified_commit" || fail "set-verified failed"
    print_written "$contract_name"
    [ ! -e "$contract_folder/$note_name" ] || print_written "$note_name"
    for draft_decision in "$task_dir/decisions.draft"/*; do
      [ -e "$draft_decision" ] || continue
      echo "new: $contract_folder/decisions/$(basename "$draft_decision")"
    done
    for archived in "$archive_dir"/*; do
      [ -e "$archived" ] || continue
      archived_name="$(basename "$archived")"
      case "$archived_name" in "$contract_name"|"$note_name") [ ! -e "$contract_folder/$archived_name" ] || continue ;; esac
      echo "moved: $contract_folder/$archived_name -> $archived"
    done
    for kept in "$contract_folder"/*; do
      case "$(basename "$kept")" in handover|*.facts.md) echo "unchanged: $kept" ;; esac
    done ;;

  undo)
    # Without the marker, the old contract may still sit in the folder with no copy in the archive.
    [ -e "$archive_dir/.archived" ] || fail "nothing to undo: $archive_dir/.archived is missing"
    # Check every name before any change, so undo changes nothing or completes.
    for archived in "$archive_dir"/*; do
      [ -e "$archived" ] || continue
      case "$(basename "$archived")" in "$contract_name"|"$note_name") continue ;; esac  # undo deletes these first
      [ ! -e "$contract_folder/$(basename "$archived")" ] || fail "will not move over $contract_folder/$(basename "$archived"), so nothing changed"
    done
    rm -f "$contract_file" "$contract_folder/$note_name" "$HOME/.wstack/pages/contracts/$app_name.html"
    if [ -f "$copied_list" ]; then
      while IFS= read -r copied_name; do
        [ -z "$copied_name" ] || rm -f "$contract_folder/decisions/$copied_name"
      done <"$copied_list"
      rm -f "$copied_list"
    fi
    for archived in "$archive_dir"/*; do
      [ -e "$archived" ] || continue
      mv "$archived" "$contract_folder/"
    done
    rm -f "$archive_dir/.archived"
    rmdir "$archive_dir" || fail "files are left in $archive_dir"
    for empty_folder in "$contract_folder/_archive" "$contract_folder/decisions"; do rmdir "$empty_folder" 2>/dev/null || true; done
    # No render here: a page under the real HOME would make the rehearsal diff differ.
    [ ! -f "$contract_file" ] || echo "rebuild the page: bash '$scripts/contract-render.sh' '$contract_file'" ;;

  rehearse)
    rehearsal_dir="$(mktemp -d)"
    trap 'rm -rf "$rehearsal_dir"' EXIT
    for copy in clean work; do
      mkdir -p "$rehearsal_dir/$copy"
      if [ -d "$contract_folder" ]; then cp -R "$contract_folder" "$rehearsal_dir/$copy/contract"; else mkdir "$rehearsal_dir/$copy/contract"; fi
      cp -R "$task_dir" "$rehearsal_dir/$copy/task"
      rm -rf "$rehearsal_dir/$copy/contract"/*.lock  # a lock held on the real contract would make write wait and fail
    done
    mkdir "$rehearsal_dir/home"
    for step in write undo; do
      echo "== $step"
      HOME="$rehearsal_dir/home" bash "$scripts/contract-deliver.sh" "$step" "$rehearsal_dir/work/task" "$rehearsal_dir/work/contract/$contract_name" "$task_id" 2>&1 \
        || { echo "rehearsal: $step failed"; exit 1; }
    done
    echo "== diff -r clean work"
    diff -r "$rehearsal_dir/clean" "$rehearsal_dir/work" || exit 1
    echo "no difference" ;;

  *) echo "$usage_line" >&2; exit 1 ;;
esac
