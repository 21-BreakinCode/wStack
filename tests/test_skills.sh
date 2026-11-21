#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"

expected_skills="build-review-page capture-evidence deliver-task run-retro start-task"
actual_skills="$(ls "$repo_root/skills" | sort | tr '\n' ' ' | sed 's/ $//')"
assert "skill folders" '[ "$actual_skills" = "$expected_skills" ]'

for skill_dir in "$repo_root"/skills/*/; do
  skill="$(basename "$skill_dir")"
  assert "$skill: name matches folder" '[ "$(sed -n "s/^name: //p" "$skill_dir/SKILL.md")" = "$skill" ]'
done

missing_refs=0
for ref in $(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$repo_root/skills" "$repo_root/agents" "$repo_root/hooks" | sort -u); do
  ref="${ref%.}"
  [ -e "$repo_root/${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}" ] || { echo "missing: $ref"; missing_refs=$((missing_refs + 1)); }
done
assert "every CLAUDE_PLUGIN_ROOT path exists" '[ "$missing_refs" -eq 0 ]'

old_names='/wstack:retro([^-a-z]|$)|the (deliver|evidence|review-page) skill|skills/(retro|evidence|deliver|review-page)/'
old_status=0
old_hits="$(git -C "$repo_root" grep -lE "$old_names" -- . ':!CHANGELOG.md' ':!docs/decisions.md' ':!docs/superpowers' ':!tests/test_skills.sh')" || old_status=$?
assert "old-name search ran" '[ "$old_status" -le 1 ]'
assert "no old skill names in current files" '[ -z "$old_hits" ]'
finish
