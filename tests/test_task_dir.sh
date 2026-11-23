#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/task-dir.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
vault="$work_dir/My Vault"
mkdir -p "$vault/Tasks/2026-11-20-top" "$vault/Tasks/_archive/2026-W45/2026-11-01-old" \
  "$vault/Tasks/2026-11-02-both" "$vault/Tasks/_archive/2026-W45/2026-11-02-both"

assert "top-level task is found" '[ "$(task_dir_of "$vault" Tasks 2026-11-20-top)" = "$vault/Tasks/2026-11-20-top" ]'
assert "archived task is found" '[ "$(task_dir_of "$vault" Tasks 2026-11-01-old)" = "$vault/Tasks/_archive/2026-W45/2026-11-01-old" ]'
assert "top level wins over the archive" '[ "$(task_dir_of "$vault" Tasks 2026-11-02-both)" = "$vault/Tasks/2026-11-02-both" ]'
assert "a missing task returns 1 and prints nothing" '! task_dir_of "$vault" Tasks 2026-11-03-none && [ -z "$(task_dir_of "$vault" Tasks 2026-11-03-none || true)" ]'
finish
