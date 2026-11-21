#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-check.sh"
setup="$repo_root/tests/fixtures/contract/setup.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
case_count=0
new_world() {
  case_count=$((case_count + 1))
  source "$(bash "$setup" "$work_dir/case $case_count")"
}
push_file() {  # <relative path>
  mkdir -p "$(dirname "$REPO/$1")"
  echo "change $RANDOM" > "$REPO/$1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "change $1"
  git -C "$REPO" push -q origin main 2>/dev/null
}
run() { set +e; out="$(bash "$script" "$REPO" "$CONTRACT" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"; }
field() { printf '%s\n' "$out" | sed -n "s/^$1: //p"; }
set_key() {  # <file> <key> <value>
  sed -i.bak "s|^$2: .*|$2: $3|" "$1"
}

new_world; run
assert "fresh" '[ $rc = 0 ] && [ "$(field status)" = fresh ] && [ "$(field behind)" = 0 ] && [ "$(field base)" = origin/main ]'
assert "line order" '[ "$(printf "%s\n" "$out" | cut -d: -f1 | paste -sd, -)" = "status,base,behind,stale_sections,stale_dependencies,unclaimed_files,unclaimed_count,pending" ]'

new_world; push_file api/new.go; run
assert "section stale" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"Interfaces\"]" ] && [ "$(field behind)" = 1 ] && [ "$(field status)" = stale ]'

new_world; push_file docs/PRD.md; run
assert "team doc stale" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"Team docs\"]" ] && [ "$(field unclaimed_count)" = 0 ]'

new_world; push_file README.md; run
assert "unclaimed" '[ $rc = 1 ] && [ "$(field unclaimed_files)" = "[\"README.md\"]" ] && [ "$(field unclaimed_count)" = 1 ] && [ "$(field stale_sections)" = "[]" ]'

new_world; push_file tests/b_test.go; run
assert "ignored" '[ $rc = 0 ] && [ "$(field unclaimed_count)" = 0 ]'

new_world; push_file "api/my file.go"; run
assert "space in a name" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"Interfaces\"]" ]'

new_world
git -C "$REPO" checkout -q -b feature
echo x > "$REPO/api/x.go"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m x
run
assert "feature branch" '[ $rc = 0 ]'

new_world; set_key "$CONTRACT" verified_commit 0123456789abcdef0123456789abcdef01234567; run
assert "unknown commit" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"Team docs\",\"Abilities\",\"Interfaces\"]" ]'

new_world; set_key "$CONTRACT" pending '[{"pr":12,"task":"t1"}]'; run
assert "pending listed" '[ $rc = 0 ] && [ "$(field pending)" = "[{\"pr\":12,\"task\":\"t1\"}]" ]'

new_world
dep_dir="$ORG_DIR/Services/dep"; mkdir -p "$dep_dir"
echo "| dep | $(dirname "$REPO")/dep | Services/dep |" >> "$ORG_DIR/handover_handler__initiation.md"
printf -- '---\napp_name: dep\nverified_commit: aaa1111\n---\n' > "$dep_dir/dep.md"
echo '- dep (mapped): its contract at commit aaa1111' >> "$CONTRACT"
run
assert "dependency equal" '[ $rc = 0 ] && [ "$(field stale_dependencies)" = "[]" ]'
set_key "$dep_dir/dep.md" verified_commit bbb2222; run
assert "dependency changed" '[ $rc = 1 ] && [ "$(field stale_dependencies)" = "[\"dep\"]" ] && [ "$(field stale_sections)" = "[\"Depends on\"]" ]'

new_world; rm "$CONTRACT"; run
assert "missing contract" '[ $rc = 3 ]'

new_world; sed -i.bak '/^verified_commit:/d' "$CONTRACT"; run
assert "bad frontmatter" '[ $rc = 2 ] && [ -n "$err" ]'

new_world; set_key "$CONTRACT" base_branch release; run
assert "missing base ref" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "origin/release"'

new_world
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "$i" > "$REPO/n$i.txt"; done
git -C "$REPO" add -A; git -C "$REPO" commit -q -m many; git -C "$REPO" push -q origin main 2>/dev/null; run
assert "unclaimed capped at 10" '[ "$(field unclaimed_count)" = 12 ] && [ "$(field unclaimed_files | jq length)" = 10 ]'

new_world
mkdir -p "$REPO/api/v1" "$REPO/cmd/tool" "$REPO/tests/many" "$REPO/misc"
for i in $(seq 1 125); do
  echo "$i" > "$REPO/api/v1/f$i.go"; echo "$i" > "$REPO/cmd/tool/f$i.go"
  echo "$i" > "$REPO/tests/many/f$i.go"; echo "$i" > "$REPO/misc/f$i.txt"
done
git -C "$REPO" add -A; git -C "$REPO" commit -q -m bulk; git -C "$REPO" push -q origin main 2>/dev/null
started=$SECONDS; run; elapsed=$((SECONDS - started))
echo "  (500 files took ${elapsed}s)"
assert "500 changed files" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"Interfaces\",\"Abilities\"]" ] && [ "$(field unclaimed_count)" = 125 ] && [ "$elapsed" -lt 10 ]'


finish
