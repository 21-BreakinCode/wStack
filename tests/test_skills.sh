#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"

expected_skills="build-review-page capture-evidence create-handover deliver-task init-org init-service run-retro start-task wrap-up-handovers"
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
for skill in create-handover init-org init-service run-retro start-task wrap-up-handovers; do
  assert "$skill is user-invoked" 'grep -qx "disable-model-invocation: true" "$repo_root/skills/$skill/SKILL.md"'
done
for skill in build-review-page capture-evidence deliver-task; do
  assert "$skill is a helper" 'grep -qx "user-invocable: false" "$repo_root/skills/$skill/SKILL.md"'
done
assert "run-retro names the -2 rule for a second retro in a week" 'grep -qF "write \`\$week-2\` instead, then \`\$week-3\`" "$repo_root/skills/run-retro/SKILL.md"'
assert "run-retro uses retro_name in every retro file path" '! grep -qF "\$retro_dir/\$week" "$repo_root/skills/run-retro/SKILL.md"'
assert "no obsidian-kit names in skills" '! grep -rqE "obsidian-kit:|OBSIDIAN_KIT_|resolve_via_handover" "$repo_root/skills"'
for s in init-org init-service create-handover wrap-up-handovers; do assert "$s reads vault_path" 'grep -qF "\${user_config.vault_path}" "$repo_root/skills/$s/SKILL.md"'; done
assert "init-service sets REPO_ROOT before the mapped skip" '[ "$(grep -n "REPO_ROOT=" "$repo_root/skills/init-service/SKILL.md" | head -1 | cut -d: -f1)" -lt "$(grep -n "skip to Phase 5" "$repo_root/skills/init-service/SKILL.md" | head -1 | cut -d: -f1)" ]'
assert "init-service uses the exclude script" 'grep -q "scripts/handover/ensure-exclude.sh" "$repo_root/skills/init-service/SKILL.md"'
# A3-8: a later Verify round replaces the evidence lines
assert "verify clears evidence lines on a later round" 'grep -q "first delete every line under .## Evidence." "$repo_root/skills/start-task/references/verify.md"'
finish
