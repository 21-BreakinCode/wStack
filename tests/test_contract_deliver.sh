#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
deliver="$repo_root/scripts/contract-deliver.sh"
verify_draft="$repo_root/scripts/contract-verify-draft.sh"
setup="$repo_root/tests/fixtures/contract/setup.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"
task_id="2026-11-24-svc-contract"
case_count=0

new_world() {  # sets REPO, CONTRACT, folder, task, archive, page; the task folder holds the drafts
  case_count=$((case_count + 1))
  source "$(bash "$setup" "$work_dir/case $case_count")"
  folder="$(dirname "$CONTRACT")"
  archive="$folder/_archive/$task_id"
  page="$HOME/.wstack/pages/contracts/svc.html"
  rm -f "$page"
  task="$VAULT/wStack/Tasks/$task_id"
  mkdir -p "$task/decisions.draft"
  sed 's/^summary: .*/summary: New text./' "$CONTRACT" >"$task/contract.draft.yaml"
  printf -- '---\nid: "0001"\n---\n\n# 0001 Baseline\n' >"$task/decisions.draft/0001-baseline.md"
  printf -- '---\nid: "0002"\n---\n\n# 0002 Queue\n' >"$task/decisions.draft/0002-queue.md"
}
run() {  # <script> <args>...
  set +e; out="$(bash "$@" 2>&1)"; rc=$?; set -e
}
has_line() { printf '%s\n' "$out" | grep -qxF "$1"; }
keep_copy() { rm -rf "$work_dir/copy"; mkdir -p "$work_dir/copy"; cp -R "$folder" "$work_dir/copy/contract"; cp -R "$task" "$work_dir/copy/task"; }
same_as_copy() { diff -r "$folder" "$work_dir/copy/contract" >/dev/null && diff -r "$task" "$work_dir/copy/task" >/dev/null; }

new_world; rm -rf "$folder"
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write on a new folder prints new lines ($out)" '[ $rc = 0 ] && has_line "new: $CONTRACT" && has_line "new: $folder/svc.md" &&
  has_line "new: $folder/decisions/0001-baseline.md" && has_line "new: $folder/decisions/0002-queue.md" &&
  ! printf "%s\n" "$out" | grep -q "^replaced:\|^moved:" && grep -qxF "summary: New text." "$CONTRACT" && [ -f "$page" ] && [ ! -e "$CONTRACT.lock" ]'

new_world; mkdir -p "$folder/handover"; echo h >"$folder/handover/note.md"; echo f >"$folder/svc.facts.md"
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write keeps handover and facts in place ($out)" '[ $rc = 0 ] && [ -f "$folder/handover/note.md" ] && [ -f "$folder/svc.facts.md" ] &&
  [ ! -e "$archive/svc.facts.md" ] && [ ! -e "$archive/handover" ] && has_line "unchanged: $folder/svc.facts.md" && has_line "unchanged: $folder/handover"'

new_world; echo '# old md contract' >"$folder/svc.md"; echo '# old plan' >"$folder/plan.md"; cp "$CONTRACT" "$work_dir/contract.orig"
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write moves an old md contract and plan.md to the archive ($out)" '[ $rc = 0 ] && grep -qxF "# old md contract" "$archive/svc.md" &&
  [ -f "$archive/plan.md" ] && [ ! -e "$folder/plan.md" ] && [ -e "$archive/.archived" ] && cmp -s "$archive/svc.contract.yaml" "$work_dir/contract.orig" &&
  has_line "replaced: $folder/svc.md (old copy: $archive/svc.md)" && has_line "replaced: $CONTRACT (old copy: $archive/svc.contract.yaml)" &&
  has_line "moved: $folder/plan.md -> $archive/plan.md"'

new_world; cp "$CONTRACT" "$work_dir/contract.orig"
run "$deliver" write "$task" "$CONTRACT" "$task_id"; first_rc=$rc; first_out="$out"
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write twice is safe ($out)" '[ $first_rc = 0 ] && [ $rc = 0 ] && [ "$out" = "$first_out" ] && cmp -s "$archive/svc.contract.yaml" "$work_dir/contract.orig" &&
  [ "$(cat "$task/decisions.copied.txt")" = "$(printf "0001-baseline.md\n0002-queue.md")" ] && grep -qxF "summary: New text." "$CONTRACT" && [ ! -e "$CONTRACT.lock" ]'

new_world; mkdir -p "$folder/decisions"; echo other >"$folder/decisions/0001-other.md"; keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "decision id clash exits 1 before any change ($out)" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -qF "decision id 0001 already exists in decisions/: 0001-other.md" && same_as_copy'

new_world; mkdir -p "$folder/handover"; echo h >"$folder/handover/note.md"; echo f >"$folder/svc.facts.md"; echo '# old plan' >"$folder/plan.md"; echo '# old' >"$folder/svc.md"
keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"; write_rc=$rc
[ -f "$page" ] && page_after_write=yes || page_after_write=no
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo restores the folder ($out)" '[ $write_rc = 0 ] && [ $rc = 0 ] && same_as_copy'
assert "undo removes the html page" '[ $page_after_write = yes ] && [ ! -e "$page" ]'

new_world; keep_copy
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo without a write exits 1 and deletes nothing ($out)" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -qF "nothing to undo" && same_as_copy'

new_world; echo '# old plan' >"$folder/plan.md"; keep_copy
run "$deliver" rehearse "$task" "$CONTRACT" "$task_id"
assert "rehearse exits 0 and leaves the real folders unchanged ($out)" '[ $rc = 0 ] && same_as_copy && [ ! -e "$page" ]'

new_world; evidence="$work_dir/evidence $case_count"
run "$verify_draft" "$REPO" "$task" "$CONTRACT" "$task_id" "$evidence"
assert "verify-draft writes four evidence files and exits 0 ($out)" '[ $rc = 0 ] &&
  [ -s "$evidence/check-contract-check.txt" ] && [ -s "$evidence/check-contract-validate.txt" ] &&
  [ -s "$evidence/check-contract-refs.txt" ] && [ -s "$evidence/check-undo-rehearsal.txt" ] &&
  has_line "PASS contract-check" && has_line "PASS contract-validate" && has_line "PASS contract-refs" && has_line "PASS undo-rehearsal" &&
  [ "$(grep -c "^unclaimed_count: 0$" "$evidence/check-contract-check.txt")" = 2 ]'

new_world; evidence="$work_dir/evidence $case_count"
yq -i '.sections.abilities.items = [{"text": "Claim.", "refs": ["cmd/gone.go:1"]}]' "$task/contract.draft.yaml"
run "$verify_draft" "$REPO" "$task" "$CONTRACT" "$task_id" "$evidence"
assert "verify-draft fails the refs check on a bad ref ($out)" '[ $rc = 1 ] && has_line "FAIL contract-refs" && has_line "PASS contract-validate" &&
  grep -q "^bad: cmd/gone.go:1: " "$evidence/check-contract-refs.txt"'

finish
