#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export WSTACK_OBSIDIAN_BIN="$repo/tests/fixtures/fake-obsidian.sh" WSTACK_ARCHIVE_WAIT=0 FAKE_TASKS_DIR=Tasks
archive="$repo/scripts/archive-tasks.py"

make_task() {  # <vault> <id> <status> <retro_read> <extra file>...
  local vault="$1" id="$2" status="$3" read_mark="$4"; shift 4
  mkdir -p "$vault/Tasks/$id"
  printf -- '---\ntask_id: %s\nstatus: %s\nretro_read: %s\n---\nbody\n' "$id" "$status" "$read_mark" > "$vault/Tasks/$id/spec.md"
  local extra
  for extra in "$@"; do mkdir -p "$(dirname "$vault/Tasks/$id/$extra")"; echo x > "$vault/Tasks/$id/$extra"; done
}
make_vault() {  # <name> <alwaysUpdateLinks>
  mkdir -p "$work_dir/$1/.obsidian"
  echo "{\"alwaysUpdateLinks\": $2}" > "$work_dir/$1/.obsidian/app.json"
  echo "$work_dir/$1"
}

vault="$(make_vault v1 true)"
make_task "$vault" 2026-11-20-a delivered 2026-W48 review.html decisions.draft/0001-x.md
make_task "$vault" 2026-11-20-b delivered 2026-W48 fail-me.md
make_task "$vault" 2026-11-20-c cancelled 2026-W48
make_task "$vault" 2026-11-20-open executing ""
rc=0; out="$(FAKE_VAULT="$vault" FAKE_FAIL_MATCH=fail-me /usr/bin/env python3 "$archive" --vault "$vault" --tasks-dir Tasks --week 2026-W48 2026-11-20-a 2026-11-20-b 2026-11-20-c 2026-11-20-open 2>&1)" || rc=$?
assert "run exits 0" '[ "$rc" = 0 ]'
assert "full move: spec, html, and subfolder file arrive" '[ -f "$vault/Tasks/_archive/2026-W48/2026-11-20-a/spec.md" ] && [ -f "$vault/Tasks/_archive/2026-W48/2026-11-20-a/review.html" ] && [ -f "$vault/Tasks/_archive/2026-W48/2026-11-20-a/decisions.draft/0001-x.md" ]'
assert "full move: source folder is gone" '[ ! -e "$vault/Tasks/2026-11-20-a" ]'
assert "failure in the middle moves files back" '[ -f "$vault/Tasks/2026-11-20-b/spec.md" ] && [ -f "$vault/Tasks/2026-11-20-b/fail-me.md" ] && [ ! -e "$vault/Tasks/_archive/2026-W48/2026-11-20-b" ] && grep -q "^not moved 2026-11-20-b: " <<<"$out"'
assert "the next task still moves after a failure" 'grep -q "^moved 2026-11-20-c -> " <<<"$out"'
assert "an open task is not moved" 'grep -q "^not moved 2026-11-20-open: status executing" <<<"$out"'
assert "an open task stays in place" '[ -f "$vault/Tasks/2026-11-20-open/spec.md" ]'
assert "candidates: marked delivered task, also when not moved" '[ "$(bash "$repo/scripts/archive-candidates.sh" --vault "$vault" --tasks-dir Tasks)" = "2026-11-20-b" ]'

rc_exists=0; mkdir -p "$vault/Tasks/_archive/2026-W48/2026-11-20-b"
out_exists="$(FAKE_VAULT="$vault" python3 "$archive" --vault "$vault" --tasks-dir Tasks --week 2026-W48 2026-11-20-b 2>&1)" || rc_exists=$?
assert "an existing destination is not moved" '[ "$rc_exists" = 0 ] && grep -q "^not moved 2026-11-20-b: destination exists" <<<"$out_exists" && [ -f "$vault/Tasks/2026-11-20-b/spec.md" ]'
out_missing="$(FAKE_VAULT="$vault" python3 "$archive" --vault "$vault" --tasks-dir Tasks --week 2026-W48 2026-11-20-nope 2>&1)"
assert "a missing task is reported" 'grep -q "^not moved 2026-11-20-nope: " <<<"$out_missing"'

vault_back="$(make_vault v4 true)"
make_task "$vault_back" 2026-11-20-d delivered 2026-W48 zz-second.md
rc_back=0; out_back="$(FAKE_VAULT="$vault_back" FAKE_FAIL_MATCH=zz-second FAKE_FAIL_ARCHIVE_SOURCE=1 python3 "$archive" --vault "$vault_back" --tasks-dir Tasks --week 2026-W48 2026-11-20-d 2>&1)" || rc_back=$?
assert "failed move back exits 4 and lists the files" '[ "$rc_back" = 4 ] && grep -q "left in old folder:" <<<"$out_back" && grep -q "left in archive:" <<<"$out_back"'
assert "failed move back lists each file once on the right side" 'grep -q "Tasks/2026-11-20-d/zz-second.md" <<<"$out_back" && grep -q "_archive/2026-W48/2026-11-20-d/spec.md" <<<"$out_back"'

vault_raw="$(make_vault v5 true)"
make_task "$vault_raw" 2026-11-20-e delivered 2026-W48 docs/note.md .DS_Store
ln -s docs "$vault_raw/Tasks/2026-11-20-e/linkdir"
out_raw="$(FAKE_VAULT="$vault_raw" python3 "$archive" --vault "$vault_raw" --tasks-dir Tasks --week 2026-W48 2026-11-20-e 2>&1)"
dest_raw="$vault_raw/Tasks/_archive/2026-W48/2026-11-20-e"
assert "symlink and dot file: moved completely" 'grep -q "^moved 2026-11-20-e -> " <<<"$out_raw" && [ ! -e "$vault_raw/Tasks/2026-11-20-e" ] && [ -f "$dest_raw/docs/note.md" ] && [ -f "$dest_raw/.DS_Store" ]'
assert "the symlink arrives as a symlink" '[ -L "$dest_raw/linkdir" ] && [ "$(readlink "$dest_raw/linkdir")" = docs ]'

vault_ghost="$(make_vault v6 true)"
make_task "$vault_ghost" 2026-11-20-f delivered 2026-W48 ghost.md
rc_ghost=0; out_ghost="$(FAKE_VAULT="$vault_ghost" FAKE_MOVE_THEN_FAIL_MATCH=ghost python3 "$archive" --vault "$vault_ghost" --tasks-dir Tasks --week 2026-W48 2026-11-20-f 2>&1)" || rc_ghost=$?
assert "a move that failed but really moved exits 4 and lists both sides" '[ "$rc_ghost" = 4 ] && grep -q "Tasks/2026-11-20-f/spec.md" <<<"$out_ghost" && grep -q "_archive/2026-W48/2026-11-20-f/ghost.md" <<<"$out_ghost" && ! grep -q "^not moved" <<<"$out_ghost"'

vault2="$(make_vault v2 false)"
make_task "$vault2" 2026-11-20-a delivered 2026-W48
rc_links=0; FAKE_VAULT="$vault2" python3 "$archive" --vault "$vault2" --tasks-dir Tasks --week 2026-W48 2026-11-20-a >/dev/null 2>&1 || rc_links=$?
assert "alwaysUpdateLinks false exits 3 and moves nothing" '[ "$rc_links" = 3 ] && [ -d "$vault2/Tasks/2026-11-20-a" ]'

vault3="$(make_vault v3 true)"
make_task "$vault3" 2026-11-20-a delivered 2026-W48
rc_vault=0; FAKE_VAULT="$work_dir/other" python3 "$archive" --vault "$vault3" --tasks-dir Tasks --week 2026-W48 2026-11-20-a >/dev/null 2>&1 || rc_vault=$?
assert "another open vault exits 3 and moves nothing" '[ "$rc_vault" = 3 ] && [ -d "$vault3/Tasks/2026-11-20-a" ]'

rc_input=0; python3 "$archive" --vault "$vault3" --tasks-dir Tasks --week bad 2026-11-20-a >/dev/null 2>&1 || rc_input=$?
assert "a bad week exits non-zero" '[ "$rc_input" != 0 ]'
finish
