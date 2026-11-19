#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v playwright-cli >/dev/null 2>&1; then
  echo "SKIP test_check_page_width: playwright-cli not installed"
  exit 0
fi
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><body style="max-width:760px"><h1>narrow</h1><p>text</p>' > "$work_dir/narrow.html"
echo '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><body><table style="width:900px"><tr><td>wide</td></tr></table>' > "$work_dir/wide.html"

narrow_exit=0
narrow_output="$(bash "$repo_root/scripts/check-page-width.sh" "$work_dir/narrow.html" 375 2>&1)" || narrow_exit=$?
assert "narrow page exits 0" '[ "$narrow_exit" -eq 0 ]'
assert "narrow page prints a width of 375 or less" '[ "${narrow_output##*$'"'"'\n'"'"'}" -le 375 ]'

wide_exit=0
wide_output="$(bash "$repo_root/scripts/check-page-width.sh" "$work_dir/wide.html" 2>&1)" || wide_exit=$?
assert "wide page exits 1" '[ "$wide_exit" -eq 1 ]'
assert "wide page prints a width above 375" '[ "$wide_output" -gt 375 ]'

missing_exit=0
bash "$repo_root/scripts/check-page-width.sh" "$work_dir/none.html" >/dev/null 2>&1 || missing_exit=$?
assert "missing page exits 2" '[ "$missing_exit" -eq 2 ]'
nopw_exit=0
nopw_output="$(PATH="/usr/bin:/bin" /bin/bash "$repo_root/scripts/check-page-width.sh" "$work_dir/narrow.html" 2>&1)" || nopw_exit=$?
assert "missing playwright-cli exits 2 and names the install line" '[ "$nopw_exit" -eq 2 ] && [[ "$nopw_output" == *"npm i -g @playwright/cli@0.1.24"* ]]'
finish
