#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/handover/ensure-symlink.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
target="$work_dir/my target"; mkdir -p "$target"
other="$work_dir/other"; mkdir -p "$other"
link="$work_dir/link"
run() { set +e; bash "$script" "$@" >/dev/null 2>&1; rc=$?; set -e; }

run "$link" "$target"
assert "creates a new link" '[ "$rc" = 0 ] && [ "$(readlink "$link")" = "$target" ]'
run "$link" "$target"
assert "correct link exits 0" '[ "$rc" = 0 ]'
rm "$link"; mkdir "$link"
run "$link" "$target"
assert "empty folder replaced" '[ "$rc" = 0 ] && [ -L "$link" ]'
rm "$link"; mkdir "$link"; touch "$link/file"
run "$link" "$target"
assert "non-empty folder exits 1" '[ "$rc" = 1 ] && [ ! -L "$link" ]'
rm -r "$link"
run "$link" "$work_dir/missing"
assert "missing target exits 3" '[ "$rc" = 3 ]'
ln -s "$other" "$link"
run "$link" "$target"
assert "other target exits 4" '[ "$rc" = 4 ] && [ "$(readlink "$link")" = "$other" ]'
run "$link" "$target" force
assert "force repoints" '[ "$rc" = 0 ] && [ "$(readlink "$link")" = "$target" ]'
finish
