#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/handover/ensure-exclude.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
case_count=0
new_repo() {
  case_count=$((case_count + 1))
  repo="$work_dir/case $case_count/my repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}
gitignore_sum() { if [ -f "$1/.gitignore" ]; then cksum < "$1/.gitignore"; else echo none; fi; }
run() { set +e; out="$(bash "$script" "$@" 2>/dev/null)"; rc=$?; set -e; }
exclude_count() { grep -cx '/handover' "$1/.git/info/exclude" || true; }

new_repo; before="$(gitignore_sum "$repo")"
run "$repo"
assert "fresh repository" '[ "$out" = added ] && git -C "$repo" check-ignore -q handover && [ ! -e "$repo/.gitignore" ]'
run "$repo"
assert "second run" '[ "$out" = "already present" ] && [ "$(exclude_count "$repo")" = 1 ]'
assert "gitignore untouched" '[ "$(gitignore_sum "$repo")" = "$before" ]'

new_repo; echo '/handover' > "$repo/.gitignore"; before="$(gitignore_sum "$repo")"
run "$repo"
assert "team gitignore covers it" '[ "$out" = "already present" ] && [ "$(exclude_count "$repo")" = 0 ] && [ "$(gitignore_sum "$repo")" = "$before" ]'

new_repo; echo 'handover/' > "$repo/.gitignore"; ln -s /tmp "$repo/handover"; before="$(gitignore_sum "$repo")"
run "$repo"
assert "trailing slash does not count" '[ "$out" = added ] && [ "$(gitignore_sum "$repo")" = "$before" ]'

new_repo
git -C "$repo" worktree add -q "$work_dir/wt tree" -b wt-branch
run "$work_dir/wt tree"
assert "worktree" '[ "$out" = added ] && [ "$(exclude_count "$repo")" = 1 ] && git -C "$work_dir/wt tree" check-ignore -q handover'

new_repo; rm -rf "$repo/.git/info"
run "$repo"
assert "no info folder" '[ "$out" = added ] && [ -f "$repo/.git/info/exclude" ]'

new_repo; mkdir -p "$repo/src/handover"; echo x > "$repo/src/handover/keep.txt"
run "$repo"
assert "anchored entry" '[ "$out" = added ] && git -C "$repo" check-ignore -q handover && ! git -C "$repo" check-ignore -q src/handover/keep.txt'

mkdir "$work_dir/plain"
run "$work_dir/plain"
assert "not a repository" '[ "$rc" = 2 ]'
finish
