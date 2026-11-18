#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
upload="$repo_root/scripts/evidence-upload.sh"
delete="$repo_root/scripts/evidence-delete.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export FAKE_LOG="$work_dir/cf.log"
task_id="2000-01-02-demo"
evidence_dir="$work_dir/my evidence"
mkdir "$evidence_dir"
echo a > "$evidence_dir/a.webp"; echo b > "$evidence_dir/b.mp4"; echo c > "$evidence_dir/with space.txt"

fresh_log() { rm -f "$FAKE_LOG" "$FAKE_LOG.listed"; : > "$FAKE_LOG"; }
up() { bash "$upload" --task-id "$task_id" --dir "$evidence_dir" --bucket bkt --domain ev.example.com --repo o/r --local-only-repos "x/y" "$@"; }

fresh_log
out="$(up)"
assert "put a.webp key" 'grep -q "^cf r2 objects put evidence/$task_id/a.webp --bucket-name bkt --file $evidence_dir/a.webp --content-type" "$FAKE_LOG"'
assert "put b.mp4 key" 'grep -q "^cf r2 objects put evidence/$task_id/b.mp4 " "$FAKE_LOG"'
assert "put file name with space" 'grep -q "^cf r2 objects put evidence/$task_id/with space.txt " "$FAKE_LOG"'
assert "three put calls" '[ "$(grep -c "^cf r2 objects put" "$FAKE_LOG")" = 3 ]'
assert "url a" '[[ "$out" == *"https://ev.example.com/evidence/$task_id/a.webp"* ]]'
assert "url b" '[[ "$out" == *"https://ev.example.com/evidence/$task_id/b.mp4"* ]]'
assert "url space is encoded" '[[ "$out" == *"/with%20space.txt"* ]]'
assert "no presigned url" '[[ "$out" != *"X-Amz"* && "$out" != *"presign"* ]]'

fresh_log
out="$(up --dry-run)"
assert "upload dry-run logs no call" '[ ! -s "$FAKE_LOG" ]'
assert "upload dry-run prints cf command" '[[ "$out" == *"cf r2 objects put evidence/$task_id/a.webp"* ]]'

fresh_log
out="$(bash "$upload" --task-id "$task_id" --dir "$evidence_dir" --bucket "" --domain ev.example.com --repo o/r --local-only-repos "")"
assert "empty bucket: local only" '[[ "$out" == *"local only: $evidence_dir"* ]]'
assert "empty bucket: no cf call" '[ ! -s "$FAKE_LOG" ]'

fresh_log
out="$(bash "$upload" --task-id "$task_id" --dir "$evidence_dir" --bucket bkt --domain ev.example.com --repo o/r --local-only-repos "a/b,o/r")"
assert "listed repo: local only" '[[ "$out" == *"local only: $evidence_dir"* ]]'
assert "listed repo: no cf call" '[ ! -s "$FAKE_LOG" ]'

fresh_log
out="$(bash "$upload" --task-id "$task_id" --dir "$evidence_dir" --bucket bkt --domain "" --repo o/r --local-only-repos "")"
assert "empty domain: local only" '[[ "$out" == *"local only: $evidence_dir"* ]]'
assert "empty domain: names evidence_domain" '[[ "$out" == *"evidence_domain"* ]]'
assert "empty domain: no cf call" '[ ! -s "$FAKE_LOG" ]'

# R25(a): bad task ids stop before any cf call
for bad_id in "" ".." "2000-01-02-a/b" "2000-01-02-a b" "../x" "2000-01-02-Demo" "demo"; do
  fresh_log
  assert "upload rejects id '$bad_id'" '! bash "$upload" --task-id "$bad_id" --dir "$evidence_dir" --bucket bkt --domain d --repo o/r --local-only-repos "" >/dev/null 2>&1'
  assert "delete rejects id '$bad_id'" '! bash "$delete" --task-id "$bad_id" --bucket bkt >/dev/null 2>&1'
  assert "bad id '$bad_id' logs no cf call" '[ ! -s "$FAKE_LOG" ]'
done

# delete: list the prefix, then bulk-delete by key list
fresh_log
FAKE_CF_LIST="[{\"key\":\"evidence/$task_id/a.webp\"},{\"key\":\"evidence/$task_id/b.mp4\"},{\"key\":\"evidence/other/x\"}]" \
  bash "$delete" --task-id "$task_id" --bucket bkt > "$work_dir/delete.out"
assert "delete lists the prefix" 'grep -q "^cf r2 objects list --bucket-name bkt --prefix evidence/$task_id/ " "$FAKE_LOG"'
assert "delete sends a key list" 'grep -q "^cf r2 objects bulk-delete --bucket-name bkt --body \[\"evidence/$task_id/a.webp\",\"evidence/$task_id/b.mp4\"\] --force$" "$FAKE_LOG"'
assert "delete skips keys outside the prefix" '! grep -q "evidence/other" <(grep bulk-delete "$FAKE_LOG")'
assert "delete never uses --prefix on bulk-delete" '! grep "bulk-delete" "$FAKE_LOG" | grep -q -- "--prefix"'
assert "delete never makes a job" '! grep -q "jobs" "$FAKE_LOG"'

fresh_log
out="$(bash "$delete" --task-id "$task_id" --bucket bkt)"
assert "empty listing: says nothing found" '[[ "$out" == *"nothing found"* ]]'
assert "empty listing: no bulk-delete" '! grep -q "bulk-delete" "$FAKE_LOG"'

fresh_log
bash "$delete" --task-id "$task_id" --bucket bkt --dry-run >/dev/null
assert "delete dry-run logs no call" '[ ! -s "$FAKE_LOG" ]'

# delete safety branches
one_key_listing="[{\"key\":\"evidence/$task_id/a.webp\"}]"
fresh_log
assert "delete fails when bulk-delete fails" '! FAKE_CF_LIST="$one_key_listing" FAKE_CF_BULK_FAIL=1 bash "$delete" --task-id "$task_id" --bucket bkt >/dev/null 2>&1'

fresh_log
assert "delete exits 1 when the same keys stay listed" '! FAKE_CF_LIST="$one_key_listing" FAKE_CF_LIST_EVERY_TIME=1 bash "$delete" --task-id "$task_id" --bucket bkt >/dev/null 2>&1'
assert "same-keys case stops after one bulk-delete" '[ "$(grep -c "bulk-delete" "$FAKE_LOG")" = 1 ]'

fresh_log
assert "delete exits 1 when list output is not an array" '! FAKE_CF_LIST="{\"error\":1}" bash "$delete" --task-id "$task_id" --bucket bkt >/dev/null 2>&1'
assert "non-array list: no bulk-delete" '! grep -q "bulk-delete" "$FAKE_LOG"'

fresh_log
page_one="$(jq -nc --arg p "evidence/$task_id/" '[range(1500) | {key: ($p + "f\(.).txt")}]')"
page_two="$(jq -nc --arg p "evidence/$task_id/" '[range(1000; 1500) | {key: ($p + "f\(.).txt")}]')"
multi_out="$(FAKE_CF_LISTS="$page_one"$'\n'"$page_two" bash "$delete" --task-id "$task_id" --bucket bkt)"
assert "multi-round: two bulk-deletes" '[ "$(grep -c "bulk-delete" "$FAKE_LOG")" = 2 ]'
assert "multi-round: every body holds at most 1000 keys" '[ "$(grep "bulk-delete" "$FAKE_LOG" | sed "s/.*--body \(.*\) --force$/\1/" | jq -s "map(length) | max")" = 1000 ]'
assert "multi-round: first body is 1000 keys, second is 500" '[ "$(grep "bulk-delete" "$FAKE_LOG" | sed "s/.*--body \(.*\) --force$/\1/" | jq -sc "map(length)")" = "[1000,500]" ]'
assert "multi-round: reports 1500 deleted" '[[ "$multi_out" == *"deleted 1500 objects"* ]]'

finish
