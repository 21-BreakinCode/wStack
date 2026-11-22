#!/usr/bin/env bash
# Runs the contract lock blocks of the skill text in a test world (Ruling 26).
# Each block runs in bash, and in zsh when zsh exists, because the Bash tool runs the user's shell.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
confirmation="$repo_root/skills/start-task/references/confirmation.md"
deliver="$repo_root/skills/deliver-task/SKILL.md"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"; mkdir -p "$HOME"
task_id=2026-11-22-add-health
weird_heading="Drop the \`rm -rf canary\` cleanup and \$(rm -rf canary) for O'Brien"
test_shells=bash
if command -v zsh >/dev/null 2>&1; then test_shells="bash zsh"; fi

# block_after <file> <text>: the first bash block after the first line that holds <text>
block_after() {
  awk -v marker="$2" '
    !found && index($0, marker) { found = 1; next }
    found && /^[[:space:]]*```bash[[:space:]]*$/ { inside = 1; next }
    inside && /^[[:space:]]*```[[:space:]]*$/ { exit }
    inside { sub(/^[[:space:]]+/, ""); print }
  ' "$1"
}
# code_after <file> <text>: the first code span after <text> on its line
code_after() {
  awk -v marker="$2" 'i = index($0, marker) { rest = substr($0, i + length(marker)); sub(/^[^`]*`/, "", rest); sub(/`.*$/, "", rest); print rest; exit }' "$1"
}
# replace_all <text> <literal> <replacement>: no regex, no escapes
replace_all() {
  FROM="$2" TO="$3" awk 'BEGIN { RS = "\001" } {
    from = ENVIRON["FROM"]; to = ENVIRON["TO"]; out = ""; rest = $0
    while ((i = index(rest, from)) > 0) { out = out substr(rest, 1, i - 1) to; rest = substr(rest, i + length(from)) }
    printf "%s%s", out, rest
  }' < <(printf '%s' "$1")
}
# quote <text>: the house rule for text inside single quotes, each ' becomes '\''
quote() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
fill() {  # <text> then <placeholder> <value> pairs
  local text="$1"; shift
  while [ "$#" -ge 2 ]; do text="$(replace_all "$text" "$1" "$2")"; shift 2; done
  printf '%s\n' "$text"
}
raw_block() {  # <block name>: the block text as the skill shows it
  case "$1" in
    step9) block_after "$confirmation" '9. If `$task_dir/contract-brief.md`' ;;
    files) block_after "$deliver" '### Contract files' ;;
    pending-add) block_after "$deliver" '2. Add the pending item.' ;;
    decisions) block_after "$deliver" '3. Write the decision files.' ;;
    merged) block_after "$deliver" '- `MERGED`:' ;;
    closed) block_after "$deliver" '- `CLOSED`:' ;;
  esac
}
filled_block() {  # <block name> <task folder> <plan heading> <pr> [plugin root]
  local root="${5:-$repo_root}"
  fill "$(raw_block "$1")" '${CLAUDE_PLUGIN_ROOT}' "$root" '<scripts folder>' "$root/scripts" '<task folder>' "$(quote "$2")" \
    '<contract_file>' "$(quote "$CONTRACT")" '<task_id>' "$task_id" '<pr>' "$4" '<heading>' "$(quote "$3")" '<task>' "$(basename "$2")"
}
setup_world() {  # <name>: a fresh world in $work_dir/<name>, with a plan and a canary folder
  world_dir="$work_dir/$1"
  source "$(bash "$repo_root/tests/fixtures/contract/setup.sh" "$world_dir")"
  contract_folder="$(dirname "$CONTRACT")"
  printf '# svc plan\n\n## Gate item\n\nx\n\n## B item\n\ny\n\n## %s\n\nz\n\n## Keep me\n\nw\n' "$weird_heading" >"$contract_folder/plan.md"
  mkdir -p "$world_dir/canary"
}
write_brief() {  # <task folder> <stale_sections JSON>
  mkdir -p "$1"
  printf -- '---\ncontract_file: %s\nbase_branch: main\nchecked_commit: checked123\nstale_sections: %s\n---\n\nBrief\n' "$CONTRACT" "$2" >"$1/contract-brief.md"
}
prepare_inputs() {  # <task folder>: every input file that the blocks read
  local task="$1"
  write_brief "$task" '["Interfaces"]'
  mkdir -p "$task/decisions.draft" "$task/decisions.writeback"
  printf '## Interfaces\n<!-- sources: api/** -->\nA gate text.\n\n## Remove from plan\n- Gate item\n' >"$task/contract.gate-patch.md"
  printf '## Interfaces\n<!-- sources: api/** -->\nA write-back text.\n\n## Remove from plan\n- %s\n' "$weird_heading" >"$task/contract.patch.md"
  printf -- '---\napp_name: svc\nbase_branch: main\nverified_commit: %s\n---\n\n# svc contract\n\n## Abilities\nNew text.\n' "$FIRST_COMMIT" >"$task/contract.draft.md"
  printf '# svc plan\n' >"$task/plan.draft.md"
  printf -- '---\nid: "0001"\n---\n\n# 0001 Baseline\n' >"$task/decisions.draft/0001-baseline.md"
  printf -- '---\nid: "{{id}}"\ntask: "[[Tasks/%s/spec]]"\n---\n\n# {{id}} Serve health without auth\n' "$(basename "$task")" >"$task/decisions.writeback/serve-health.md"
  fm_set "$CONTRACT" pending '[{"pr":7,"task":"task-a"}]'
}
run_block() {  # <filled block> <shell>: runs it in the world folder, sets rc and out
  rc=0; out="$(cd "$world_dir" && "$2" -c "$1" 2>&1)" || rc=$?
}
section_of() { awk -v name="$2" '/^## /{ inside = (substr($0, 4) == name); next } inside' "$1"; }
body_of() { awk 'n >= 2 { print } /^---$/ { n++ }' "$1"; }
snapshot() { find "$VAULT" -print | LC_ALL=C sort; find "$VAULT" -type f -exec shasum {} + | LC_ALL=C sort; }

all_blocks="step9 files pending-add decisions merged closed"
for block in $all_blocks; do
  assert "block $block is in the skill text" 'raw_block "$block" | grep -qF "contract-edit.sh\" lock"'
done

echo "busy lock: exit 4 and no file changes"
for shell in $test_shells; do
  for block in $all_blocks; do
    (
      setup_world "busy-$shell-$block"
      task="$VAULT/Tasks/task-a"; prepare_inputs "$task"
      mkdir "$CONTRACT.lock"
      before="$(snapshot)"
      run_block "$(filled_block "$block" "$task" "$weird_heading" 7)" "$shell"
      same=no; [ "$(snapshot)" != "$before" ] || same=yes
      echo "$rc $same" >"$work_dir/busy-$shell-$block.result"
    ) &
  done
done
wait
for shell in $test_shells; do
  for block in $all_blocks; do
    result="$(cat "$work_dir/busy-$shell-$block.result" 2>/dev/null || echo missing)"
    assert "$shell $block: busy lock exits 4 and changes no file ($result)" '[ "$result" = "4 yes" ]'
  done
done

echo "failure after the lock: the trap unlocks"
broken_root="$work_dir/broken plugin"
mkdir -p "$broken_root"; cp -R "$repo_root/scripts" "$broken_root/scripts"
cat >"$broken_root/scripts/contract-edit.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\$1" in lock|unlock) exec bash "$repo_root/scripts/contract-edit.sh" "\$@" ;; esac
echo "contract-edit.sh: broken for the test" >&2; exit 9
EOF
for shell in $test_shells; do
  for block in $all_blocks; do
    setup_world "broken-$shell-$block"
    task="$VAULT/Tasks/task-a"; prepare_inputs "$task"
    run_block "$(filled_block "$block" "$task" "$weird_heading" 7 "$broken_root")" "$shell"
    assert "$shell $block: a failure after the lock exits non-zero, not 4 (rc $rc)" '[ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]'
    assert "$shell $block: the lock is gone after the failure" '[ ! -e "$CONTRACT.lock" ]'
  done
done

for shell in $test_shells; do
  echo "$shell: gate step 9 (I4, M1, I3)"
  setup_world "gate-$shell"
  task="$VAULT/Tasks/task-a"
  write_brief "$task" '["Abilities","Interfaces"]'
  printf '## Interfaces\n<!-- sources: api/** -->\nGET /health answers 200.\n\n## Remove from plan\n- %s\n' "$weird_heading" >"$task/contract.gate-patch.md"
  cp "$CONTRACT" "$world_dir/contract.orig"
  run_block "$(filled_block step9 "$task" "$weird_heading" 0)" "$shell"
  assert "$shell step 9: exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell step 9: patch applied" 'section_of "$CONTRACT" Interfaces | grep -qF "GET /health answers 200."'
  assert "$shell step 9: contract.before.md is the original" 'cmp -s "$task/contract.before.md" "$world_dir/contract.orig"'
  assert "$shell step 9 I4: verified_commit stays while Abilities has no patch block" '[ "$(fm_get "$CONTRACT" verified_commit)" = "$FIRST_COMMIT" ]'
  assert "$shell step 9 I4: the output names the section that stays stale" 'printf "%s\n" "$out" | grep -qxF "Abilities"'
  assert "$shell step 9 M1: the plan item is removed" '! grep -qxF "## $weird_heading" "$contract_folder/plan.md" && grep -qxF "## Keep me" "$contract_folder/plan.md"'
  assert "$shell step 9 M1: plan.before.md keeps the plan item" 'grep -qxF "## $weird_heading" "$task/plan.before.md"'
  assert "$shell step 9 M1: the output names the removed item" 'printf "%s\n" "$out" | grep -qF "plan item removed: $weird_heading"'
  assert "$shell step 9 I3: the heading text did not run" '[ -d "$world_dir/canary" ]'
  gate_undo="$(fill "$(code_after "$confirmation" 'The old-section command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task" '<applied names, joined by commas>' Interfaces)"
  cp "$CONTRACT" "$world_dir/contract.gated"
  run_block "$gate_undo" "$shell"
  assert "$shell step 9 A2-28: the logged contract undo restores Interfaces ($out)" '[ "$rc" = 0 ] && ! grep -qF "GET /health answers 200." "$CONTRACT" && section_of "$CONTRACT" Interfaces | grep -qxF "<!-- sources: api/** -->"'
  cp "$world_dir/contract.gated" "$CONTRACT"

  task="$VAULT/Tasks/task-a2"
  write_brief "$task" '["Interfaces"]'
  printf '## Interfaces\n<!-- sources: api/** -->\nGET /health answers 204.\n\n## Health checks\nGET /health is the probe.\n\n## Remove from plan\n- Gate item\n' >"$task/contract.gate-patch.md"
  run_block "$(filled_block step9 "$task" "Gate item" 0)" "$shell"
  assert "$shell step 9 I4: verified_commit moves when every stale section has a block" '[ "$rc" = 0 ] && [ "$(fm_get "$CONTRACT" verified_commit)" = checked123 ]'
  run_block "$(filled_block step9 "$task" "Gate item" 0)" "$shell"
  assert "$shell step 9 second run: exit 0, and the snapshot still lacks the new section" '[ "$rc" = 0 ] && ! grep -qxF "## Health checks" "$task/contract.before.md"'
  undo_old="$(fill "$(code_after "$confirmation" 'The old-section command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task" '<applied names, joined by commas>' Interfaces)"
  undo_new="$(fill "$(code_after "$confirmation" 'once for each new name:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" '<name>' 'Health checks')"
  undo_commit="$(fill "$(code_after "$confirmation" 'add the commit command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<verified_commit>' "$(fm_get "$task/contract.before.md" verified_commit)")"
  run_block "$undo_old && $undo_new && $undo_commit" "$shell"
  assert "$shell step 9 undo: exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell step 9 undo: verified_commit is back, so the drift shows again" '[ "$(fm_get "$CONTRACT" verified_commit)" = "$FIRST_COMMIT" ]'
  assert "$shell step 9 undo: the new section is gone and Interfaces is back" '! grep -qxF "## Health checks" "$CONTRACT" && section_of "$CONTRACT" Interfaces | grep -qF "GET /health answers 200." && ! grep -qF "answers 204" "$CONTRACT"'

  echo "$shell: MERGED and its undo (I2, I3)"
  setup_world "merge-$shell"
  fm_set "$CONTRACT" pending '[{"pr":7,"task":"task-a"},{"pr":8,"task":"task-b"}]'
  task_a="$VAULT/Tasks/task-a"; task_b="$VAULT/Tasks/task-b"; mkdir -p "$task_b"
  write_brief "$task_a" '["Interfaces"]'
  printf '## Interfaces\n<!-- sources: api/** -->\nA gate text.\n\n## Remove from plan\n- Gate item\n' >"$task_a/contract.gate-patch.md"
  run_block "$(filled_block step9 "$task_a" "Gate item" 0)" "$shell"
  assert "$shell task A gate: exit 0" '[ "$rc" = 0 ]'
  printf '## Interfaces\n<!-- sources: api/** -->\nB edit text.\n\n## Remove from plan\n- B item\n' >"$task_b/contract.patch.md"
  run_block "$(filled_block merged "$task_b" "B item" 8)" "$shell"
  assert "$shell task B MERGED: exit 0" '[ "$rc" = 0 ]'
  printf '## Interfaces\n<!-- sources: api/** -->\nA write-back text.\n\n## Health checks\nA new section.\n\n## Remove from plan\n- %s\n' "$weird_heading" >"$task_a/contract.patch.md"
  run_block "$(filled_block merged "$task_a" "$weird_heading" 7)" "$shell"
  assert "$shell task A MERGED: exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell task A MERGED I3: the heading text did not run" '[ -d "$world_dir/canary" ]'
  assert "$shell task A MERGED I3: the plan item is removed" '! grep -qxF "## $weird_heading" "$contract_folder/plan.md"'
  assert "$shell task A MERGED: the pending item is gone" '[ "$(fm_get "$CONTRACT" pending)" = "[]" ]'
  assert "$shell task A MERGED: the write-back text is in" 'section_of "$CONTRACT" Interfaces | grep -qF "A write-back text."'
  undo_contract="$(fill "$(code_after "$deliver" 'The contract part is')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task_a" '<applied names, joined by commas>' Interfaces)"
  undo_plan="$(fill "$(code_after "$deliver" 'The plan part is')" '<scripts>' "$repo_root/scripts" '<contract folder>' "$contract_folder" \
    '<task folder>' "$task_a" '<removed headings, joined by commas>' "$(quote "$weird_heading")")"
  undo_new="$(fill "$(code_after "$deliver" 'add the new-section part')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" '<name>' 'Health checks')"
  run_block "$undo_contract" "$shell"; undo_contract_rc="$rc"
  run_block "$undo_plan" "$shell"; undo_plan_rc="$rc"
  run_block "$undo_new" "$shell"; undo_new_rc="$rc"
  assert "$shell undo: all parts exit 0" '[ "$undo_contract_rc" = 0 ] && [ "$undo_plan_rc" = 0 ] && [ "$undo_new_rc" = 0 ]'
  assert "$shell undo: the new section of the write-back is gone" '! grep -qxF "## Health checks" "$CONTRACT"'
  assert "$shell undo I2: the edit of task B stays" 'section_of "$CONTRACT" Interfaces | grep -qF "B edit text."'
  assert "$shell undo I2: the write-back text of task A is gone" '! grep -qF "A write-back text." "$CONTRACT"'
  assert "$shell undo: the plan item is back" 'grep -qxF "## $weird_heading" "$contract_folder/plan.md"'
  assert "$shell undo: the plan removals of the gate and of task B stay" '! grep -qxF "## B item" "$contract_folder/plan.md" && ! grep -qxF "## Gate item" "$contract_folder/plan.md"'
  assert "$shell undo I3: the heading text did not run" '[ -d "$world_dir/canary" ]'

  echo "$shell: CLOSED"
  setup_world "closed-$shell"
  fm_set "$CONTRACT" pending '[{"pr":9,"task":"task-c"}]'
  cp "$CONTRACT" "$world_dir/contract.orig"
  mkdir -p "$contract_folder/decisions"
  printf -- '---\nid: "0001"\nstatus: accepted\ntask: "[[Tasks/task-c/spec]]"\n---\n\n# 0001 C choice\n' >"$contract_folder/decisions/0001-c-choice.md"
  printf -- '---\nid: "0002"\nstatus: accepted\ntask: "[[Tasks/task-d/spec]]"\n---\n\nSee [[Tasks/task-c/spec]].\n' >"$contract_folder/decisions/0002-d-choice.md"
  run_block "$(filled_block closed "$VAULT/Tasks/task-c" "" 9)" "$shell"
  assert "$shell CLOSED: exit 0, pending empty, body unchanged" '[ "$rc" = 0 ] && [ "$(fm_get "$CONTRACT" pending)" = "[]" ] && [ "$(body_of "$CONTRACT")" = "$(body_of "$world_dir/contract.orig")" ]'
  assert "$shell CLOSED A2-24: the decision of the closed task is withdrawn" '[ "$(fm_get "$contract_folder/decisions/0001-c-choice.md" status)" = withdrawn ] && printf "%s\n" "$out" | grep -qxF "decision withdrawn: $contract_folder/decisions/0001-c-choice.md"'
  assert "$shell CLOSED A2-24: a decision of another task stays accepted" '[ "$(fm_get "$contract_folder/decisions/0002-d-choice.md" status)" = accepted ]'

  echo "$shell: write-back decision files (M6)"
  setup_world "decisions-$shell"
  task="$VAULT/Tasks/task-a"; prepare_inputs "$task"
  mkdir -p "$contract_folder/decisions"
  printf -- '---\nid: "0001"\ntask: "[[Tasks/task-z/spec]]"\n---\n\n# 0001 Serve health from another task\n' >"$contract_folder/decisions/0001-serve-health.md"
  run_block "$(filled_block decisions "$task" "" 0)" "$shell"
  assert "$shell decisions: exit 0 and the next id is used ($out)" '[ "$rc" = 0 ] && grep -qxF "id: \"0002\"" "$contract_folder/decisions/0002-serve-health.md"'
  printf '\nThe retry wrote the draft again with new words.\n' >>"$task/decisions.writeback/serve-health.md"
  run_block "$(filled_block decisions "$task" "" 0)" "$shell"
  assert "$shell decisions A2-29: a retry keeps the id and makes no copy ($out)" '[ "$rc" = 0 ] && [ ! -e "$contract_folder/decisions/0003-serve-health.md" ] && printf "%s\n" "$out" | grep -qxF "decision file: $contract_folder/decisions/0002-serve-health.md"'

  echo "$shell: write-back decisions whose slugs end alike"
  setup_world "slugs-$shell"
  task="$VAULT/Tasks/task-t"; write_brief "$task" '[]'; mkdir -p "$task/decisions.writeback"
  for slug in auth-token token; do
    printf -- '---\nid: "{{id}}"\ntask: "[[Tasks/task-t/spec]]"\n---\n\n# {{id}} %s\n' "$slug" >"$task/decisions.writeback/$slug.md"
  done
  run_block "$(filled_block decisions "$task" "" 0)" "$shell"
  assert "$shell decisions: auth-token and token each get a file ($out)" '[ "$rc" = 0 ] && [ -f "$contract_folder/decisions/0001-auth-token.md" ] && [ -f "$contract_folder/decisions/0002-token.md" ]'
  assert "$shell decisions: each file is printed once" '[ "$(printf "%s\n" "$out" | grep -c "^decision file: ")" = 2 ] && printf "%s\n" "$out" | grep -qxF "decision file: $contract_folder/decisions/0002-token.md"'

  echo "$shell: Contract files twice"
  setup_world "files-$shell"
  task="$VAULT/Tasks/$task_id"; prepare_inputs "$task"
  echo '# Old PRD' >"$contract_folder/PRD.md"
  cp "$CONTRACT" "$world_dir/contract.orig"
  files_block="$(filled_block files "$task" "" 0)"
  run_block "$files_block" "$shell"; first_rc="$rc"
  run_block "$files_block" "$shell"; second_rc="$rc"
  assert "$shell Contract files: both runs exit 0 ($out)" '[ "$first_rc" = 0 ] && [ "$second_rc" = 0 ]'
  assert "$shell Contract files: contract.before.md keeps the original" 'cmp -s "$task/contract.before.md" "$world_dir/contract.orig"'
  assert "$shell Contract files: the archive keeps the original" 'cmp -s "$contract_folder/_archive/$task_id/svc.md" "$world_dir/contract.orig" && [ -f "$contract_folder/_archive/$task_id/PRD.md" ]'
  assert "$shell Contract files: the new contract and decision are in" 'grep -qxF "New text." "$CONTRACT" && [ -f "$contract_folder/decisions/0001-baseline.md" ]'
  assert "$shell Contract files A2-19: the copied decision is listed once" '[ "$(cat "$task/decisions.copied.txt")" = 0001-baseline.md ]'
  # the recorded undo, step by step
  rm -f "$CONTRACT" "$contract_folder/plan.md"
  while IFS= read -r copied_name; do rm -f "$contract_folder/decisions/$copied_name"; done <"$task/decisions.copied.txt"
  for archived in "$contract_folder/_archive/$task_id"/*; do mv "$archived" "$contract_folder/"; done
  rm -rf "$contract_folder/_archive/$task_id"
  for empty_folder in "$contract_folder/_archive" "$contract_folder/decisions"; do rmdir "$empty_folder" 2>/dev/null || true; done
  cp "$task/contract.before.md" "$CONTRACT"
  assert "$shell Contract files undo: no empty decisions/ or _archive/ is left" '[ ! -e "$contract_folder/decisions" ] && [ ! -e "$contract_folder/_archive" ] && [ -f "$contract_folder/PRD.md" ]'

  for clash in other-name same-text; do
    echo "$shell: Contract files with a decision id clash ($clash)"
    setup_world "files-clash-$clash-$shell"
    task="$VAULT/Tasks/$task_id"; prepare_inputs "$task"
    mkdir -p "$contract_folder/decisions"
    if [ "$clash" = other-name ]; then echo other >"$contract_folder/decisions/0001-other.md"
    else cp "$task/decisions.draft/0001-baseline.md" "$contract_folder/decisions/"; fi
    before="$(snapshot)"
    run_block "$(filled_block files "$task" "" 0)" "$shell"
    assert "$shell Contract files A2-19 ($clash): exit 1 with the clash and no vault change ($out)" '[ "$rc" = 1 ] && printf "%s\n" "$out" | grep -qF "decision id 0001 already exists in decisions/" && [ "$(snapshot)" = "$before" ]'
  done

  for draft_state in missing empty; do
    echo "$shell: Contract files with $draft_state decisions.draft"
    setup_world "files-$draft_state-$shell"
    task="$VAULT/Tasks/$task_id"; prepare_inputs "$task"
    rm -rf "$task/decisions.draft"
    if [ "$draft_state" = empty ]; then mkdir "$task/decisions.draft"; fi
    run_block "$(filled_block files "$task" "" 0)" "$shell"
    assert "$shell Contract files, $draft_state decisions.draft: exit 0 ($out)" '[ "$rc" = 0 ]'
    assert "$shell Contract files, $draft_state decisions.draft: the contract is delivered" 'grep -qxF "New text." "$CONTRACT"'
    assert "$shell Contract files, $draft_state decisions.draft: no lock is left" '[ ! -e "$CONTRACT.lock" ]'
  done
done

retro_skill="$repo_root/skills/run-retro/SKILL.md"
retro_block() {  # <retro folder> <stale JSON> <chosen names, one per line>
  fill "$(block_after "$retro_skill" 'D6. After the answer')" '<scripts folder>' "$repo_root/scripts" '<retro folder>' "$1" '<retro name>' 2026-W47 \
    '<contract file>' "$(quote "$CONTRACT")" '<checked commit>' checked123 '<stale_sections JSON>' "$2" '<chosen section names, one per line>' "$3"
}
for shell in $test_shells; do
  echo "$shell: run-retro contract drift block"
  setup_world "retro-$shell"
  retro_dir="$VAULT/Retros"; mkdir -p "$retro_dir"
  printf '## Interfaces\n<!-- sources: api/** -->\nRetro interfaces text.\n\n## Abilities\n<!-- sources: cmd/** -->\nRetro abilities text.\n' >"$retro_dir/2026-W47.contract-patch.md"
  cp "$CONTRACT" "$world_dir/contract.orig"
  run_block "$(retro_block "$retro_dir" '["Abilities","Interfaces"]' 'Interfaces')" "$shell"
  assert "$shell retro: only some sections chosen, exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell retro: the chosen section is applied, the other is not" 'section_of "$CONTRACT" Interfaces | grep -qF "Retro interfaces text." && ! grep -qF "Retro abilities text." "$CONTRACT"'
  assert "$shell retro: verified_commit does not move" '[ "$(fm_get "$CONTRACT" verified_commit)" = "$FIRST_COMMIT" ] && printf "%s\n" "$out" | grep -qxF "Abilities"'
  assert "$shell retro: the before copy is the original and no lock is left" 'cmp -s "$retro_dir/2026-W47.contract-before.md" "$world_dir/contract.orig" && [ ! -e "$CONTRACT.lock" ]'
  run_block "$(retro_block "$retro_dir" '["Abilities","Interfaces"]' $'Abilities\nInterfaces')" "$shell"
  assert "$shell retro: all stale sections chosen, verified_commit moves ($out)" '[ "$rc" = 0 ] && [ "$(fm_get "$CONTRACT" verified_commit)" = checked123 ] && grep -qF "Retro abilities text." "$CONTRACT"'
  assert "$shell retro: the second run keeps the first before copy" 'cmp -s "$retro_dir/2026-W47.contract-before.md" "$world_dir/contract.orig"'
  echo "$shell: run-retro all with a stale section that has no patch block"
  setup_world "retro-all-$shell"
  retro_dir="$VAULT/Retros"; mkdir -p "$retro_dir"
  printf '## Interfaces\n<!-- sources: api/** -->\nOnly interfaces.\n' >"$retro_dir/2026-W47.contract-patch.md"
  run_block "$(retro_block "$retro_dir" '["Abilities","Interfaces"]' 'Interfaces')" "$shell"
  assert "$shell retro all: applies the block it has, verified_commit stays, names the section left ($out)" '[ "$rc" = 0 ] && section_of "$CONTRACT" Interfaces | grep -qF "Only interfaces." && [ "$(fm_get "$CONTRACT" verified_commit)" = "$FIRST_COMMIT" ] && printf "%s\n" "$out" | grep -qxF "Abilities"'
  setup_world "retro-lock-$shell"
  mkdir "$CONTRACT.lock"
  run_block "$(retro_block "$retro_dir" '[]' 'Interfaces')" "$shell"
  assert "$shell retro: a busy lock exits 4" '[ "$rc" = 4 ]'
  rmdir "$CONTRACT.lock"
done

finish
