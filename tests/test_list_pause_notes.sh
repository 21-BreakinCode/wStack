#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/list-pause-notes.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"
pauses="$HOME/.wstack/pauses"

assert "no pauses folder prints nothing" '[ -z "$(bash "$script" /w/app)" ]'
mkdir -p "$pauses"
printf -- '- folder: /w/app\n' >"$pauses/app-20261122-090000.md"
printf -- '- folder: /w/app\n' >"$pauses/app-20261122-180000.md"
printf -- '- folder: /w/app\n' >"$pauses/app-20261121-230000.md.resumed-20261122-100000.md"
printf -- '- folder: /w/other\n' >"$pauses/other-20261123-100000.md"
printf -- '- folder: /w/app\n' >"$pauses/app-notes.md"
out="$(bash "$script" /w/app)"
assert "two notes listed" '[ "$(wc -l <<<"$out" | tr -d " ")" = 2 ]'
assert "newest first" '[ "$(sed -n 1p <<<"$out")" = "$pauses/app-20261122-180000.md" ]'
assert "older second" '[ "$(sed -n 2p <<<"$out")" = "$pauses/app-20261122-090000.md" ]'
assert "other folder excluded" '! grep -q other <<<"$out"'
rc=0; bash "$script" relative 2>/dev/null || rc=$?
assert "relative folder rejected" '[ "$rc" = 2 ]'
finish
