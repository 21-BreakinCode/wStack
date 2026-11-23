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
assert "a passing test line with skip in its name is not a skip" 'printf "  PASS  task with retro_read is skipped\nPASS: skip-cache.sh\nok 3 - skips the cache\n  \342\234\223 skips empty input (5 ms)\n" >"$log"; bash "$script" "$log" >"$out" && [ ! -s "$out" ]'
assert "a TAP ok line with a skip directive is a skip" 'printf "ok 4 # SKIP no network\n" >"$log"; ! bash "$script" "$log" >"$out" && grep -q "ok 4 # SKIP" "$out"'
assert "a FAIL line with skip in its name is still found" 'printf "  FAIL  task with retro_read is skipped\n" >"$log"; ! bash "$script" "$log" >/dev/null'
assert "zero counts are not a skip" 'printf "Passed: 3  Skipped: 0  Failed: 0\n5 passed, 0 skipped\nOK (skipped=0)\n" >"$log"; bash "$script" "$log" >"$out" && [ ! -s "$out" ]'
assert "a count that ends in 0 is a skip" 'printf "10 skipped\n" >"$log"; ! bash "$script" "$log" >/dev/null'
assert "a real skip next to a zero count is found" 'printf "3 passed, 1 skipped, 0 xfailed\n" >"$log"; ! bash "$script" "$log" >"$out" && grep -q "1 skipped" "$out"'
assert "an unreadable file exits 2" 'printf "SKIP x\n" >"$work/locked.log"; chmod 000 "$work/locked.log"; rc=0; bash "$script" "$work/locked.log" >/dev/null 2>&1 || rc=$?; chmod 600 "$work/locked.log"; [ "$rc" -eq 2 ]'
assert "a folder exits 2" 'rc=0; bash "$script" "$work" >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ]'
finish
