#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"

expected_skills="build-review-page capture-evidence create-handover deliver-task init-org init-service pause-task run-retro start-task wrap-up-handovers"
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
for skill in create-handover init-org init-service pause-task run-retro start-task wrap-up-handovers; do
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
assert "verify clears old evidence lines first" 'grep -q "First delete every line under .## Evidence." "$repo_root/skills/start-task/references/verify.md"'
# Controller ruling: outside herdr a code task is handed to the user, not run in the main checkout session
assert "start-task exit 3 hands a code task to a new session in the worktree" 'grep -q "cd \"<workspace_cwd>\" && claude \"/wstack:start-task --task <task_id>\"" "$repo_root/skills/start-task/SKILL.md" && grep -q "do not run work mode in this session" "$repo_root/skills/start-task/SKILL.md"'
pause_skill="$repo_root/skills/pause-task/SKILL.md"
start_skill="$repo_root/skills/start-task/SKILL.md"
assert "pause-task stops background work with TaskStop and checks pgrep" 'grep -q "TaskStop" "$pause_skill" && grep -q "pgrep" "$pause_skill"'
assert "pause-task writes pause.md with the listed fields" 'grep -q "pause.md" "$pause_skill" && grep -q "git HEAD" "$pause_skill" && grep -q "uncommitted paths" "$pause_skill" && grep -q "next step" "$pause_skill"'
assert "pause-task sets paused and paused_from" 'grep -qF "status paused" "$pause_skill" && grep -q "paused_from" "$pause_skill"'
assert "pause-task refuses a task that is already paused" 'grep -qF "If status is \`paused\`, tell the user the task is already paused and stop" "$pause_skill"'
assert "pause-task tells the user the resume command" 'grep -qF "/wstack:start-task --task <task_id>" "$pause_skill"'
assert "work mode has a paused row that reads pause.md" 'grep -qF "| \`paused\` |" "$start_skill" && grep -q "pause.md" "$start_skill"'
assert "work mode restores the status and renames the note to pause-<time>.md" 'grep -q "paused_from" "$start_skill" && grep -qF "pause-<time>.md" "$start_skill"'
finish
