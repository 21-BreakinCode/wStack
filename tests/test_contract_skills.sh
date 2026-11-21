#!/usr/bin/env bash
# Static pins for the contract instructions in the skills. Evals cannot run on every Mac.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"

confirmation="$repo_root/skills/start-task/references/confirmation.md"
verify="$repo_root/skills/start-task/references/verify.md"

for needle in 'contract-path.sh' 'contract-check.sh' 'wstack:contract-reader' '=== PATCH ===' \
  'contract-brief.md' 'contract.gate-patch.md' 'contract.before.md' \
  '# Contract changes from the gate' 'fetch origin'; do
  assert "confirmation.md names $needle" 'grep -qF -- "$needle" "$confirmation"'
done
assert "confirmation.md uses git -C" 'grep -qF "git -C" "$confirmation"'

line_of() { grep -nF -- "$1" "$confirmation" | head -1 | cut -d: -f1; }
lock_line="$(line_of 'contract-edit.sh" lock')"
apply_line="$(line_of 'contract-edit.sh" apply')"
assert "lock before apply" '[ -n "$lock_line" ] && [ -n "$apply_line" ] && [ "$lock_line" -lt "$apply_line" ]'
gate_line="$(line_of '## Contract gate')"
spec_line="$(line_of '## Write the spec')"
assert "gate section before Write the spec" '[ -n "$gate_line" ] && [ "$gate_line" -lt "$spec_line" ]'
assert "verify.md passes the contract path to the reviewer" 'grep -qF "contract path" "$verify"'

for key in contract_file base_branch checked_commit check_exit stale_sections; do
  assert "confirmation.md names the gate state key $key" 'grep -qF -- "\`$key\`" "$confirmation"'
done
assert "verify.md reads the gate state with fm_get" 'grep -qF "fm_get" "$verify" && grep -qF "contract-brief.md" "$verify"'
assert "step 9 says the trap already unlocked" 'grep -qF "The trap already ran \`unlock\`" "$confirmation"'
assert "gate deletes old files before dispatch" 'grep -qF "If \`\$task_dir/contract-brief.md\` or \`\$task_dir/contract.gate-patch.md\` exists, delete it." "$confirmation"'
assert "step 9 is not tied to check exit 1" '! grep -qF "If the check in G5 exited 1" "$confirmation"'
assert "set-verified uses checked_commit" 'grep -F "set-verified" "$confirmation" | grep -qF "checked_commit"'

deliver="$repo_root/skills/deliver-task/SKILL.md"
decision_template="$repo_root/templates/decision.md"
assert "deliver has Contract write-back heading" 'grep -qxF "## Contract write-back" "$deliver"'
assert "deliver has Pending items heading" 'grep -qxF "## Pending items" "$deliver"'
for needle in 'contract-brief.md' 'contract.patch.md' '=== PATCH ===' 'pending-add' 'next-decision-id' \
  'templates/decision.md' 'docs/adr/' 'contract write-back' 'gh pr view' 'MERGED' 'CLOSED' 'OPEN' \
  'contract.before.md' 'delete-section' 'pending-remove' '{{tasks_dir}}'; do
  assert "deliver-task names $needle" 'grep -qF -- "$needle" "$deliver"'
done
pending_part="$(sed -n '/^## Pending items/,$p' "$deliver")"
pending_line_of() { printf '%s\n' "$pending_part" | grep -nF -- "$1" | head -1 | cut -d: -f1; }
p_lock="$(pending_line_of 'contract-edit.sh" lock')"
p_apply="$(pending_line_of 'contract-edit.sh" apply')"
assert "pending: lock before apply" '[ -n "$p_lock" ] && [ -n "$p_apply" ] && [ "$p_lock" -lt "$p_apply" ]'
assert "pending: trap unlock comes right after lock" 'printf "%s\n" "$pending_part" | grep -A1 -F "contract-edit.sh\" lock" | grep -qF "trap"'
assert "decision template links the tasks folder" 'grep -qF "task: \"[[{{tasks_dir}}/{{task_id}}/spec]]\"" "$decision_template"'


# Each lock block runs in one shell: it needs set -e and a trap that unlocks.
for lock_file in "$confirmation" "$deliver"; do
  lock_blocks="$(grep -cF 'contract-edit.sh" lock' "$lock_file" || true)"
  trap_lines="$(grep -cF "trap 'bash \"\$scripts/contract-edit.sh\" unlock" "$lock_file" || true)"
  set_e_lines="$(grep -cx '[[:space:]]*set -e' "$lock_file" || true)"
  assert "$(basename "$lock_file"): every lock has a trap with unlock" '[ "$lock_blocks" -ge 1 ] && [ "$trap_lines" -eq "$lock_blocks" ]'
  assert "$(basename "$lock_file"): every lock block has set -e" '[ "$set_e_lines" -ge "$lock_blocks" ]'
  assert "$(basename "$lock_file"): no bare unlock line" '! grep -qE "^[[:space:]]*bash .*contract-edit.sh\" unlock" "$lock_file"'
done
assert "deliver: apply output is read from the call" 'grep -qF "Read both from the output of the call" "$deliver"'
assert "deliver: plan.writeback.before.md saved before delete-section" '[ "$(grep -nF "plan.writeback.before.md\" ] ||" "$deliver" | head -1 | cut -d: -f1)" -lt "$(grep -nF "contract-edit.sh\" delete-section" "$deliver" | head -1 | cut -d: -f1)" ]'
assert "deliver: undo restores plan items from plan.writeback.before.md" 'grep -qF "<task folder>/plan.writeback.before.md'"'"' --sections" "$deliver"'
assert "deliver: undo leaves out a part without names" 'grep -qF "leave out the plan part" "$deliver" && grep -qF "leave out the contract part" "$deliver"'
assert "deliver: apply exit 2 has a way out" 'grep -qF "the user can say to drop the item" "$deliver"'
assert "deliver: None patch still writes decisions" 'grep -qF "Decisions do not depend on the patch" "$deliver"'

execute="$repo_root/skills/start-task/references/execute.md"
launch="$repo_root/skills/start-task/SKILL.md"
contract_part="$(sed -n '/^## Contract work/,/^## Learning tasks/p' "$execute")"
assert "execute.md: Contract work after Thinking and ops work" '[ -n "$(grep -nxF "## Contract work" "$execute" | head -1)" ] && [ "$(grep -nxF "## Thinking and ops work" "$execute" | head -1 | cut -d: -f1)" -lt "$(grep -nxF "## Contract work" "$execute" | head -1 | cut -d: -f1)" ]'
for needle in 'contract.draft.md' 'plan.draft.md' 'decisions.draft/' 'templates/contract.md' 'Open questions' \
  'fetch origin' 'rev-parse' 'verified_commit' 'next-decision-id' 'contract-path.sh' 'repository not mapped: run /wstack:init-service'; do
  assert "execute.md Contract work names $needle" 'printf "%s\n" "$contract_part" | grep -qF -- "$needle"'
done
assert "verify.md names file:line for contract work" 'grep -qF "file:line" "$verify"'
assert "SKILL.md launch names contract work type" 'grep -qF "\`contract\`" "$launch"'

files_part="$(sed -n '/^### Contract files/,/^## /p' "$deliver")"
assert "deliver has Contract files heading" 'grep -qxF "### Contract files" "$deliver"'
for needle in 'contract.before.md' '_archive/' 'handover/' 'decisions/' 'set-verified' 'contract.draft.md' 'set -e' "trap 'bash" 'unlock' 'fm_get' 'contract-path.sh'; do
  assert "deliver Contract files names $needle" 'printf "%s\n" "$files_part" | grep -qF -- "$needle"'
done

step6_line="$(printf '%s\n' "$contract_part" | grep -E '^6\. ')"
step3_line="$(printf '%s\n' "$contract_part" | grep -E '^3\. ')"
assert "execute: step 6 sets verified_commit when it fills the template" 'printf "%s\n" "$step6_line" | grep -qF "verified_commit" && printf "%s\n" "$step6_line" | grep -qF "templates/contract.md"'
assert "execute: step 3 keeps the SHA for step 6" 'printf "%s\n" "$step3_line" | grep -qF "step 6"'
assert "execute: new-project questions are not in Execute" '! printf "%s\n" "$contract_part" | grep -qF "Ask the user one question"'
assert "confirmation: contract new-project detection and questions" 'grep -qF "has no source files outside the team docs" "$confirmation" && grep -qF "planned path" "$confirmation" && grep -qF "project: new" "$confirmation"'
assert "deliver: decisions are checked before the first change" '[ "$(printf "%s\n" "$files_part" | grep -nF "already exists in decisions/" | head -1 | cut -d: -f1)" -lt "$(printf "%s\n" "$files_part" | grep -nF "cp \"\$contract_file\" \"\$task_dir/contract.before.md" | head -1 | cut -d: -f1)" ]'
assert "deliver: contract.before.md is write-once" 'printf "%s\n" "$files_part" | grep -qF "[ -f \"\$task_dir/contract.before.md\" ] || cp"'
assert "deliver: archive never moves over a file" 'printf "%s\n" "$files_part" | grep -qF "[ ! -e \"\$archive_dir/\$(basename \"\$old_file\")\" ] || continue" && printf "%s\n" "$files_part" | grep -qF ".archived"'
assert "deliver: empty decisions.draft does not fail" '! printf "%s\n" "$files_part" | grep -qF "decisions.draft\"/* \"\$contract_folder"'
assert "confirmation: existing project asks no section question and lists what to read" 'grep -qF "ask no section question" "$confirmation" && grep -qF "code areas to read under" "$confirmation"'
assert "execute: existing project reads the list from the spec" 'printf "%s\n" "$contract_part" | grep -qF "code areas that the spec lists"'

# Final fix wave pins
assert "gate stops start with the prefix" '[ "$(grep -cF "the reason \`contract gate: <stderr text>\`" "$confirmation")" -ge 1 ] && [ "$(grep -cF "the reason \`contract gate: <stderr text>\`" "$deliver")" -ge 1 ]'
assert "After a stop runs the gate again from G1 for the prefix" 'sed -n "/^## After a stop/,/^## /p" "$confirmation" | grep -F "\`contract gate:\`" | grep -qF "from G1"'
assert "G5 writes stale_sections from the check" 'grep -qF "the one-line JSON list from the \`stale_sections:\` line of the check" "$confirmation"'
assert "step 9 reads stale_sections before set-verified" 'grep -qF "fm_get \"\$task_dir/contract-brief.md\" stale_sections" "$confirmation"'
assert "gate snapshots are contract.before.md and plan.before.md" 'grep -qF "cp \"\$contract_file\" \"\$task_dir/contract.before.md\"" "$confirmation" && grep -qF "\"\$task_dir/plan.before.md\"" "$confirmation"'
assert "write-back snapshots have their own names" 'grep -qF "\"\$task_folder/contract.writeback.before.md\"" "$deliver" && grep -qF "\"\$task_folder/plan.writeback.before.md\"" "$deliver" && ! sed -n "/^## Pending items/,\$p" "$deliver" | grep -qF "task_folder/contract.before.md"'
assert "write-back undo names its own snapshot" 'grep -qF "<task folder>/contract.writeback.before.md'"'"' --sections" "$deliver"'
assert "plan headings sit in single quotes" '[ "$(grep -cF "for heading in '"'"'<heading>'"'"'; do" "$confirmation")" -eq 1 ] && [ "$(grep -cF "for heading in '"'"'<heading>'"'"'; do" "$deliver")" -eq 1 ] && ! grep -qF "\"<heading>\"" "$confirmation" "$deliver"'
assert "reference bash blocks use no CLAUDE_PLUGIN_ROOT" '! awk "/^[[:space:]]*\`\`\`bash/{b=1;next} /^[[:space:]]*\`\`\`/{b=0} b" "$confirmation" "$execute" "$verify" | grep -qF "CLAUDE_PLUGIN_ROOT"'
assert "decision files are written under the lock" 'sed -n "/^## Contract write-back/,/^## Targets/p" "$deliver" | grep -qF "next-decision-id \"\$decisions_dir\""'
reader="$repo_root/agents/contract-reader.md"
assert "reader writes no code fence in the reply" 'sed -n "/^## Reply/,\$p" "$reader" | grep -qF "Write no code fence in the reply."'
assert "reader writes stale sections from the code" 'grep -qF "If the code does not show a fact, leave the fact out." "$reader"'

finish
