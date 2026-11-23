#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/find-test-skips.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
log="$work/test.log"
out="$work/out.txt"
assert "a SKIP line is found" 'printf "PASS a\nSKIP page cases: x\n" >"$log"; ! bash "$script" "$log" >"$out" && grep -q "SKIP page cases" "$out"'
assert "skipped tests are found" 'printf "3 passed, 2 skipped\n" >"$log"; ! bash "$script" "$log" >/dev/null'
assert "collected 0 items is found" 'printf "collected 0 items\n" >"$log"; ! bash "$script" "$log" >/dev/null'
assert "a clean log exits 0" 'printf "Passed: 3  Failed: 0\n" >"$log"; bash "$script" "$log" >/dev/null'
assert "a word that only starts with skip is not a skip" 'printf "skipper ok\n" >"$log"; bash "$script" "$log" >/dev/null'
assert "a missing file exits 2" 'bash "$script" "$work/none.log" 2>/dev/null; [ $? -eq 2 ]'
finish
