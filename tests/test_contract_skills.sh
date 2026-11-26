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
retro_skill="$repo_root/skills/run-retro/SKILL.md"
decision_template="$repo_root/templates/decision.md"
contract_template="$repo_root/templates/contract.yaml"

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
verify_final_review="$(grep '^4\. Final review' "$verify")"
verify_step1="$(slice "$verify" '1. Behavior check' '2. Stale references')"
verify_edit_part="$(slice "$verify" '## An edit after the last review' '## Go on to Deliver')"
files_part="$(slice "$deliver" '### Contract files' '## Contract write-back')"
writeback_part="$(slice "$deliver" '## Contract write-back' '## Targets that need approval')"
pending_part="$(sed -n '/^## Pending items/,$p' "$deliver")"
merged_part="$(slice "$deliver" '- `MERGED`:' '- `CLOSED`:')"
closed_part="$(slice "$deliver" '- `CLOSED`:' 'Exit 4 from `lock`')"
contract_part="$(slice "$execute" '## Contract work' '## Learning tasks')"

# Contract gate
for needle in 'contract-path.sh' 'contract-check.sh' 'wstack:contract-reader' '=== PATCH ===' 'contract-brief.md' 'contract.gate-patch.yaml'; do
  assert "gate names $needle" 'has "$gate_part" "$needle"'
done
assert "G1 skips the rest of the gate for other work types" 'has "$g1_line" "If \`work_type\` is not \`code\` or \`ops\`, skip the rest of the gate."'
assert "G2 exit 1 writes Contract: not mapped" 'printf "%s\n" "$gate_part" | grep -F "Exit 1:" | grep -qF "\`Contract: not mapped\`"'
assert "G3 fetches with git -C" 'has "$g3_line" "git -C \"<repository folder>\" fetch origin \"<base_branch>\""'
assert "G3: a failed fetch is noted in the brief at G5" 'has "$g3_line" "G5 then adds a line about it to the brief." && has "$g5_part" "If the fetch in G3 failed, append the line"'
assert "the gate text says where it changes the contract" 'has "$gate_part" "The contract file changes in two places only:"'
assert "gate deletes old files in G1, before any exit" 'has "$g1_line" "If \`\$task_dir/contract-brief.md\`, \`\$task_dir/contract.gate-patch.yaml\`, or \`\$task_dir/contract.before.new.yaml\` exists, delete it." && ! has "$g5_part" "delete it"'
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
assert "confirmation names contract-verify-draft.sh in a contract verification plan" 'printf "%s\n" "$write_part" | grep -F "## Verification plan" | grep -qF "For a \`contract\` task, write these two checks:" && has "$write_part" "contract-verify-draft.sh" && has "$write_part" "check-undo-rehearsal.txt" && has "$write_part" "claim review"'
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
assert "step 9: the gate snapshot is contract.before.yaml, with no plan snapshot" 'has "$step9_part" "cp \"\$contract_file\" \"\$task_dir/contract.before.new.yaml\"" && has "$step9_part" "mv \"\$task_dir/contract.before.new.yaml\" \"\$task_dir/contract.before.yaml\"" && ! has "$step9_part" "plan.before.md" && ! has "$step9_part" "delete-section"'
assert "step 9: a missing patch skips the snapshot and apply lines" 'has "$step9_part" "If \`contract.gate-patch.yaml\` does not exist, skip the three lines that name \`contract.before\` and the \`apply\` line."'
assert "step 9: the undo ids come from the snapshot, so a rerun keeps them" 'has "$step9_part" "\"\$task_dir/contract.before.yaml\" | jq -r --argjson remove" && has "$step9_part" "The removed ids are the ids of the \`undo planned:\` line." && ! has "$step9_part" "planned removed:"'
assert "step 9: a refused patch is a gate stop, and G1 keeps the snapshot" 'has "$step9_part" "the reason is \`contract gate: patch refused: <stderr text of apply>\`" && has "$g1_line" "Keep \`\$task_dir/contract.before.yaml\`" && has "$g1_line" "contract.before.new.yaml"'
assert "the gate patch is YAML with a sections map" 'has "$g5_part" "\$task_dir/contract.gate-patch.yaml" && has "$step9_part" "(.sections // {} | keys) + (if has(\"diagrams\")" && grep -qF "a \`sections:\` map" "$reader"'
assert "step 9 undo uses apply with --sections and --planned" 'has "$step9_part" "The undo command: \`bash '"'"'<scripts>/contract-edit.sh'"'"' apply '"'"'<contract_file>'"'"' '"'"'<task folder>/contract.before.yaml'"'"' --sections '"'"'<applied keys, joined by commas>'"'"' --planned '"'"'<removed ids, joined by commas>'"'"' --diagrams\`"'
assert "step 9: an undo with no applied key leaves out --sections and needs no plan-only snapshot" 'has "$step9_part" "If \`apply\` printed no section key, leave out the \`--sections\` flag and its value." && ! has "$step9_part" "contract.before-planned.yaml"'
assert "step 9: the undo restores verified_commit and has no new-section command" 'has "$step9_part" "add the commit command:" && has "$step9_part" "yq '"'"'.verified_commit'"'"' '"'"'<task folder>/contract.before.yaml'"'"'" && ! has "$step9_part" "new-section"'

# Verify
assert "verify final review passes the contract path to the reviewer" 'has "$verify_final_review" "also give it the contract path"'
assert "verify final review reads the gate state with fm_get" 'has "$verify_final_review" "fm_get \"\$task_dir/contract-brief.md\" contract_file"'
assert "verify final review names each file" 'has "$verify_final_review" "If \`contract-brief.md\` does not exist" && has "$verify_final_review" "If \`agents/reviewer.md\` is not there" && ! has "$verify_final_review" "If the file"'
assert "verify tells the reviewer to judge whether each ref shows its claim" 'has "$verify_final_review" "\`contract-refs.sh\` in step 1 already proved that every ref exists" && has "$verify_final_review" "whether each ref shows its claim"'
assert "verify runs contract-verify-draft.sh for a contract task" 'has "$verify_step1" "For a \`contract\` task" && has "$verify_step1" "contract-verify-draft.sh\" \"<repository folder>\" \"\$task_dir\" \"<contract path>\" \"<task_id>\" \"/tmp/wstack-evidence/<task_id>\""'
assert "Count the try sends a fix after a review to the reviewed-copy step" 'grep "^3\. Take the retry limit" "$verify" | grep -qF "If a review already ran, follow \"An edit after the last review\" for the fix."'
assert "a missing reviewed copy falls back to the whole draft" 'has "$verify_edit_part" "If the reviewed copy is missing, give the reviewer the whole draft."'
assert "verify: a new project needs sources in each section that needs them, and each answer as a plan item" 'has "$verify_final_review" "Each section that needs \`sources\` has them. Each answer under \`## Contract changes\` in the spec is a plan item under \`planned\`." && ! has "$verify_final_review" "has content"'
assert "execute: a new project writes each answer as a plan item with empty section items" 'has "$contract_part" "Write each answer as an item under \`planned\`" && has "$contract_part" "A plan item needs no \`refs\`." && has "$contract_part" "leave the \`items\` of every section empty"'
assert "confirmation: new-project answers feed plan items and sources" 'has "$write_part" "Execute writes each answer as a plan item under \`planned\`, and the globs as the \`sources\` of the section." && ! has "$write_part" "until the section has content"'
assert "verify step 2 reads base_branch from contract-brief.md" 'grep "^2\. Stale references" "$verify" | grep -qF "fm_get \"\$task_dir/contract-brief.md\" base_branch" && ! grep -qF "comes from the contract frontmatter" "$verify"'
assert "confirmation asks no question about open_questions" 'has "$write_part" "Skip \`open_questions\`, because it holds only what a later task finds."'
assert "verify re-reviews an edit after the last review with the diff only" 'has "$verify_edit_part" "a fix for a non-blocking finding" && has "$verify_edit_part" "diff -u \"\$task_dir/contract.draft.reviewed.yaml\" \"\$task_dir/contract.draft.yaml\"" && has "$verify_edit_part" "only the diff of the edit" && has "$verify_final_review" "An edit after the last review"'

# Deliver: Contract write-back
assert "deliver has Contract write-back heading" 'grep -qxF "## Contract write-back" "$deliver"'
assert "deliver has Pending items heading" 'grep -qxF "## Pending items" "$deliver"'
for needle in 'contract-brief.md' 'contract.patch.yaml' 'remove_planned:' '=== PATCH ===' 'pending-add' 'next-decision-id' \
  'templates/decision.md' 'docs/adr/' 'contract write-back' '{{tasks_dir}}'; do
  assert "Contract write-back names $needle" 'has "$writeback_part" "$needle"'
done
assert "write-back: None patch still writes decisions" 'has "$writeback_part" "Decisions do not depend on the patch"'
assert "write-back: decision files are written under the lock" 'has "$writeback_part" "next-decision-id \"\$decisions_dir\""'
assert "write-back: the reuse glob needs a 4-digit id before the slug" 'has "$writeback_part" "\"\$decisions_dir\"/[0-9][0-9][0-9][0-9]-\"\$(basename \"\$draft\")\""'
assert "write-back: a retry reuses the decision file of the same slug and task" 'has "$writeback_part" "grep -qF \"/\$(basename \"\$task_dir\")/spec]]\"" && has "$writeback_part" "so a retry makes no second copy"'
assert "decision template links the tasks folder" 'grep -qF "task: \"[[{{tasks_dir}}/{{task_id}}/spec]]\"" "$decision_template"'

# Deliver: Pending items
for needle in 'gh pr view' 'MERGED' 'CLOSED' 'OPEN' 'remove_planned' 'pending-remove'; do
  assert "Pending items names $needle" 'has "$pending_part" "$needle"'
done
p_lock="$(line_in "$pending_part" 'contract-edit.sh" lock')"
p_apply="$(line_in "$pending_part" 'contract-edit.sh" apply')"
assert "pending: lock before apply" '[ -n "$p_lock" ] && [ -n "$p_apply" ] && [ "$p_lock" -lt "$p_apply" ]'
assert "pending: trap unlock comes right after lock" 'printf "%s\n" "$pending_part" | grep -A1 -F "contract-edit.sh\" lock" | grep -qF "trap"'
assert "MERGED: a missing task folder keeps the item" 'has "$merged_part" "if the task folder of the item does not exist, keep the item"'
assert "pending: the list and base_branch come from the YAML" 'has "$pending_part" "yq -o json -I0 '"'"'.pending'"'"' \"\$contract_file\"" && has "$pending_part" "yq '"'"'.base_branch'"'"' \"\$contract_file\"" && ! has "$pending_part" "fm_get \"\$contract_file\""'
assert "MERGED: a missing patch skips the snapshot and apply lines" 'has "$merged_part" "If \`<task folder>/contract.patch.yaml\` does not exist, skip the three lines that name \`contract.writeback.before\` and the \`apply\` line."'
assert "MERGED: apply output is read from the call" 'has "$merged_part" "Read the keys and the ids from the output of the call"'
assert "MERGED: the undo ids come from the snapshot, so a rerun keeps them" 'has "$merged_part" "\"\$task_folder/contract.writeback.before.yaml\" | jq -r --argjson remove" && has "$merged_part" "The removed ids are the ids of the \`undo planned:\` line." && ! has "$merged_part" "planned removed:"'
assert "write-back: the patch is tested on a copy with a temp HOME" 'has "$writeback_part" "HOME=\"\$test_dir\" bash \"\$scripts/contract-edit.sh\" apply \"\$test_dir/\$(basename \"\$contract_file\")\" \"\$task_dir/contract.patch.yaml\""'
assert "write-back: a refused patch gets one more reader try, then a stop" 'has "$writeback_part" "Dispatch the reader once more with the same input and the stderr text" && has "$writeback_part" "If the second patch is refused too, stop as in \"Stop\""'
assert "Contract files: the undo record says to run the rebuild line" 'has "$files_part" "If it prints a \`rebuild the page:\` line, the user runs that command after the undo."'
assert "MERGED: the write-back snapshot is contract.writeback.before.yaml, with no plan snapshot" 'has "$merged_part" "[ -f \"\$task_folder/contract.writeback.before.yaml\" ] || cp \"\$contract_file\" \"\$task_folder/contract.writeback.before.new.yaml\"" && has "$merged_part" "mv \"\$task_folder/contract.writeback.before.new.yaml\" \"\$task_folder/contract.writeback.before.yaml\"" && ! has "$pending_part" "plan.writeback.before" && ! has "$pending_part" "delete-section" && ! has "$pending_part" "task_folder/contract.before"'
assert "MERGED undo uses apply with --sections and --planned" 'has "$merged_part" "set the undo of the \`contract write-back\` target to the undo command: \`bash '"'"'<scripts>/contract-edit.sh'"'"' apply '"'"'<contract_file>'"'"' '"'"'<task folder>/contract.writeback.before.yaml'"'"' --sections '"'"'<applied keys, joined by commas>'"'"' --planned '"'"'<removed ids, joined by commas>'"'"' --diagrams\`" && has "$merged_part" "leave out the \`--planned\` flag and its value" && has "$merged_part" "leave out the \`--sections\` flag and its value"'
assert "CLOSED: decision files of the task are withdrawn and logged" 'has "$closed_part" "fm_set \"\$decision_file\" status withdrawn" && has "$closed_part" "For each \`decision withdrawn:\` line, write a \`step\` line in \`run-log.md\`"'
assert "pending: a stuck item can be dropped without withdrawing decisions" 'has "$pending_part" "If the user says to drop the item, run \`pending-remove\` for its pull request" && has "$pending_part" "Do not withdraw its decisions."'
assert "pending: no new-section text is left, because the section keys are fixed" '! has "$pending_part" "new-section" && ! has "$pending_part" "adds the section at the end"'

# Each lock block runs in one shell: it needs set -e and a trap that unlocks.
for lock_file in "$confirmation" "$deliver"; do
  lock_blocks="$(grep -cF 'contract-edit.sh" lock' "$lock_file" || true)"
  trap_lines="$(grep -cF "trap 'bash \"\$scripts/contract-edit.sh\" unlock" "$lock_file" || true)"
  set_e_lines="$(grep -cx '[[:space:]]*set -e' "$lock_file" || true)"
  assert "$(basename "$lock_file"): every lock has a trap with unlock" '[ "$lock_blocks" -ge 1 ] && [ "$trap_lines" -eq "$lock_blocks" ]'
  assert "$(basename "$lock_file"): every lock block has set -e" '[ "$set_e_lines" -ge "$lock_blocks" ]'
  assert "$(basename "$lock_file"): no bare unlock line" '! grep -qE "^[[:space:]]*bash .*contract-edit.sh\" unlock" "$lock_file"'
done
assert "no plan heading loop is left" '! grep -qF "for heading in" "$confirmation" "$deliver" && ! grep -qF "<heading>" "$confirmation" "$deliver"'

# Execute: Contract work
assert "execute.md: Contract work after Thinking and ops work" '[ -n "$(grep -nxF "## Contract work" "$execute" | head -1)" ] && [ "$(grep -nxF "## Thinking and ops work" "$execute" | head -1 | cut -d: -f1)" -lt "$(grep -nxF "## Contract work" "$execute" | head -1 | cut -d: -f1)" ]'
for needle in 'contract.draft.yaml' 'decisions.draft/' 'templates/contract.yaml' 'disagreements.md' \
  'fetch origin' 'rev-parse' 'verified_commit' 'next-decision-id' 'contract-path.sh' 'repository not mapped: run /wstack:init-service'; do
  assert "execute.md Contract work names $needle" 'has "$contract_part" "$needle"'
done
assert "SKILL.md launch names contract work type" 'grep -qF "\`contract\`" "$launch"'
step6_line="$(printf '%s\n' "$contract_part" | grep -E '^6\. ')"
step3_line="$(printf '%s\n' "$contract_part" | grep -E '^3\. ')"
step7_line="$(printf '%s\n' "$contract_part" | grep -E '^7\. ')"
assert "execute writes contract.draft.yaml from templates/contract.yaml" 'has "$step6_line" "verified_commit" && has "$step6_line" "Write \`contract.draft.yaml\` from \`\${CLAUDE_PLUGIN_ROOT}/templates/contract.yaml\`"'
assert "execute links repo ADRs as a team_docs glob and makes no decision file for them" 'has "$contract_part" "add the glob \`docs/adr/**\` to the \`sources\` of \`team_docs\`. Make no decision file for it."'
assert "execute puts wStack settings in YAML fields, not decision files" 'has "$contract_part" "The spec choices that set how wStack works, such as \`base_branch\` and the \`ignore\` list, are YAML fields, not decision files."'
assert "execute writes disagreements.md" 'has "$step7_line" "Write \`\$task_dir/disagreements.md\`" && ! has "$contract_part" "open_questions\` in the contract"'
assert "execute fetches another repo before it cites it" 'has "$contract_part" "git -C \"<clone>\" fetch origin \"<default branch>\"" && has "$contract_part" "\`<owner>/<repo>@<commit>:path:lines\`" && has "$contract_part" "If the fetch fails, cite the local commit"'
assert "execute quotes a ref that holds a comma" 'has "$step6_line" "put a ref that holds a comma in double quotes"'
assert "execute: step 3 keeps the SHA for step 6" 'has "$step3_line" "step 6"'
assert "execute: new-project questions are not in Execute" '! has "$contract_part" "Ask the user one question"'
assert "execute: existing project reads the list from the spec" 'has "$contract_part" "code areas that the spec lists"'
for placeholder in $(grep -ho '{{[a-z_]*}}' "$contract_template" | tr -d '{}' | sort -u); do
  assert "execute: step 6 says how to fill $placeholder" 'has "$step6_line" "$placeholder"'
done
assert "execute: org_kebab uses the handover kebab rule" 'has "$step6_line" "insert \`-\` before each uppercase letter except the first, lowercase the result, and collapse repeated \`-\`" && has "$step6_line" "\`BreakinCode\` gives \`breakin-code\`" && has "$(grep -F "Algorithm:" "$repo_root/skills/create-handover/SKILL.md")" "insert \`-\` before each uppercase letter (except position 0), lowercase the result, collapse repeated \`-\`"'
assert "execute: org_kebab is defined" 'has "$step6_line" "\`{{org_kebab}}\` is the \`<ORG>\` folder of the contract path"'

# Deliver: Contract files
assert "confirmation has the Vault docs spec section" 'grep -qF "## Vault docs" "$confirmation"'
assert "deliver Contract files names docs-archive.txt" 'has "$files_part" "docs-archive.txt"'
assert "contract-deliver.sh names docs-archive.txt" 'grep -qF "docs-archive.txt" "$repo_root/scripts/contract-deliver.sh"'
assert "deliver has Contract files heading" 'grep -qxF "### Contract files" "$deliver"'
for needle in 'contract-path.sh' 'contract-deliver.sh" write' 'contract-files.txt' 'contract.draft.yaml' 'decisions.draft/' 'disagreements.md' '## Doc and code disagree' 'Exit 4'; do
  assert "deliver Contract files names $needle" 'has "$files_part" "$needle"'
done
assert "Contract files: <workspace_cwd> has a source" 'has "$files_part" "\`<workspace_cwd>\` is the \`workspace_cwd\` value in the spec frontmatter."'
assert "Contract files: no Markdown draft and no inline block is left" '! has "$files_part" "contract.draft.md" && ! has "$files_part" "plan.draft.md" && ! has "$files_part" "contract-edit.sh\" lock"'
assert "Contract files records the contract-deliver.sh undo" 'has "$files_part" "{\"target\":\"write the contract files\",\"url\":\"<contract_file>\",\"undo\":\"bash <scripts>/contract-deliver.sh undo '"'"'<task folder>'"'"' '"'"'<contract_file>'"'"' <task_id>\"}"'

# Deliver: Finish
finish_part="$(slice "$deliver" '## Finish' '## Stop')"
finish_where_part="$(slice "$deliver" '1. Fill `## What shipped`' '2. If `HERDR_ENV`')"
finish_step8="$(printf '%s\n' "$finish_part" | grep '^8\. ')"
assert "report Where holds the tree" 'has "$finish_where_part" "Write \`## Where\` in this order" && has "$finish_where_part" "\`NEW\`, \`REPLACED\`, \`MOVED\`, or \`UNCHANGED\`" && has "$finish_where_part" "the \`new:\`, \`replaced:\`, \`moved:\`, and \`unchanged:\` lines in \`\$task_dir/contract-files.txt\`" && has "$finish_where_part" "build it from the \`targets\` list"'
assert "report Where names each unchanged repository, the open commands, and the reading order" 'has "$finish_where_part" "\`<repository folder>: no change\`" && has "$finish_where_part" "\`open '"'"'<review.html>'"'"'\`" && has "$finish_where_part" "\$HOME/.wstack/pages/<task_id>/review.html" && has "$finish_where_part" "\`open '"'"'<contract page>'"'"'\`" && has "$finish_where_part" "\$HOME/.wstack/pages/contracts/<app_name>.html" && has "$finish_where_part" "Cmd+O" && has "$finish_where_part" "\`## Guided diff\` in \`review.md\`"'
assert "Finish step 8 gives the file tree, unchanged repos, and open commands" 'has "$finish_step8" "the file tree" && has "$finish_step8" "each repository that did not change" && has "$finish_step8" "the open commands" && has "$finish_step8" "the reading order" && has "$finish_step8" "Ask nothing."'

# Agents, templates, and docs
assert "reader writes no code fence in the reply" 'sed -n "/^## Reply/,\$p" "$reader" | grep -qF "Write no code fence in the reply."'
assert "reader writes stale sections from the code" 'grep -qF "If the code does not show a fact, leave the fact out." "$reader"'
assert "reference bash blocks use no CLAUDE_PLUGIN_ROOT" '! awk "/^[[:space:]]*\`\`\`bash/{b=1;next} /^[[:space:]]*\`\`\`/{b=0} b" "$confirmation" "$execute" "$verify" | grep -qF "CLAUDE_PLUGIN_ROOT"'
for key in app_name repo base_branch verified_commit verified_at pending ignore tags; do
  assert "contract template has $key" 'grep -q "^$key:" "$contract_template"'
  assert "README names the contract key $key" 'grep -F "The top keys are" "$repo_root/README.md" | grep -qF "\`$key\`"'
done
for section in team_docs abilities interfaces depends_on; do
  assert "contract template: $section has sources" '[ "$(yq ".sections.$section | has(\"sources\")" "$contract_template")" = true ]'
done
for section in consumers gotchas open_questions; do
  assert "contract template: $section has no sources" '[ "$(yq ".sections.$section | has(\"sources\")" "$contract_template")" = false ]'
done
assert "templates/contract.md and templates/plan.md are gone" '[ ! -e "$repo_root/templates/contract.md" ] && [ ! -e "$repo_root/templates/plan.md" ]'
assert "README states the sources rule of Ruling 4" 'grep -qF "\`team_docs\`, \`abilities\`, \`interfaces\`, and \`depends_on\` list their \`sources\` globs" "$repo_root/README.md"'
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
for eval_name in confirm-stale-contract gate-applies-merged-patch; do
  assert "eval $eval_name builds a code task folder and resumes it, because outside herdr a launch hands the code task off" 'grep -qF -- "--work-type code" "$repo_root/evals/$eval_name/prompt.md" && grep -qF "/wstack:start-task --task 2026-11-22-" "$repo_root/evals/$eval_name/prompt.md" && ! grep -qF "/wstack:start-task in REPO" "$repo_root/evals/$eval_name/prompt.md"'
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
assert "init-service never runs work mode and prints the resume command outside herdr" 'has "$init_contract_part" "Never run work mode in this session." && has "$init_contract_part" "created, not launched (not inside herdr)" && has "$init_contract_part" "claude \"/wstack:start-task --task <task_id>\""'
assert "init-service maps the launch exit codes" 'has "$init_contract_part" "exit 5" && has "$init_contract_part" "exit 1, 4, or 6" && has "$init_contract_part" "cleanup hint"'
assert "init-service checks the file explicitly and runs gh from the repo" 'has "$init_contract_part" "file=yes" && has "$init_contract_part" "from \`\$REPO_ROOT\`"'
assert "init-service reads contract-check status for exit 0 or 1" 'has "$init_contract_part" "Exit 0 or 1 prints a \`status:\` line." && has "$init_contract_part" "Exit 2 or 3 is an error"'
assert "Contract: line appears only in Phase 8 text and the Phase 9 report block" '[ "$(grep -c "^    Contract: " "$init_skill")" = 1 ] && has "$init_report_part" "    Contract: "'
assert "init-service names the contract.yaml path" 'has "$init_contract_part" "\`<app_name>.contract.yaml\`" && has "$init_contract_part" "An old \`<app_name>.md\` contract does not count"'
assert "init-service report has a Contract: line" 'has "$init_report_part" "Contract:"'

# Contract diagrams: build path
draw_skill="$repo_root/skills/draw-contract/SKILL.md"
reviewer_agent="$repo_root/agents/reviewer.md"
for needle in 'diagram-design:diagram-design' 'faithful' 'contract-open.sh' '--contract' 'contract-render.sh' 'keep the default style'; do
  assert "draw-contract names $needle" 'grep -qF -- "$needle" "$draw_skill"'
done
assert "draw-contract allows the dependency merge" 'grep -qF "the zone around the parts" "$draw_skill" && grep -qF "same dependency" "$draw_skill"'
assert "draw-contract allows the caller merge" 'grep -qF "the count" "$draw_skill" && grep -qF "same part" "$draw_skill" && grep -qF "three or more callers" "$draw_skill" && grep -qF "In a \`flow\`:" "$draw_skill"'
assert "draw-contract draws a sibling layer beside the nested layers" 'grep -qF "sibling: true" "$draw_skill" && grep -qF "never as a ring around them" "$draw_skill"'
assert "execute fills diagrams.flow and architecture" 'has "$(cat "$execute")" "diagrams.flow" && has "$(cat "$execute")" "architecture"'
assert "reviewer judges diagrams.flow" 'grep -qF "diagrams.flow" "$reviewer_agent"'
assert "reviewer checks every network peer in depends_on" 'grep -qF "network peer" "$reviewer_agent"'
for needle in 'http.server' 'file://' 'data-id'; do
  assert "draw-contract browser note names $needle" 'grep -qF -- "$needle" "$draw_skill"'
done
assert "verify names diagrams" 'grep -qF "diagrams" "$verify"'
for needle in 'contract-diagram.sh stale' 'diagrams.backup' 'diagrams.drawn.txt' '/wstack:draw-contract'; do
  assert "deliver names $needle" 'has "$(cat "$deliver")" "$needle"'
done

# Contract diagrams: update path
assert "step 9 uses its own diagram list names" 'has "$step9_part" "diagrams.gate.drawn.txt" && has "$step9_part" "diagrams.gate.backup" && ! has "$step9_part" "diagrams.drawn.txt"'
assert "Pending items uses its own diagram list names" 'has "$pending_part" "diagrams.writeback.drawn.txt" && has "$pending_part" "diagrams.writeback.backup" && ! has "$pending_part" "diagrams.drawn.txt"'
assert "redraw runs only after a diagrams line" 'has "$step9_part" "If \`apply\` printed the line \`diagrams\`, redraw" && has "$pending_part" "If \`apply\` printed the line \`diagrams\`, redraw" && grep -qF "If it printed the line \`diagrams\`, redraw" "$retro_skill"'
assert "reader patch holds a diagrams block" 'grep -qF "diagrams:" "$reader"'
for needle in 'has("diagrams")' '--diagrams' 'contract-diagram.sh" stale' "contract-diagram.sh' restore"; do
  assert "step 9 names $needle" 'has "$step9_part" "$needle"'
done
for needle in '--diagrams' "contract-diagram.sh' restore"; do
  assert "Pending items names $needle" 'has "$pending_part" "$needle"'
done
for needle in '--diagrams' 'contract-diagram.sh" stale'; do
  assert "run-retro names $needle" 'grep -qF -- "$needle" "$retro_skill"'
done

# glob_blocks_without_null_glob <file>...: counts bash blocks that loop over a glob and lack the setopt line
glob_blocks_without_null_glob() {
  awk '/^[[:space:]]*```bash/ { in_block = 1; has_glob = 0; has_setopt = 0; next }
    /^[[:space:]]*```/ { if (in_block && has_glob && !has_setopt) missing++; in_block = 0 }
    in_block && /setopt NULL_GLOB/ { has_setopt = 1 }
    in_block && /for [a-z_]+ in .*\*/ { has_glob = 1 }
    END { print missing + 0 }' "$@"
}
assert "every bash block with a glob for loop sets NULL_GLOB (zsh)" '[ "$(glob_blocks_without_null_glob "$confirmation" "$execute" "$deliver")" = 0 ]'

assert "execute.md names contract-ref-shift.sh" 'grep -qF "contract-ref-shift.sh" "$execute"'
assert "execute.md fetches the clones, then writes each shift ref" 'grep -qF "The script does not fetch." "$execute" && grep -qF -- "--mapping-from \"<contract path>\"" "$execute" && grep -qF "For each \`shift: <ref> -> <new ref>\` line" "$execute"'
assert "execute.md says the reviewer judges the whole draft" 'grep -qF "The reviewer still judges the whole draft." "$execute"'

finish
