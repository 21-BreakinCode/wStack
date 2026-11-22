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
# Contract drift in run-retro
retro_skill="$repo_root/skills/run-retro/SKILL.md"
assert "run-retro: step 7 hands over to Contract drift, step 8 asks after it" '[ "$(grep -n "^7\. .*Contract drift" "$retro_skill" | head -1 | cut -d: -f1)" -lt "$(grep -n "^## Contract drift" "$retro_skill" | cut -d: -f1)" ] && [ "$(grep -n "^## Contract drift" "$retro_skill" | cut -d: -f1)" -lt "$(grep -n "^## After the user picks" "$retro_skill" | cut -d: -f1)" ]'
assert "run-retro drift skips a non-git directory, an unmapped repository, and a missing contract" 'grep -qF "Contract: not a git project" "$retro_skill" && grep -qF "Contract: not mapped" "$retro_skill" && grep -qF "/wstack:init-service" "$retro_skill"'
assert "run-retro drift uses contract-path.sh and contract-check.sh" 'grep -qF "contract-path.sh" "$retro_skill" && grep -qF "contract-check.sh" "$retro_skill"'
assert "run-retro drift fetches, and fast-forwards only on a clean base branch" 'grep -qF "fetch origin" "$retro_skill" && grep -qF "merge --ff-only" "$retro_skill" && grep -qF "status --porcelain" "$retro_skill" && ! grep -qE "git (-C [^ ]+ )?(rebase|stash|pull)( |$)" "$retro_skill"'
assert "run-retro drift dispatches contract-reader and writes the patch and before copy in retro_dir" 'grep -qF "wstack:contract-reader" "$retro_skill" && grep -qF "\$retro_name.contract-patch.md" "$retro_skill" && grep -qF "\$retro_name.contract-before.md" "$retro_skill"'
assert "run-retro drift applies under the lock pattern with a write-once copy and --section" 'grep -qF "contract-edit.sh\" lock" "$retro_skill" && grep -qF "trap '"'"'bash \"\$scripts/contract-edit.sh\" unlock" "$retro_skill" && grep -qF "[ -f \"\$retro_dir/\$retro_name.contract-before.md\" ] || cp" "$retro_skill" && grep -qF -- "--section" "$retro_skill"'
assert "run-retro drift writes a Contract section into the retro file" 'grep -qF "## Contract" "$retro_skill" && grep -qF "the undo" "$retro_skill"'
assert "run-retro drift runs set-verified only if every stale section was applied" 'grep -qF "If every stale section was applied, run \`set-verified\`" "$retro_skill" && grep -qF "set-verified" "$retro_skill"'
assert "run-retro step 8 asks for proposals and contract sections in one question" 'grep -qF "contract sections" "$retro_skill" && grep -qF "\`all\`" "$retro_skill" && grep -qF "\`none\`" "$retro_skill"'
assert "run-retro drift handles no patch, no stale section, empty base branch, detached HEAD, and a missing answer" 'grep -qF "Contract: stale, no patch" "$retro_skill" && grep -qF "no section to update" "$retro_skill" && grep -qF "If \`base_branch\` is empty" "$retro_skill" && grep -qF "branch --show-current" "$retro_skill" && grep -qF "means \`none\`" "$retro_skill" && grep -qF "Drop any chosen name that has no such block" "$retro_skill" && grep -qF "Skip step 4. In step 5, write \`Tasks read: 0\` and use \`No proposals.\`" "$retro_skill" && ! grep -qF "no task folder is in the last 7 days. Stop" "$retro_skill"'
assert "run-retro: every skip adds a Contract status line to the retro file" 'grep -qF "Every outcome has a status line that starts with \`Contract:\`" "$retro_skill" && grep -qF "Contract: missing" "$retro_skill"'
assert "no obsidian-kit names in skills" '! grep -rqE "obsidian-kit:|OBSIDIAN_KIT_|resolve_via_handover" "$repo_root/skills"'
for s in init-org init-service create-handover wrap-up-handovers; do assert "$s reads vault_path" 'grep -qF "\${user_config.vault_path}" "$repo_root/skills/$s/SKILL.md"'; done
assert "init-service sets REPO_ROOT before the mapped skip" '[ "$(grep -n "REPO_ROOT=" "$repo_root/skills/init-service/SKILL.md" | head -1 | cut -d: -f1)" -lt "$(grep -n "skip to Phase 5" "$repo_root/skills/init-service/SKILL.md" | head -1 | cut -d: -f1)" ]'
assert "init-service uses the exclude script" 'grep -q "scripts/handover/ensure-exclude.sh" "$repo_root/skills/init-service/SKILL.md"'
# A3-8: a later Verify round replaces the evidence lines
assert "verify clears old evidence lines first" 'grep -q "First delete every line under .## Evidence." "$repo_root/skills/start-task/references/verify.md"'
# Controller ruling: outside herdr a code task is handed to the user, not run in the main checkout session
assert "start-task exit 3 hands a code task to a new session in the worktree" 'grep -q "cd \"<workspace_cwd>\" && claude \"/wstack:start-task --task <task_id>\"" "$repo_root/skills/start-task/SKILL.md" && grep -q "do not run work mode in this session" "$repo_root/skills/start-task/SKILL.md"'
finish
