#!/usr/bin/env bash
# Static pins for the contract instructions in the skills. Evals cannot run on every Mac.
# Each pin reads one section of a file, so a match in another section does not count.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"

confirmation="$repo_root/skills/start-task/references/confirmation.md"
verify="$repo_root/skills/start-task/references/verify.md"
execute="$repo_root/skills/start-task/references/execute.md"
launch="$repo_root/skills/start-task/SKILL.md"
deliver="$repo_root/skills/deliver-task/SKILL.md"
reader="$repo_root/agents/contract-reader.md"
decision_template="$repo_root/templates/decision.md"
contract_template="$repo_root/templates/contract.md"

# slice <file> <first line prefix> <end line prefix>: the lines from the first line with the first prefix, up to the next line with the end prefix
slice() { awk -v from="$2" -v to="$3" 'on && index($0, to) == 1 { exit } !on && index($0, from) == 1 { on = 1 } on' "$1"; }
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }
line_in() { printf '%s\n' "$1" | grep -nF -- "$2" | head -1 | cut -d: -f1; }

gate_part="$(slice "$confirmation" '## Contract gate' '## Write the spec')"
write_part="$(slice "$confirmation" '## Write the spec' '## Show the spec')"
show_part="$(slice "$confirmation" '## Show the spec' '## After approval')"
step9_part="$(slice "$confirmation" '9. ' '10. ')"
stop_part="$(slice "$confirmation" '## After a stop' '## Approval scope')"
g1_line="$(printf '%s\n' "$gate_part" | grep '^G1\. ')"
g3_line="$(printf '%s\n' "$gate_part" | grep '^G3\. ')"
g5_part="$(slice "$confirmation" 'G5. ' 'G6. ')"
verify_step3="$(grep '^3\. Final review' "$verify")"
files_part="$(slice "$deliver" '### Contract files' '## Contract write-back')"
writeback_part="$(slice "$deliver" '## Contract write-back' '## Targets that need approval')"
pending_part="$(sed -n '/^## Pending items/,$p' "$deliver")"
merged_part="$(slice "$deliver" '- `MERGED`:' '- `CLOSED`:')"
closed_part="$(slice "$deliver" '- `CLOSED`:' 'Exit 4 from `lock`')"
contract_part="$(slice "$execute" '## Contract work' '## Learning tasks')"

# Contract gate
for needle in 'contract-path.sh' 'contract-check.sh' 'wstack:contract-reader' '=== PATCH ===' 'contract-brief.md' 'contract.gate-patch.md'; do
  assert "gate names $needle" 'has "$gate_part" "$needle"'
done
assert "G1 skips the rest of the gate for other work types" 'has "$g1_line" "If \`work_type\` is not \`code\` or \`ops\`, skip the rest of the gate."'
assert "G2 exit 1 writes Contract: not mapped" 'printf "%s\n" "$gate_part" | grep -F "Exit 1:" | grep -qF "\`Contract: not mapped\`"'
assert "G3 fetches with git -C" 'has "$g3_line" "git -C \"<repository folder>\" fetch origin \"<base_branch>\""'
assert "G3: a failed fetch is noted in the brief at G5" 'has "$g3_line" "G5 then adds a line about it to the brief." && has "$g5_part" "If the fetch in G3 failed, append the line"'
assert "gate deletes old files in G1, before any exit" 'has "$g1_line" "If \`\$task_dir/contract-brief.md\` or \`\$task_dir/contract.gate-patch.md\` exists, delete it." && ! has "$g5_part" "delete it"'
gate_line="$(grep -nxF '## Contract gate' "$confirmation" | cut -d: -f1)"
spec_line="$(grep -nxF '## Write the spec' "$confirmation" | cut -d: -f1)"
assert "gate section before Write the spec" '[ -n "$gate_line" ] && [ "$gate_line" -lt "$spec_line" ]'
for key in contract_file base_branch checked_commit stale_sections; do
  assert "G5 names the gate state key $key" 'has "$g5_part" "\`$key\`"'
done
assert "check_exit is gone: nothing reads it" '! grep -qF "check_exit" "$confirmation" "$deliver" "$repo_root/docs/spec.md" "$repo_root/evals/deliver-contract-pending/prompt.md"'
assert "G5 writes stale_sections from the check" 'has "$g5_part" "the one-line JSON list from the \`stale_sections:\` line of the check"'
assert "gate stops start with the prefix" '[ "$(grep -cF "the reason \`contract gate: <stderr text>\`" "$confirmation")" -ge 1 ] && [ "$(grep -cF "the reason \`contract gate: <stderr text>\`" "$deliver")" -ge 1 ]'
assert "After a stop runs the gate again from G1 for the prefix" 'printf "%s\n" "$stop_part" | grep -F "\`contract gate:\`" | grep -qF "from G1"'

# Write the spec and Show the spec
assert "contract task: new-project detection and questions" 'has "$write_part" "If no listed file is a source file outside the team docs, the project is new." && has "$write_part" "planned path" && has "$write_part" "project: new"'
assert "contract task: the file list has a command" 'has "$write_part" "ls-tree -r --name-only \"origin/<base_branch>\""'
assert "contract task: a failed fetch has a rule" 'has "$write_part" "If the fetch fails, tell the user the stderr text."'
assert "contract task: existing project asks no section question and lists what to read" 'has "$write_part" "ask no section question" && has "$write_part" "code areas to read under"'
assert "existing contract project never writes None under Contract changes" 'has "$write_part" "For an existing \`contract\` project, list the team docs and the code areas to read. A \`contract\` task never writes \`None\` here."'
assert "a work_type change runs the gate again, then step 1" 'printf "%s\n" "$write_part" | grep "^3\. " | grep -qF "run \"Contract gate\" again from G1, and go back to step 1."'
assert "G5: set up the contract first is a gate stop" 'has "$g5_part" "the reason \`contract gate: set up the contract first\`"'
assert "spec page puts the gate patch right after the title line" 'has "$show_part" "right after the title line, under the heading \`# Contract changes from the gate\`"'

# After approval, step 9
lock_line="$(line_in "$step9_part" 'contract-edit.sh" lock')"
apply_line="$(line_in "$step9_part" 'contract-edit.sh" apply')"
assert "step 9: lock before apply" '[ -n "$lock_line" ] && [ -n "$apply_line" ] && [ "$lock_line" -lt "$apply_line" ]'
assert "step 9: no brief goes straight to step 10" 'printf "%s\n" "$step9_part" | head -1 | grep -qF "and go to step 10." && ! has "$step9_part" "skip to"'
assert "step 9: exit 4 means the lock is busy" 'has "$step9_part" "Exit 4 means the lock is busy."'
assert "step 9 says the trap already unlocked" 'has "$step9_part" "The trap already ran \`unlock\`"'
assert "step 9 is not tied to check exit 1" '! grep -qF "If the check in G5 exited 1" "$confirmation"'
assert "step 9: set-verified uses checked_commit" 'printf "%s\n" "$step9_part" | grep -F "set-verified" | grep -qF "checked_commit"'
assert "step 9 reads stale_sections before set-verified" 'has "$step9_part" "fm_get \"\$task_dir/contract-brief.md\" stale_sections"'
assert "step 9: gate snapshots are contract.before.md and plan.before.md" 'has "$step9_part" "cp \"\$contract_file\" \"\$task_dir/contract.before.md\"" && has "$step9_part" "\"\$task_dir/plan.before.md\""'
assert "step 9: a missing plan.md skips the plan lines" 'has "$step9_part" "or \`plan.md\` is not in the contract folder, skip the plan lines"'
assert "step 9: run-log gets the undo of the contract part" 'has "$step9_part" "The old-section command:" && has "$step9_part" "contract.before.md'"'"' --sections"'
assert "step 9: the undo deletes new sections and restores verified_commit" 'has "$step9_part" "The new-section command, once for each name that a warning named:" && has "$step9_part" "add the commit command:" && has "$step9_part" "fm_get '"'"'<task folder>/contract.before.md'"'"' verified_commit"'
assert "step 9: both undo lines say how to pass a name with a comma" '[ "$(printf "%s\n" "$step9_part" | grep -cF "If a name holds a comma, give every name as its own \`--section '"'"'<name>'"'"'\` flag in place of \`--sections\`.")" = 2 ]'
assert "step 9: run-log gets the undo of the plan part" 'has "$step9_part" "with the undo of the plan part:"'

# Verify
assert "verify step 3 passes the contract path to the reviewer" 'has "$verify_step3" "also give it the contract path"'
assert "verify step 3 reads the gate state with fm_get" 'has "$verify_step3" "fm_get \"\$task_dir/contract-brief.md\" contract_file"'
assert "verify step 3 names each file" 'has "$verify_step3" "If \`contract-brief.md\` does not exist" && has "$verify_step3" "If \`agents/reviewer.md\` is not there" && ! has "$verify_step3" "If the file"'
assert "verify step 3 names file:line for contract work" 'has "$verify_step3" "file:line"'

# Deliver: Contract write-back
assert "deliver has Contract write-back heading" 'grep -qxF "## Contract write-back" "$deliver"'
assert "deliver has Pending items heading" 'grep -qxF "## Pending items" "$deliver"'
for needle in 'contract-brief.md' 'contract.patch.md' '=== PATCH ===' 'pending-add' 'next-decision-id' \
  'templates/decision.md' 'docs/adr/' 'contract write-back' '{{tasks_dir}}'; do
  assert "Contract write-back names $needle" 'has "$writeback_part" "$needle"'
done
assert "write-back: None patch still writes decisions" 'has "$writeback_part" "Decisions do not depend on the patch"'
assert "write-back: decision files are written under the lock" 'has "$writeback_part" "next-decision-id \"\$decisions_dir\""'
assert "write-back: the reuse glob needs a 4-digit id before the slug" 'has "$writeback_part" "\"\$decisions_dir\"/[0-9][0-9][0-9][0-9]-\"\$(basename \"\$draft\")\""'
assert "write-back: a retry reuses the decision file of the same slug and task" 'has "$writeback_part" "grep -qF \"/\$(basename \"\$task_dir\")/spec]]\"" && has "$writeback_part" "so a retry makes no second copy"'
assert "decision template links the tasks folder" 'grep -qF "task: \"[[{{tasks_dir}}/{{task_id}}/spec]]\"" "$decision_template"'

# Deliver: Pending items
for needle in 'gh pr view' 'MERGED' 'CLOSED' 'OPEN' 'delete-section' 'pending-remove'; do
  assert "Pending items names $needle" 'has "$pending_part" "$needle"'
done
p_lock="$(line_in "$pending_part" 'contract-edit.sh" lock')"
p_apply="$(line_in "$pending_part" 'contract-edit.sh" apply')"
assert "pending: lock before apply" '[ -n "$p_lock" ] && [ -n "$p_apply" ] && [ "$p_lock" -lt "$p_apply" ]'
assert "pending: trap unlock comes right after lock" 'printf "%s\n" "$pending_part" | grep -A1 -F "contract-edit.sh\" lock" | grep -qF "trap"'
assert "pending: <contract folder> is defined" 'has "$pending_part" "\`<contract folder>\` is the folder that holds \`\$contract_file\`."'
assert "MERGED: a missing task folder keeps the item" 'has "$merged_part" "if the task folder of the item does not exist, keep the item"'
assert "MERGED: the heading placeholder is named" 'has "$merged_part" "in place of \`'"'"'<heading>'"'"'\` in the \`for\` line"'
assert "MERGED: a missing plan.md skips the plan lines" 'has "$merged_part" "or \`plan.md\` is not in the contract folder, skip the plan lines"'
assert "MERGED: a removed heading prints only on delete-section exit 0" 'has "$merged_part" "[ \"\$rc\" -le 1 ] || exit \"\$rc\"" && has "$merged_part" "[ \"\$rc\" = 1 ] || printf '"'"'plan item removed: %s\n'"'"' \"\$heading\""'
assert "MERGED: apply output is read from the call" 'has "$merged_part" "Read both from the output of the call"'
assert "MERGED: plan.writeback.before.md saved before delete-section" '[ "$(line_in "$merged_part" "plan.writeback.before.md\" ] ||")" -lt "$(line_in "$merged_part" "contract-edit.sh\" delete-section")" ]'
assert "MERGED: undo restores plan items from plan.writeback.before.md" 'has "$merged_part" "<task folder>/plan.writeback.before.md'"'"' --sections"'
assert "MERGED: undo leaves out a part without names" 'has "$merged_part" "leave out the plan part" && has "$merged_part" "leave out the contract part"'
assert "MERGED: write-back snapshots have their own names" 'has "$merged_part" "\"\$task_folder/contract.writeback.before.md\"" && has "$merged_part" "\"\$task_folder/plan.writeback.before.md\"" && ! has "$pending_part" "task_folder/contract.before.md"'
assert "MERGED: write-back undo names its own snapshot" 'has "$merged_part" "<task folder>/contract.writeback.before.md'"'"' --sections"'
assert "CLOSED: decision files of the task are withdrawn and logged" 'has "$closed_part" "fm_set \"\$decision_file\" status withdrawn" && has "$closed_part" "For each \`decision withdrawn:\` line, write a \`step\` line in \`run-log.md\`"'
assert "pending: a stuck item can be dropped without withdrawing decisions" 'has "$pending_part" "If the user says to drop the item, run \`pending-remove\` for its pull request" && has "$pending_part" "Do not withdraw its decisions."'
assert "MERGED: the undo deletes a section that apply added as new" 'has "$merged_part" "add the new-section part \`bash '"'"'<scripts>/contract-edit.sh'"'"' delete-section"'
assert "pending: a new section has a warning, not an impossible exit 2" 'has "$pending_part" "prints a warning on stderr that names the section" && ! has "$pending_part" "If \`apply\` exits 2"'

# Each lock block runs in one shell: it needs set -e and a trap that unlocks.
for lock_file in "$confirmation" "$deliver"; do
  lock_blocks="$(grep -cF 'contract-edit.sh" lock' "$lock_file" || true)"
  trap_lines="$(grep -cF "trap 'bash \"\$scripts/contract-edit.sh\" unlock" "$lock_file" || true)"
  set_e_lines="$(grep -cx '[[:space:]]*set -e' "$lock_file" || true)"
  assert "$(basename "$lock_file"): every lock has a trap with unlock" '[ "$lock_blocks" -ge 1 ] && [ "$trap_lines" -eq "$lock_blocks" ]'
  assert "$(basename "$lock_file"): every lock block has set -e" '[ "$set_e_lines" -ge "$lock_blocks" ]'
  assert "$(basename "$lock_file"): no bare unlock line" '! grep -qE "^[[:space:]]*bash .*contract-edit.sh\" unlock" "$lock_file"'
done
assert "plan headings sit in single quotes" '[ "$(grep -cF "for heading in '"'"'<heading>'"'"'; do" "$confirmation")" -eq 1 ] && [ "$(grep -cF "for heading in '"'"'<heading>'"'"'; do" "$deliver")" -eq 1 ] && ! grep -qF "\"<heading>\"" "$confirmation" "$deliver"'

# Execute: Contract work
assert "execute.md: Contract work after Thinking and ops work" '[ -n "$(grep -nxF "## Contract work" "$execute" | head -1)" ] && [ "$(grep -nxF "## Thinking and ops work" "$execute" | head -1 | cut -d: -f1)" -lt "$(grep -nxF "## Contract work" "$execute" | head -1 | cut -d: -f1)" ]'
for needle in 'contract.draft.md' 'plan.draft.md' 'decisions.draft/' 'templates/contract.md' 'Open questions' \
  'fetch origin' 'rev-parse' 'verified_commit' 'next-decision-id' 'contract-path.sh' 'repository not mapped: run /wstack:init-service'; do
  assert "execute.md Contract work names $needle" 'has "$contract_part" "$needle"'
done
assert "SKILL.md launch names contract work type" 'grep -qF "\`contract\`" "$launch"'
step6_line="$(printf '%s\n' "$contract_part" | grep -E '^6\. ')"
step3_line="$(printf '%s\n' "$contract_part" | grep -E '^3\. ')"
step7_line="$(printf '%s\n' "$contract_part" | grep -E '^7\. ')"
assert "execute: step 6 sets verified_commit when it fills the template" 'has "$step6_line" "verified_commit" && has "$step6_line" "templates/contract.md"'
assert "execute: step 3 keeps the SHA for step 6" 'has "$step3_line" "step 6"'
assert "execute: new-project questions are not in Execute" '! has "$contract_part" "Ask the user one question"'
assert "execute: existing project reads the list from the spec" 'has "$contract_part" "code areas that the spec lists"'
for placeholder in $(grep -ho '{{[a-z_]*}}' "$contract_template" "$repo_root/templates/plan.md" | tr -d '{}' | sort -u); do
  assert "execute: step 6 says how to fill $placeholder" 'has "$step6_line" "$placeholder"'
done
assert "execute: org_kebab is defined" 'has "$step6_line" "\`{{org_kebab}}\` is the \`<ORG>\` folder of the contract path"'
assert "execute: step 7 fills the plan template" 'has "$step7_line" "Fill \`app_name\` and \`tags\` as in step 6."'

# Deliver: Contract files
assert "deliver has Contract files heading" 'grep -qxF "### Contract files" "$deliver"'
for needle in 'contract.before.md' '_archive/' 'handover/' 'decisions/' 'set-verified' 'contract.draft.md' 'set -e' "trap 'bash" 'unlock' 'fm_get' 'contract-path.sh'; do
  assert "deliver Contract files names $needle" 'has "$files_part" "$needle"'
done
assert "Contract files: <workspace_cwd> has a source" 'has "$files_part" "\`<workspace_cwd>\` is the \`workspace_cwd\` value in the spec frontmatter."'
assert "Contract files: decisions are checked before the first change" '[ "$(line_in "$files_part" "already exists in decisions/")" -lt "$(line_in "$files_part" "cp \"\$contract_file\" \"\$task_dir/contract.before.md")" ]'
assert "Contract files: the clash check compares ids" 'has "$files_part" "for same_id in \"\$contract_folder/decisions/\${draft_name%%-*}\"-*; do"'
assert "Contract files: copied decisions are listed and the undo deletes only those" 'has "$files_part" ">>\"\$task_dir/decisions.copied.txt\"" && has "$files_part" "the files in <contract folder>/decisions/ that <task folder>/decisions.copied.txt names"'
assert "Contract files: the undo deletes the archive folder" 'has "$files_part" "then delete the folder <contract folder>/_archive/<task_id>/"'
assert "Contract files: the text says the glob skips dot files" 'has "$files_part" "The \`*\` glob skips dot files"'
assert "Contract files: contract.before.md is write-once" 'has "$files_part" "[ -f \"\$task_dir/contract.before.md\" ] || cp"'
assert "Contract files: archive never moves over a file" 'has "$files_part" "[ ! -e \"\$archive_dir/\$(basename \"\$old_file\")\" ] || continue" && has "$files_part" ".archived"'
assert "Contract files: empty decisions.draft does not fail" '! has "$files_part" "decisions.draft\"/* \"\$contract_folder"'

# Agents, templates, and docs
assert "reader writes no code fence in the reply" 'sed -n "/^## Reply/,\$p" "$reader" | grep -qF "Write no code fence in the reply."'
assert "reader writes stale sections from the code" 'grep -qF "If the code does not show a fact, leave the fact out." "$reader"'
assert "reference bash blocks use no CLAUDE_PLUGIN_ROOT" '! awk "/^[[:space:]]*\`\`\`bash/{b=1;next} /^[[:space:]]*\`\`\`/{b=0} b" "$confirmation" "$execute" "$verify" | grep -qF "CLAUDE_PLUGIN_ROOT"'
for key in app_name repo base_branch verified_commit verified_at pending ignore tags; do
  assert "contract template frontmatter has $key" 'sed -n "2,/^---\$/p" "$contract_template" | grep -q "^$key:"'
  assert "README names the contract key $key" 'grep -F "the contract. Its sections are" "$repo_root/README.md" | grep -qF "\`$key\`"'
done
section_body() { awk -v heading="## $2" '/^## / { on = ($0 == heading); next } on' "$1"; }
for section in Abilities Interfaces 'Depends on'; do
  assert "contract template: $section has a sources comment" '[ "$(section_body "$contract_template" "$section" | head -1)" = "<!-- sources: -->" ]'
done
for section in 'Team docs' Consumers Gotchas 'Open questions'; do
  assert "contract template: $section has no sources comment (Ruling 4)" 'grep -qxF "## $section" "$contract_template" && ! section_body "$contract_template" "$section" | grep -qF "sources:"'
done
assert "README states the sources rule of Ruling 4" 'grep -qF "Abilities, Interfaces, and Depends on each have a \`<!-- sources: -->\` comment" "$repo_root/README.md"'
assert "design doc states the sources rule of Ruling 4" 'grep -qF "Every section except \`Team docs\`, \`Consumers\`, \`Gotchas\`, and \`Open questions\` has a \`sources\` comment." "$repo_root/docs/superpowers/specs/2026-11-21-contract-gate-design.md"'
assert "spec.md layout lists the lib scripts" 'grep -qF "lib/frontmatter.sh         fm_get, fm_set, fm_append, fm_to_json:" "$repo_root/docs/spec.md" && grep -qF "lib/herdr.sh" "$repo_root/docs/spec.md"'
assert "design doc names the withdrawn edit of a decision file" 'grep -qF "the gate sets the file'"'"'s \`status\` to \`withdrawn\`." "$repo_root/docs/superpowers/specs/2026-11-21-contract-gate-design.md" && grep -qF "Closed without a merge: drop the patch, set the \`status\` of the task'"'"'s decision files to \`withdrawn\`" "$repo_root/docs/superpowers/specs/2026-11-21-contract-gate-design.md"'
assert "spec.md: contract writes are a note, not an approval rule" '! grep -qF "6. Writing the contract." "$repo_root/docs/spec.md" && grep -qxF "A contract write needs no new approval. The approved spec covers the gate'"'"'s contract update, and the write after a merge. A \`contract\` task covers \`write the contract files\` as a deliver target. Every write takes the lock folder \`<contract>.lock\`. A busy lock stops the task, and the agent never writes without the lock." "$repo_root/docs/spec.md"'

# Evals for these flows. Each one needs the contract world and a grader.
for eval_name in confirm-stale-contract contract-absorb-existing deliver-contract-pending verify-contract-mismatch gate-applies-merged-patch; do
  assert "eval $eval_name builds the contract world" 'grep -qF "__FIXTURES__/contract/setup.sh" "$repo_root/evals/$eval_name/prompt.md"'
  assert "eval $eval_name allows the Agent tool" 'grep "^allowed_tools:" "$repo_root/evals/$eval_name/prompt.md" | grep -qF "Agent"'
  assert "eval $eval_name has a grader" 'ls "$repo_root/evals/$eval_name/graders/"*.md >/dev/null 2>&1'
done
assert "deliver-contract-pending grader gives the real reason for the unchanged body" 'grep -qF "because the contract gate does not run again after Deliver" "$repo_root/evals/deliver-contract-pending/graders/patch-and-pending.md"'

# init-service contract phase
init_skill="$repo_root/skills/init-service/SKILL.md"
init_contract_part="$(slice "$init_skill" '### Phase 8' '### Phase 9')"
init_report_part="$(slice "$init_skill" '### Phase 9' '## Non-negotiable rules')"
for needle in 'contract-path.sh" --vault "$vault"' 'contract-check.sh' 'Set up the service contract now?' 'Launch a contract task' 'Not now' 'Launch mode' 'skills/start-task/SKILL.md' 'set up the contract' 'WSTACK_TASKS_DIR' 'EVAL_WSTACK_TASKS_DIR' 'Workflow/Tasks'; do
  assert "init-service contract phase names $needle" 'has "$init_contract_part" "$needle"'
done
assert "init-service contract phase comes after Phase 7" '[ -n "$(grep -n "^### Phase 8 " "$init_skill" | cut -d: -f1)" ] && [ "$(grep -n "^### Phase 7 " "$init_skill" | cut -d: -f1)" -lt "$(grep -n "^### Phase 8 " "$init_skill" | cut -d: -f1)" ]'
assert "init-service report has a Contract: line" 'has "$init_report_part" "Contract:"'

# glob_blocks_without_null_glob <file>...: counts bash blocks that loop over a glob and lack the setopt line
glob_blocks_without_null_glob() {
  awk '/^[[:space:]]*```bash/ { in_block = 1; has_glob = 0; has_setopt = 0; next }
    /^[[:space:]]*```/ { if (in_block && has_glob && !has_setopt) missing++; in_block = 0 }
    in_block && /setopt NULL_GLOB/ { has_setopt = 1 }
    in_block && /for [a-z_]+ in .*\*/ { has_glob = 1 }
    END { print missing + 0 }' "$@"
}
assert "every bash block with a glob for loop sets NULL_GLOB (zsh)" '[ "$(glob_blocks_without_null_glob "$confirmation" "$execute" "$deliver")" = 0 ]'

finish
