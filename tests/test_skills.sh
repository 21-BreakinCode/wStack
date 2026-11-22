#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"

expected_skills="build-review-page capture-evidence create-handover deliver-task init-org init-service pause-work resume-work run-retro start-task wrap-up-handovers"
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
for skill in create-handover init-org init-service pause-work resume-work run-retro start-task wrap-up-handovers; do
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
for s in init-org init-service create-handover wrap-up-handovers pause-work resume-work; do assert "$s reads vault_path" 'grep -qF "\${user_config.vault_path}" "$repo_root/skills/$s/SKILL.md"'; done
assert "init-service sets REPO_ROOT before the mapped skip" '[ "$(grep -n "REPO_ROOT=" "$repo_root/skills/init-service/SKILL.md" | head -1 | cut -d: -f1)" -lt "$(grep -n "skip to Phase 5" "$repo_root/skills/init-service/SKILL.md" | head -1 | cut -d: -f1)" ]'
assert "init-service uses the exclude script" 'grep -q "scripts/handover/ensure-exclude.sh" "$repo_root/skills/init-service/SKILL.md"'
# A3-8: a later Verify round replaces the evidence lines
assert "verify clears old evidence lines first" 'grep -q "First delete every line under .## Evidence." "$repo_root/skills/start-task/references/verify.md"'
# Controller ruling: outside herdr a code task is handed to the user, not run in the main checkout session
assert "start-task exit 3 hands a code task to a new session in the worktree" 'grep -q "cd \"<workspace_cwd>\" && claude \"/wstack:start-task --task <task_id>\"" "$repo_root/skills/start-task/SKILL.md" && grep -q "do not run work mode in this session" "$repo_root/skills/start-task/SKILL.md"'
assert "start-task resume mode hands a code task to a new session in the worktree outside herdr" 'awk "/^## Resume mode/ {on=1} on" "$repo_root/skills/start-task/SKILL.md" | grep -q "For a \`code\` task, tell the user to run \`cd \"<workspace_cwd>\" && claude \"/wstack:start-task --task <task_id>\"\`, and stop"'
pause_skill="$repo_root/skills/pause-work/SKILL.md"
resume_skill="$repo_root/skills/resume-work/SKILL.md"
start_skill="$repo_root/skills/start-task/SKILL.md"
assert "pause-work writes the note before it stops anything" '[ "$(grep -n "^## Step 1: write the resume note first" "$pause_skill" | cut -d: -f1)" -lt "$(grep -n "^## Step 2: stop background work" "$pause_skill" | cut -d: -f1)" ]'
assert "pause-work stops agents and shells with TaskStop" 'grep -q "TaskStop" "$pause_skill" && grep -q "ListAgents" "$pause_skill"'
assert "pause-work stops only processes traced to the session and lists the rest" 'grep -qF "Stop each \`traced\` process" "$pause_skill" && grep -qF "grep -F --" "$pause_skill" && grep -qF "still running" "$pause_skill"'
assert "pause-work names both note locations" 'grep -qF "\$task_dir/pause.md" "$pause_skill" && grep -qF "~/.wstack/pauses/<current folder name>-<YYYYMMDD-HHMMSS>.md" "$pause_skill"'
assert "pause-work note holds the listed fields" 'for f in "- goal:" "- done:" "- in progress:" "- next steps:" "- git state:" "- read first on resume:" "- folder:" "status before the pause"; do grep -qF -- "$f" "$pause_skill" || exit 1; done'
assert "pause-work sets paused and paused_from for a task" 'grep -qF "status paused" "$pause_skill" && grep -q "paused_from" "$pause_skill"'
assert "pause-work refuses a task that is already paused" 'grep -qF "If status is \`paused\`, tell the user the task is already paused." "$pause_skill"'
assert "pause-work tells the user the resume command" 'grep -qF "/wstack:resume-work" "$pause_skill" && grep -qF "/wstack:start-task --task <task_id>" "$pause_skill"'
assert "resume-work compares the git state and never resets" 'grep -q "Report every difference" "$resume_skill" && grep -qF "Do not discard, reset, or stash anything." "$resume_skill"'
assert "resume-work looks up a session note by folder, newest first" 'grep -q "list-pause-notes.sh" "$resume_skill" && grep -q "newest first" "$resume_skill"'
assert "resume-work renames the task note to pause-<time>.md and restores the status" 'grep -qF "pause-<time>.md" "$resume_skill" && grep -q "paused_from" "$resume_skill"'
assert "resume-work renames a session note to .resumed-<time>.md" 'grep -qF "<name>.resumed-<time>.md" "$resume_skill"'
assert "work mode paused row reads the resume-work file, since a model cannot call a user-invoked skill" 'grep -qF "| \`paused\` | Read \`\${CLAUDE_PLUGIN_ROOT}/skills/resume-work/SKILL.md\`" "$start_skill"'
assert "resume-work hands a task note off to start-task in its workspace and never follows work mode itself" 'grep -qF "6. For a task note, hand the task off and stop." "$resume_skill" && grep -qF "Tell the user to run \`cd \"<workspace_cwd>\" && claude \"/wstack:start-task --task <task_id>\"\`" "$resume_skill" && ! grep -qF "follow \"Work mode\"" "$resume_skill"'
assert "pause-work: a path match alone is not a trace, and rules (a) and (b) exist" 'grep -qF "A path match alone is not a trace" "$pause_skill" && grep -qF "ps -o ppid= -p" "$pause_skill" && grep -qF "(b) This session started it with a named Bash call" "$pause_skill"'
assert "pause-work: the trace skips the session process and never stops its MCP or LSP servers" 'grep -qxF "     [ \"\$pid\" = \"\$session_pid\" ] && continue" "$pause_skill" && grep -qF "Never stop a direct child of \`\$session_pid\` that is not a shell. It is an MCP or LSP server." "$pause_skill"'
assert "pause-work: a process with parent 1 goes by rule (b), with lsof for its folder, and an unknown one is asked" 'grep -qF "Judge a process with parent 1 by rule (b)." "$pause_skill" && grep -qF "lsof -a -p <pid> -d cwd -Fn" "$pause_skill" && grep -qF "List it and ask the user." "$pause_skill"'
assert "pause-work: playwright-cli daemons are found by cliDaemon.js and closed, not killed" 'grep -qF "ps -axo pid=,command= | grep -F '"'"'cliDaemon.js '"'"'" "$pause_skill" && grep -qF "The word after \`cliDaemon.js\` is the session name." "$pause_skill" && grep -qF "\`wstack-width-<pid>\`" "$pause_skill" && grep -qF "When \`ps -p <pid>\` prints nothing" "$pause_skill" && grep -qF "playwright-cli -s <session> close\`, not with \`kill\`" "$pause_skill"'
assert "pause-work points to /tasks when ids are lost" 'grep -qF "/tasks" "$pause_skill"'
assert "pause-work asks before it takes over a task it did not run" 'grep -qF "Pause task <id>, or this session only?" "$pause_skill"'
assert "pause-work still stops work when it refuses a task" 'grep -qF "still run \"Step 2\"" "$pause_skill"'
assert "pause-work asks for the vault with --task and no vault" 'grep -qF "ask the user for the vault path and stop" "$pause_skill"'
assert "pause-work re-reads the git state after the stop" 'grep -qF "Read the git state again" "$pause_skill"'
assert "resume-work asks when a task note and session notes both exist" 'grep -qF "If both kinds exist, list them and ask" "$resume_skill"'
assert "resume-work restores only a paused status, stops on a failed write, and clears paused_from" 'grep -qxF "  if [ \"\$current_status\" = paused ]; then" "$resume_skill" && grep -qxF "  set -e" "$resume_skill" && grep -qF "paused_from \"\"" "$resume_skill"'
assert "resume-work and pause-work pick among several open tasks of the folder" 'grep -qF "If there is more than one task note, list them and ask the user which one to resume." "$resume_skill" && grep -qF "If you keep more than one, ask the user which task to pause" "$pause_skill" && ! grep -qF "exactly one \`workspace_cwd\`" "$resume_skill" "$pause_skill"'
assert "pause-work gives the resume command with its folder" 'grep -qF "\`cd \"<folder>\" && claude \"/wstack:resume-work <note path>\"\`" "$pause_skill"'
assert "start-task resume mode tells the user to run work mode for a paused task" 'grep -qF "For a \`paused\` task, also tell the user to run \`/wstack:start-task --task <task_id>\` in that session." "$start_skill"'
assert "resume-work asks about a missing path" 'grep -qF "does not exist" "$resume_skill"'
assert "run-log line types include pause" 'grep -qF "<step|retry|stop|pause>" "$repo_root/skills/start-task/references/execute.md" && grep -qF "<step|retry|stop|pause>" "$repo_root/agents/retro-analyst.md"'
# Polish round
assert "run-retro: D2 exit 2 and D4 exit 2 or 3 write a Contract status line" 'grep -qF "Contract: path check failed: <first stderr line>" "$retro_skill" && grep -qF "Contract: check failed: <cause>" "$retro_skill"'
assert "run-retro: the undo deletes each applied section that the before copy lacks, not each warned name" 'grep -qF "the new-section command for each applied section that has no \`## <name>\` line in the before copy" "$retro_skill" && ! grep -qF "for each warned name" "$retro_skill"'
assert "run-retro: pending items are resolved by the deliver-task file before D4" '[ "$(grep -n "Then resolve the pending items of the contract before D4" "$retro_skill" | head -1 | cut -d: -f1)" -lt "$(grep -n "^D4\." "$retro_skill" | cut -d: -f1)" ] && grep -qF "Read \"Pending items\" in \`\${CLAUDE_PLUGIN_ROOT}/skills/deliver-task/SKILL.md\`" "$retro_skill" && grep -qF "go on to the pending items below" "$retro_skill"'
assert "run-retro: step 7 and 8 ask about sections only when a stale section has a patch block" 'grep -qF "no stale section that has a patch block, stop here" "$retro_skill" && grep -qF "If at least one stale section has a patch block, also ask" "$retro_skill"'
assert "resume-work derives task_dir from the note path and reuses the caller config" 'grep -qF "set \`\$task_dir\` to the folder of \`pause.md\`" "$resume_skill" && grep -qF "Reuse the \`\$vault\` and \`\$scripts\` that the calling skill resolved" "$resume_skill"'
assert "resume-work asks for the status before the restore block when paused_from is empty" '[ "$(grep -n "ask the user for the status now, before the block below runs" "$resume_skill" | head -1 | cut -d: -f1)" -lt "$(grep -n "old_status=" "$resume_skill" | head -1 | cut -d: -f1)" ] && grep -qF "user_status:-" "$resume_skill"'
assert "start-task exit 3 row says init-service hands a contract task off" 'grep -qF "hands a \`contract\` task off in the same way" "$repo_root/skills/start-task/SKILL.md"'
assert "init-service Phase 8 intro does not name LIFEOS_ROOT" '! grep -qF "Set \`vault\`, \`LIFEOS_ROOT\`" "$repo_root/skills/init-service/SKILL.md" && grep -qF "Set \`vault\` and \`REPO_ROOT\` again" "$repo_root/skills/init-service/SKILL.md"'
assert "new-section check strips a trailing space and carriage return" 'grep -qF "trailing space and a trailing carriage return" "$repo_root/skills/start-task/references/confirmation.md" && grep -qF "trailing space and a trailing carriage return" "$repo_root/skills/deliver-task/SKILL.md"'
assert "run-evals fills __PLUGIN_ROOT__ and the contract evals use it for plugin scripts" 'grep -qF "s|__PLUGIN_ROOT__|" "$repo_root/tests/run-evals.sh" && for e in confirm-stale-contract gate-applies-merged-patch; do grep -qF "__PLUGIN_ROOT__/scripts/new-task-folder.sh" "$repo_root/evals/$e/prompt.md" && grep -qF "__PLUGIN_ROOT__/scripts/frontmatter-set.sh" "$repo_root/evals/$e/prompt.md" || exit 1; done'
add_text='session-id-add.sh" "$task_dir/spec.md" "${CLAUDE_SESSION_ID}"'
status_text='fm_get "$task_dir/spec.md" status'
work_section="$(sed -n '/^## Work mode/,/^## Stop items/p' "$start_skill")"
add_line="$(grep -nF -- "$add_text" <<<"$work_section" | head -1 | cut -d: -f1)"
status_line="$(grep -nF -- "$status_text" <<<"$work_section" | head -1 | cut -d: -f1)"
assert "start-task work mode records the session id before it reads the status" '[ -n "$add_line" ] && [ -n "$status_line" ] && [ "$add_line" -lt "$status_line" ]'
note_template="$repo_root/templates/retro-note.md"
assert "retro-note template has its frontmatter keys and five headings in order" '[ -f "$note_template" ] && grep -q "^task_id:" "$note_template" && grep -q "^written_at:" "$note_template" && [ "$(grep "^## " "$note_template" | tr "\n" "|")" = "## Slow or repeated steps|## Would script|## Spec gaps|## Tool and guard friction|## Surprises|" ]'
deliver_skill="$repo_root/skills/deliver-task/SKILL.md"
finish_note_line="$(sed -n '/^## Finish/,/^## Stop/p' "$deliver_skill" | grep -n 'templates/retro-note.md' | head -1 | cut -d: -f1)"
finish_status_line="$(sed -n '/^## Finish/,/^## Stop/p' "$deliver_skill" | grep -n 'Set `status` to `delivered`' | head -1 | cut -d: -f1)"
assert "deliver Finish writes retro-note.md before it sets status to delivered" '[ -n "$finish_note_line" ] && [ -n "$finish_status_line" ] && [ "$finish_note_line" -lt "$finish_status_line" ]'
finish_note_step="$(sed -n '/^## Finish/,/^## Stop/p' "$deliver_skill" | grep 'templates/retro-note.md')"
assert "deliver Finish note step carries the rules, the written_at command, and the resume skip" 'grep -qF "date -u +%Y-%m-%dT%H:%M:%SZ" <<<"$finish_note_step" && grep -qF "Each bullet names its evidence" <<<"$finish_note_step" && grep -qF "None." <<<"$finish_note_step" && grep -qF "If \`\$task_dir/retro-note.md\` exists, keep it and skip this step" <<<"$finish_note_step"'
verify_ref="$repo_root/skills/start-task/references/verify.md"
retry_block="$(sed -n '/^Retry-limit stop:/,/^Any other stop/p' "$verify_ref")"
assert "verify retry-limit Cancel writes retro-note.md before status cancelled and names the stop cause, other Cancel unchanged" 'grep "^- Cancel:" <<<"$retry_block" | grep -q "retro-note.md.*Spec gaps.*Surprises.*run-log.md.*cancelled" && [ "$(grep -c "^- Cancel: set .status. to .cancelled.\.$" "$verify_ref")" = 1 ]'
assert "execute.md holds the herdr pane rule" 'grep -qF "herdr pane split --current" "$repo_root/skills/start-task/references/execute.md" && grep -qF "close it before Deliver" "$repo_root/skills/start-task/references/execute.md"'
assert "spec lists retro-note.md" 'grep -q "retro-note.md Deliver" "$repo_root/docs/spec.md"'
assert "run-retro: Ask the RDs sits between the analyst dispatch and the retro file" '[ "$(grep -n "^4\. Dispatch the agent" "$retro_skill" | head -1 | cut -d: -f1)" -lt "$(grep -n "^## Ask the RDs" "$retro_skill" | cut -d: -f1)" ] && [ "$(grep -n "^## Ask the RDs" "$retro_skill" | cut -d: -f1)" -lt "$(grep -n "^5\. Write" "$retro_skill" | head -1 | cut -d: -f1)" ]'
assert "run-retro: the fork is read-only, resumed from a fork, and runs without the herdr variables" 'grep -qF -- "--fork-session" "$retro_skill" && grep -qF -- "--tools Read,Grep,Glob" "$retro_skill" && grep -qF "env -u HERDR_ENV" "$retro_skill"'
assert "run-retro: writes RD answers and dispatches the analyst a second time" 'grep -qF "## RD answers" "$retro_skill" && grep -qF "dispatch \`wstack:retro-analyst\` a second time" "$retro_skill"'
finish
