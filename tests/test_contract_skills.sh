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

for key in contract_file base_branch checked_commit check_exit; do
  assert "confirmation.md names the gate state key $key" 'grep -qF -- "\`$key\`" "$confirmation"'
done
assert "verify.md reads the gate state with fm_get" 'grep -qF "fm_get" "$verify" && grep -qF "contract-brief.md" "$verify"'
assert "step 9 says the trap already unlocked" 'grep -qF "The trap already ran \`unlock\`" "$confirmation"'
assert "gate deletes old files before dispatch" 'grep -qF "Delete \`\$task_dir/contract-brief.md\` and \`\$task_dir/contract.gate-patch.md\`" "$confirmation"'
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
assert "deliver: plan.before.md saved before delete-section" '[ "$(grep -nF "plan.before.md\" ] ||" "$deliver" | head -1 | cut -d: -f1)" -lt "$(grep -nF "contract-edit.sh\" delete-section" "$deliver" | head -1 | cut -d: -f1)" ]'
assert "deliver: undo restores plan items from plan.before.md" 'grep -qF "<task folder>/plan.before.md --sections" "$deliver"'
assert "deliver: undo leaves out a part without names" 'grep -qF "Leave out the plan part" "$deliver" && grep -qF "Leave out the contract part" "$deliver"'
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

finish
