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

# Skill blocks run in the user's shell. In zsh a glob with no match is an error, so test the helper there too.
if command -v zsh >/dev/null 2>&1; then
  in_zsh() {  # <task id>: the output of task_dir_of in zsh, then "rc=<return code>"
    zsh -c 'source "$1"; rc=0; task_dir_of "$2" Tasks "$3" || rc=$?; echo "rc=$rc"' zsh "$repo_root/scripts/lib/task-dir.sh" "$vault" "$1" 2>&1
  }
  assert "zsh: top-level task is found" '[ "$(in_zsh 2026-11-20-top)" = "$vault/Tasks/2026-11-20-top
rc=0" ]'
  assert "zsh: archived task is found" '[ "$(in_zsh 2026-11-01-old)" = "$vault/Tasks/_archive/2026-W45/2026-11-01-old
rc=0" ]'
  assert "zsh: a missing task returns 1, prints nothing, and the shell goes on" '[ "$(in_zsh 2026-11-03-none)" = "rc=1" ]'
else
  echo "  info: zsh not found, zsh cases not run"
fi
finish
