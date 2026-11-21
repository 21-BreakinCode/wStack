#!/usr/bin/env bash
# Sourced, not run. Provides main_checkout.
set -euo pipefail

# main_checkout <dir>: print the main working tree of the repository that holds <dir>.
# Works inside a linked worktree too. Returns 1 when <dir> is not in a git work tree.
# shortcut: compares physical git paths with logical $HOME paths; breaks if $HOME or ~/Projects is a symlink, then resolve both with cd -P.
main_checkout() {
  local dir="$1" common_dir
  common_dir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  dirname "$common_dir"
}
