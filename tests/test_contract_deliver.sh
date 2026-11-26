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

new_world; rm -rf "$task/decisions.draft"
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write with no decision drafts makes no decisions folder ($out)" '[ $rc = 0 ] && [ ! -e "$folder/decisions" ]'

new_world; mkdir -p "$folder/decisions"; echo other >"$folder/decisions/0001-other.md"; keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "decision id clash exits 1 before any change ($out)" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -qF "decision id 0001 already exists in decisions/: 0001-other.md" && same_as_copy'

new_world; mkdir -p "$folder/handover"; echo h >"$folder/handover/note.md"; echo f >"$folder/svc.facts.md"; echo '# old plan' >"$folder/plan.md"; echo '# old' >"$folder/svc.md"
keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"; write_rc=$rc
[ -f "$page" ] && page_after_write=yes || page_after_write=no
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo restores the folder ($out)" '[ $write_rc = 0 ] && [ $rc = 0 ] && same_as_copy'
assert "undo of a rebuild names the render command for the restored contract" 'has_line "rebuild the page: bash '"'"'$repo_root/scripts/contract-render.sh'"'"' '"'"'$CONTRACT'"'"'"'
assert "undo removes the html page" '[ $page_after_write = yes ] && [ ! -e "$page" ]'

new_world; rm -rf "$folder"
run "$deliver" write "$task" "$CONTRACT" "$task_id"; write_rc=$rc
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo of a new contract names no render command ($out)" '[ $write_rc = 0 ] && [ $rc = 0 ] && ! printf "%s\n" "$out" | grep -qF "rebuild the page:"'

new_world; keep_copy
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo without a write exits 1 and deletes nothing ($out)" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -qF "nothing to undo" && same_as_copy'

new_world; echo '# old notes' >"$folder/zz-notes.md"; echo 'zz-notes.md' >"$task/docs-archive.txt"; keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"; write_rc=$rc
echo '# user notes' >"$folder/zz-notes.md"
rm -rf "$work_dir/after-write"; cp -R "$folder" "$work_dir/after-write"
run "$deliver" undo "$task" "$CONTRACT" "$task_id"; clash_rc=$rc; clash_out="$out"
clash_unchanged=no; diff -r "$folder" "$work_dir/after-write" >/dev/null && clash_unchanged=yes
rm "$folder/zz-notes.md"
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo with a name clash changes nothing, and a second undo restores the folder ($clash_out | $out)" '[ $write_rc = 0 ] && [ $clash_rc = 1 ] &&
  printf "%s\n" "$clash_out" | grep -qF "will not move over $folder/zz-notes.md" && [ $clash_unchanged = yes ] && [ $rc = 0 ] && same_as_copy'

new_world; mkdir -p "$folder/docs"; echo '# rules' >"$folder/docs/do-and-dont.md"; echo '# prd' >"$folder/PRD.md"; keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write with no list keeps vault docs in place and prints unchanged ($out)" '[ $rc = 0 ] && [ -f "$folder/docs/do-and-dont.md" ] && [ -f "$folder/PRD.md" ] &&
  [ ! -e "$archive/docs" ] && [ ! -e "$archive/PRD.md" ] && has_line "unchanged: $folder/docs/do-and-dont.md" && has_line "unchanged: $folder/PRD.md"'

new_world; mkdir -p "$folder/docs"; echo '# flow' >"$folder/docs/flow.md"; echo '# rules' >"$folder/docs/rules.md"; echo '# prd' >"$folder/PRD.md"
printf 'docs/flow.md\n' >"$task/docs-archive.txt"
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write with a list archives only the listed doc, with its subfolder ($out)" '[ $rc = 0 ] && [ -f "$archive/docs/flow.md" ] && [ ! -e "$folder/docs/flow.md" ] &&
  [ -f "$folder/docs/rules.md" ] && [ -f "$folder/PRD.md" ] && has_line "moved: $folder/docs/flow.md -> $archive/docs/flow.md" &&
  has_line "unchanged: $folder/docs/rules.md" && has_line "unchanged: $folder/PRD.md"'

new_world; echo '# prd' >"$folder/PRD.md"; printf 'PRD.md\ndocs/gone.md\n' >"$task/docs-archive.txt"; keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "a listed missing path exits 1 and changes nothing ($out)" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -qF "docs/gone.md" && [ ! -e "$archive" ] && same_as_copy'

for bad_path in '../x' '/x' 'handover/a.md' 'decisions/a.md' 'diagrams/a.html' '_archive/a.md' 'docs/../../x'; do
  new_world; mkdir -p "$folder/handover"; echo a >"$folder/handover/a.md"; printf '%s\n' "$bad_path" >"$task/docs-archive.txt"; keep_copy
  run "$deliver" write "$task" "$CONTRACT" "$task_id"
  assert "a bad list path $bad_path exits 1 and changes nothing ($out)" '[ $rc = 1 ] && [ ! -e "$archive" ] && same_as_copy'
done

new_world; mkdir -p "$folder/docs"; echo '# x' >"$folder/docs/x.md"; echo '# y' >"$folder/docs/y.md"; echo '# prd' >"$folder/PRD.md"
printf 'docs/x.md\nPRD.md\n' >"$task/docs-archive.txt"; keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"; write_rc=$rc
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo merges an archived docs/x.md back into a live docs/ ($out)" '[ $write_rc = 0 ] && [ $rc = 0 ] && same_as_copy && [ ! -e "$folder/_archive" ]'

new_world; mkdir -p "$folder/docs" "$archive/docs"; echo '# y' >"$folder/docs/y.md"; echo '# x' >"$archive/docs/x.md"; touch "$archive/.archived"
keep_copy
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo of an old-style archive holding a whole docs/ merges into a live docs/ ($out)" '[ $rc = 0 ] && [ -f "$folder/docs/x.md" ] && [ -f "$folder/docs/y.md" ] && [ ! -e "$folder/_archive" ]'

new_world; mkdir -p "$archive/docs" "$folder/docs"; echo old >"$archive/docs/x.md"; echo live >"$folder/docs/x.md"; touch "$archive/.archived"; keep_copy
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo with a same-name file clash exits 1 and changes nothing ($out)" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -qF "will not move over $folder/docs/x.md" && same_as_copy'

new_world; mkdir -p "$folder/docs"; echo '# x' >"$folder/docs/x.md"; printf 'docs/x.md\n' >"$task/docs-archive.txt"; keep_copy
run "$deliver" rehearse "$task" "$CONTRACT" "$task_id"
assert "rehearse with a list exits 0 and leaves the real folder unchanged ($out)" '[ $rc = 0 ] && same_as_copy'

new_world; mkdir -p "$folder/diagrams"; echo '<p>flow</p>' >"$folder/diagrams/flow.html"
run "$deliver" write "$task" "$CONTRACT" "$task_id"
assert "write leaves diagrams in place ($out)" '[ $rc = 0 ] && [ -f "$folder/diagrams/flow.html" ] && [ ! -e "$archive/diagrams" ] && has_line "unchanged: $folder/diagrams"'

new_world; mkdir -p "$folder/diagrams"; echo '<p>original</p>' >"$folder/diagrams/sequence-create.html"; keep_copy
run "$deliver" write "$task" "$CONTRACT" "$task_id"; write_rc=$rc
backup="$work_dir/backup-sequence-create.html"
cp "$folder/diagrams/sequence-create.html" "$backup"
echo '<p>redrawn</p>' >"$folder/diagrams/sequence-create.html"; echo '<p>new</p>' >"$folder/diagrams/flow.html"
printf '%s\t%s\n%s\t\n' "$folder/diagrams/sequence-create.html" "$backup" "$folder/diagrams/flow.html" >"$task/diagrams.drawn.txt"
rm -rf "$work_dir/after-write"; cp -R "$folder" "$work_dir/after-write"
mv "$backup" "$backup.hold"
run "$deliver" undo "$task" "$CONTRACT" "$task_id"; missing_rc=$rc
missing_unchanged=no; diff -r "$folder" "$work_dir/after-write" >/dev/null && [ -f "$task/diagrams.drawn.txt" ] && missing_unchanged=yes
mv "$backup.hold" "$backup"
run "$deliver" undo "$task" "$CONTRACT" "$task_id"
assert "undo with a missing deep dive backup changes nothing ($missing_rc)" '[ $write_rc = 0 ] && [ $missing_rc = 1 ] && [ $missing_unchanged = yes ]'
assert "undo restores deep dive backups and removes drawn deep dives ($out)" '[ $rc = 0 ] && [ ! -e "$folder/diagrams/flow.html" ] && [ "$(cat "$folder/diagrams/sequence-create.html")" = "<p>original</p>" ] && same_as_copy'

new_world; echo '# old plan' >"$folder/plan.md"; keep_copy
run "$deliver" rehearse "$task" "$CONTRACT" "$task_id"
assert "rehearse exits 0 and leaves the real folders unchanged ($out)" '[ $rc = 0 ] && same_as_copy && [ ! -e "$page" ]'

new_world; mkdir -p "$folder/diagrams"; echo '<p>real</p>' >"$folder/diagrams/flow.html"; echo '<p>old</p>' >"$work_dir/real-backup.html"
echo '<p>drawn</p>' >"$folder/diagrams/sequence-create.html"
printf '%s\t%s\n%s\t\n' "$folder/diagrams/sequence-create.html" "$work_dir/real-backup.html" "$folder/diagrams/flow.html" >"$task/diagrams.drawn.txt"
keep_copy
run "$deliver" rehearse "$task" "$CONTRACT" "$task_id"
assert "rehearse with a drawn list leaves the real deep dives, backup, and list alone ($out)" '[ $rc = 0 ] && same_as_copy && [ -f "$folder/diagrams/flow.html" ] && [ "$(cat "$folder/diagrams/sequence-create.html")" = "<p>drawn</p>" ] && [ -f "$work_dir/real-backup.html" ]'

new_world; mkdir "$CONTRACT.lock"; keep_copy
run "$deliver" rehearse "$task" "$CONTRACT" "$task_id"
assert "rehearse exits 0 while a lock is held on the real contract, and the lock stays ($out)" '[ $rc = 0 ] && same_as_copy && [ -d "$CONTRACT.lock" ]'
rmdir "$CONTRACT.lock"

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

new_world; evidence="$work_dir/evidence $case_count"
other="$(dirname "$REPO")/other"   # found through workspace_root in the initiation file
git init -q -b main "$other"; printf 'a\nb\nc\n' >"$other/x.txt"
git -C "$other" add -A; git -C "$other" commit -q -m x; git -C "$other" remote add origin git@github.com:acme-org/other.git
other_commit="$(git -C "$other" rev-parse HEAD)"
OTHER_REF="acme-org/other@$other_commit:x.txt:9" yq -i '.sections.abilities.items = [{"text": "Claim.", "refs": [strenv(OTHER_REF)]}]' "$task/contract.draft.yaml"
rm -rf "$folder"   # a new service: the contract folder does not exist yet
run "$verify_draft" "$REPO" "$task" "$CONTRACT" "$task_id" "$evidence"
assert "verify-draft fails the refs check on a bad cross-repo ref ($out)" '[ $rc = 1 ] && has_line "FAIL contract-refs" &&
  grep -q "^bad: acme-org/other@$other_commit:x.txt:9: " "$evidence/check-contract-refs.txt"'

finish
