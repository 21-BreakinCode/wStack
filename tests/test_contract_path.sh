#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-path.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
source "$(bash "$repo_root/tests/fixtures/contract/setup.sh" "$work_dir/world")"

out="$(bash "$script" --vault "$VAULT" "$REPO")"
assert "repo maps to the contract" '[ "$out" = "$CONTRACT" ]'

worktree="$work_dir/world/.herdr/worktrees/svc/feat"
git -C "$REPO" worktree add -q -b feat "$worktree"
out="$(bash "$script" --vault "$VAULT" "$worktree")"
assert "worktree maps to the contract" '[ "$out" = "$CONTRACT" ]'

other="$work_dir/other"
git init -q "$other"
set +e; bash "$script" --vault "$VAULT" "$other" >/dev/null 2>&1; rc=$?; set -e
assert "unmapped repo exits 1" '[ $rc = 1 ]'

set +e; bash "$script" "$REPO" >/dev/null 2>&1; rc=$?; set -e
assert "bad usage exits 2" '[ $rc = 2 ]'
finish
