#!/usr/bin/env bash
# contract-deliver.sh write|undo|rehearse <task_dir> <contract_file> <task_id>
# Deliver "Contract files": copy <task_dir>/contract.draft.yaml and decisions.draft/* into the contract folder.
#   write     Check decision ids, take the lock, move to _archive/<task_id>/ (once, marker .archived) the old
#             contract files (<app_name>.contract.yaml, <app_name>.md, plan.md) and each path listed in
#             <task_dir>/docs-archive.txt (one path per line, relative to the contract folder, kept with its
#             subfolders). Then copy the drafts, run set-verified (it renders). Safe to run again after a failure.
#             A vault doc is any other file outside handover/, decisions/, diagrams/, _archive/, *.lock and
#             *.facts.md. A vault doc not in the list stays. No list file means no vault doc moves.
#             A listed path that is missing, has .., starts with /, or is not a vault doc exits 1 before any change.
#             Prints one line per file: new:, replaced: (old copy: ...), moved: ... -> ..., unchanged:.
#             Exit 0 done, 4 lock busy, 1 a decision id clash or a failed step.
#   undo      First restore the deep dives listed in diagrams.drawn.txt (backup back, new ones removed).
#             Delete the contract, the note, the HTML page, and the copied decisions; move the archive back
#             file by file at any depth (an archived docs/ merges into a live docs/). A live file with the same
#             relative path makes it exit 1 before any change.
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
drawn_list="$task_dir/diagrams.drawn.txt"

docs_list="$task_dir/docs-archive.txt"

is_vault_doc() {  # <path relative to the contract folder>
  case "$1" in
    handover/*|decisions/*|diagrams/*|_archive/*|.*|*/.*|*.lock|*.lock/*|*.facts.md|"$contract_name"|"$note_name"|plan.md) return 1 ;;
  esac
}
each_file_under() {  # <folder>: print the relative path of every file under it, sorted
  [ -d "$1" ] || return 0
  (cd "$1" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}
each_listed_doc() {  # the lines of docs-archive.txt, no blank lines
  [ -f "$docs_list" ] || return 0
  while IFS= read -r listed_rel || [ -n "$listed_rel" ]; do
    [ -z "$listed_rel" ] || printf '%s\n' "$listed_rel"
  done <"$docs_list"
}

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
    while IFS= read -r listed_rel; do
      case "$listed_rel" in /*|..|../*|*/../*|*/..) fail "bad path in docs-archive.txt: $listed_rel, so nothing changed" ;; esac
      is_vault_doc "$listed_rel" || fail "not a vault doc in docs-archive.txt: $listed_rel, so nothing changed"
      # A rerun finds a listed doc already in the archive.
      [ -e "$archive_dir/.archived" ] || [ -f "$contract_folder/$listed_rel" ] || fail "missing path in docs-archive.txt: $listed_rel, so nothing changed"
    done < <(each_listed_doc)
    mkdir -p "$archive_dir"
    if [ ! -e "$archive_dir/.archived" ]; then
      move_to_archive() {  # <relative path>
        [ -e "$contract_folder/$1" ] || return 0
        [ ! -e "$archive_dir/$1" ] || return 0
        mkdir -p "$(dirname "$archive_dir/$1")"
        mv "$contract_folder/$1" "$archive_dir/$1"
        local emptied; emptied="$(dirname "$contract_folder/$1")"
        while [ "$emptied" != "$contract_folder" ] && rmdir "$emptied" 2>/dev/null; do emptied="$(dirname "$emptied")"; done
      }
      for old_name in "$contract_name" "$note_name" plan.md; do move_to_archive "$old_name"; done
      while IFS= read -r listed_rel; do move_to_archive "$listed_rel"; done < <(each_listed_doc)
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
    while IFS= read -r archived_rel; do
      [ "$archived_rel" != .archived ] || continue
      case "$archived_rel" in "$contract_name"|"$note_name") [ ! -e "$contract_folder/$archived_rel" ] || continue ;; esac
      echo "moved: $contract_folder/$archived_rel -> $archive_dir/$archived_rel"
    done < <(each_file_under "$archive_dir")
    for kept in "$contract_folder"/*; do
      case "$(basename "$kept")" in handover|diagrams|*.facts.md) echo "unchanged: $kept" ;; esac
    done
    while IFS= read -r vault_rel; do
      ! is_vault_doc "$vault_rel" || echo "unchanged: $contract_folder/$vault_rel"
    done < <(each_file_under "$contract_folder") ;;

  undo)
    # Without the marker, the old contract may still sit in the folder with no copy in the archive.
    [ -e "$archive_dir/.archived" ] || fail "nothing to undo: $archive_dir/.archived is missing"
    # Check every name before any change, so undo changes nothing or completes.
    while IFS= read -r archived_rel; do
      [ "$archived_rel" != .archived ] || continue
      case "$archived_rel" in "$contract_name"|"$note_name") continue ;; esac  # undo deletes these first
      [ ! -e "$contract_folder/$archived_rel" ] || fail "will not move over $contract_folder/$archived_rel, so nothing changed"
    done < <(each_file_under "$archive_dir")
    if [ -f "$drawn_list" ]; then  # restore checks this too, but only after undo started changing files
      while IFS=$'\t' read -r _ backup_path; do
        [ -z "$backup_path" ] || [ -f "$backup_path" ] || fail "deep dive backup missing: $backup_path, so nothing changed"
      done <"$drawn_list"
    fi
    bash "$scripts/contract-diagram.sh" restore "$drawn_list"
    rm -f "$contract_file" "$contract_folder/$note_name" "$HOME/.wstack/pages/contracts/$app_name.html"
    if [ -f "$copied_list" ]; then
      while IFS= read -r copied_name; do
        [ -z "$copied_name" ] || rm -f "$contract_folder/decisions/$copied_name"
      done <"$copied_list"
      rm -f "$copied_list"
    fi
    while IFS= read -r archived_rel; do
      [ "$archived_rel" != .archived ] || continue
      mkdir -p "$(dirname "$contract_folder/$archived_rel")"
      mv "$archive_dir/$archived_rel" "$contract_folder/$archived_rel"
    done < <(each_file_under "$archive_dir")
    rm -f "$archive_dir/.archived"
    find "$archive_dir" -depth -type d -empty -exec rmdir {} \;
    [ ! -e "$archive_dir" ] || fail "files are left in $archive_dir"
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
      rm -f "$rehearsal_dir/$copy/task/diagrams.drawn.txt"  # its paths are real files; write draws nothing, so undo needs no list
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
