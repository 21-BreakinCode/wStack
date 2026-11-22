#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/list-open-tasks.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
unset HERDR_ENV  # never ask the live herdr session
vault="$work_dir/My Vault"; mkdir -p "$vault"
for entry in "b-two:executing" "a-one:delivered" "c-three:waiting-user" "d-four:paused"; do
  slug="${entry%%:*}"
  folder="$(bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug "$slug" --date 2026-11-18 | tail -n 1)"
  fm_set "$folder/spec.md" status "${entry#*:}"
  fm_set "$folder/spec.md" workspace_cwd "/w/$slug"
done
out="$(bash "$script" --vault "$vault" --tasks-dir T)"
assert "three lines" '[ "$(wc -l <<<"$out" | tr -d " ")" = 3 ]'
assert "sorted, tsv" '[ "$(sed -n 1p <<<"$out")" = "$(printf "2026-11-18-b-two\texecuting\t/w/b-two\t%s" "$vault/T/2026-11-18-b-two")" ]'
second_line="$(sed -n 2p <<<"$out")"
assert "second line" '[ "${second_line%%$(printf "\t")*}" = 2026-11-18-c-three ]'
assert "paused task is listed as open" '[ "$(sed -n 3p <<<"$out" | cut -f1,2)" = "$(printf "2026-11-18-d-four\tpaused")" ]'
finish
