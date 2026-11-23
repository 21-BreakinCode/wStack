#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/facts-add.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
dir="$root/Services/app"
mkdir -p "$dir"
printf -- '---\napp_name: app\n---\n' > "$dir/app.md"
first_line="$(bash "$script" "$dir/app.facts.md" fact 2026-11-30 "task-1" "Run the full suite")"
assert "first fact makes the file as F1" 'grep -qx -- "- F1 Run the full suite" "$dir/app.facts.md" && grep -qx "service: app" "$dir/app.facts.md"'
assert "it prints the first written line" '[ "$first_line" = "- F1 Run the full suite" ]'
assert "the evidence line is written" 'grep -qx "  Confirmed 2026-11-30. Evidence: task-1" "$dir/app.facts.md"'
bash "$script" "$dir/app.facts.md" fact 2026-11-30 task-2 "Ask before a migration" >/dev/null
assert "second fact is F2 under Facts" 'awk "/^## Facts/{f=1} /^## Not facts/{f=0} f" "$dir/app.facts.md" | grep -q -- "- F2 "'
bash "$script" "$dir/app.facts.md" not 2026-11-30 "" "Never use tabs" >/dev/null
assert "not goes under Not facts with the date" 'awk "/^## Not facts/{f=1} f" "$dir/app.facts.md" | grep -qx "  Rejected 2026-11-30."'
assert "not text is under Not facts" 'awk "/^## Not facts/{f=1} f" "$dir/app.facts.md" | grep -qx -- "- Never use tabs"'
bash "$script" "$dir/app.facts.md" fact 2026-11-30 task-3 'Use `jq` # not sed' >/dev/null
assert "markdown text is kept as given" 'grep -qF -- "- F3 Use \`jq\` # not sed" "$dir/app.facts.md"'
assert "a fact after a not still lands under Facts" 'awk "/^## Facts/{f=1} /^## Not facts/{f=0} f" "$dir/app.facts.md" | grep -q -- "- F3 "'
assert "the lock is released" '[ ! -e "$dir/app.md.lock" ]'
assert "a newline in the text exits 1" '! bash "$script" "$dir/app.facts.md" fact 2026-11-30 t1 "$(printf "a\nb")" 2>/dev/null'
assert "a newline in the evidence exits 1" '! bash "$script" "$dir/app.facts.md" fact 2026-11-30 "$(printf "a\nb")" text 2>/dev/null'
rc=0; bash "$script" "$dir/app.facts.md" fact 2026-11-30 t1 "$(printf "a\nb")" 2>/dev/null || rc=$?
assert "newline exit code is 1" '[ "$rc" = 1 ]'
rc=0; bash "$script" "$dir/app.facts.md" fact 2026-11-30 t1 "" 2>/dev/null || rc=$?
assert "empty text exits 1" '[ "$rc" = 1 ]'
rc=0; bash "$script" "$dir/app.facts.md" maybe 2026-11-30 t1 x 2>/dev/null || rc=$?
assert "a bad kind exits 1" '[ "$rc" = 1 ]'
rc=0; bash "$script" "$dir/app.facts.md" fact 2026-13-xx t1 x 2>/dev/null || rc=$?
assert "a bad date exits 1" '[ "$rc" = 1 ]'
assert "bad input wrote nothing" '[ "$(grep -c "^- " "$dir/app.facts.md")" = 4 ]'
rc=0; bash "$script" "$root/nowhere/app.facts.md" fact 2026-11-30 t1 x 2>/dev/null || rc=$?
assert "a missing folder exits 2" '[ "$rc" = 2 ]'
mkdir "$dir/app.md.lock"
rc_lock=0; bash "$script" "$dir/app.facts.md" fact 2026-11-30 t1 x 2>/dev/null || rc_lock=$?
assert "a busy lock exits 2" '[ "$rc_lock" = 2 ]'
assert "a busy lock stays in place" '[ -d "$dir/app.md.lock" ]'
bad_dir="$root/Services/bad"
mkdir -p "$bad_dir"
printf -- '---\napp_name: bad\n---\n' > "$bad_dir/bad.md"
printf -- '---\nservice: bad\n---\n\n## Facts\n' > "$bad_dir/bad.facts.md"
cp "$bad_dir/bad.facts.md" "$root/before-no-not"
rc=0; out="$(bash "$script" "$bad_dir/bad.facts.md" not 2026-11-30 "" x 2>/dev/null)" || rc=$?
assert "a missing Not facts heading exits 3 with no stdout" '[ "$rc" = 3 ] && [ -z "$out" ]'
assert "the file is unchanged after a missing heading" 'cmp -s "$bad_dir/bad.facts.md" "$root/before-no-not"'
printf -- '---\nservice: bad\n---\n\n## Facts \n\n## Not facts\n' > "$bad_dir/bad.facts.md"
cp "$bad_dir/bad.facts.md" "$root/before-space"
rc=0; bash "$script" "$bad_dir/bad.facts.md" fact 2026-11-30 t1 x >/dev/null 2>&1 || rc=$?
assert "a Facts heading with a trailing space exits 3" '[ "$rc" = 3 ] && cmp -s "$bad_dir/bad.facts.md" "$root/before-space"'
assert "no temp file or lock is left" '[ "$(ls -A "$bad_dir" | tr "\n" " ")" = "bad.facts.md bad.md " ]'
finish
