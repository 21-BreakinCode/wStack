#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/find-stale-refs.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
repo="$work/repo"
clean="$work/clean"
git_in() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
make_base() {
  mkdir -p "$1/a" "$1/docs" "$1/evals"
  git init -q -b main "$1"
  printf 'old page\n' >"$1/a/old.md"
  printf 'see a/old.md\n' >"$1/docs/x.md"
  printf 'moved a/old.md\n' >"$1/CHANGELOG.md"
  printf 'one\nuses spec.html here\n' >"$1/evals/g.md"
  git_in "$1" add -A
  git_in "$1" commit -q -m base
  git_in "$1" tag base
}
make_base "$repo"
git_in "$repo" mv a/old.md a/new.md
git_in "$repo" commit -q -m rename
make_base "$clean"
printf 'more\n' >"$clean/new.txt"
git_in "$clean" add -A
git_in "$clean" commit -q -m more
assert "a renamed path still named in docs is a hit" '[ "$(bash "$script" --repo "$repo" --base base)" = "docs/x.md:1: a/old.md" ]'
assert "a hit exits 1" '! bash "$script" --repo "$repo" --base base >/dev/null'
assert "CHANGELOG.md is skipped" '! bash "$script" --repo "$repo" --base base | grep -q CHANGELOG'
assert "an --old text is searched too" '{ bash "$script" --repo "$repo" --base base --old "spec.html" || true; } | grep -q "evals/g.md:2: spec.html"'
assert "a clean repo exits 0" 'bash "$script" --repo "$clean" --base base >/dev/null'
assert "a bad base exits 2" 'bash "$script" --repo "$repo" --base nope >/dev/null 2>&1; [ $? -eq 2 ]'
assert "a folder that is not a git work tree exits 2" 'bash "$script" --repo "$work" --base base >/dev/null 2>&1; [ $? -eq 2 ]'
finish
