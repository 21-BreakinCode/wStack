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
setup_world() {  # <name>: a fresh world in $work_dir/<name>
  world_dir="$work_dir/$1"
  source "$(bash "$repo_root/tests/fixtures/contract/setup.sh" "$world_dir")"
  contract_folder="$(dirname "$CONTRACT")"
}
write_brief() {  # <task folder> <stale_sections JSON>
  mkdir -p "$1"
  printf -- '---\ncontract_file: %s\nbase_branch: main\nchecked_commit: 12e4567\nstale_sections: %s\n---\n\nBrief\n' "$CONTRACT" "$2" >"$1/contract-brief.md"
}
write_gate_patch() {  # <task folder> <interfaces item text, or empty for no section> [plan id to remove]
  local patch="$1/contract.gate-patch.yaml"
  : >"$patch"
  [ -z "$2" ] || ITEM_TEXT="$2" yq -n '.sections.interfaces = {"sources": ["api/**"], "items": [{"text": strenv(ITEM_TEXT), "refs": ["api/routes.go:1"]}]}' >"$patch"
  [ -z "${3:-}" ] || PLAN_ID="$3" yq -i -p yaml -o yaml '.remove_planned = [strenv(PLAN_ID)]' "$patch"
}
write_writeback_patch() {  # <task folder> <interfaces item text> <plan id to remove>
  ITEM_TEXT="$2" PLAN_ID="$3" yq -n '.sections.interfaces = {"sources": ["api/**"], "items": [{"text": strenv(ITEM_TEXT), "refs": ["api/routes.go:1"]}]} | .remove_planned = [strenv(PLAN_ID)]' >"$1/contract.patch.yaml"
}
set_pending() { PENDING="$1" yq -i '.pending = env(PENDING)' "$CONTRACT"; }  # <JSON list>
pending_of() { yq -o json -I0 '.pending' "$CONTRACT"; }
add_plan_items() { yq -i '.planned = [{"id": "gate-item", "title": "Gate item", "why": "x"}, {"id": "keep-me", "title": "Keep me", "why": "w"}]' "$CONTRACT"; }
plan_ids() { yq '[.planned[].id] | sort | join(",")' "$CONTRACT"; }
undo_ids() { printf '%s\n' "$out" | sed -n 's/^undo planned: //p'; }  # the ids on the block's undo planned: line
same_contract() { [ "$(yq -o json '.planned |= sort_by(.id)' "$1")" = "$(yq -o json '.planned |= sort_by(.id)' "$2")" ]; }
prepare_inputs() {  # <task folder>: every input file that the blocks read
  local task="$1"
  write_brief "$task" '["Interfaces"]'
  mkdir -p "$task/decisions.draft" "$task/decisions.writeback"
  write_gate_patch "$task" "A gate text."
  write_writeback_patch "$task" "A write-back text." keep-me
  printf -- '---\nid: "0001"\n---\n\n# 0001 Baseline\n' >"$task/decisions.draft/0001-baseline.md"
  printf -- '---\nid: "{{id}}"\ntask: "[[Tasks/%s/spec]]"\n---\n\n# {{id}} Serve health without auth\n' "$(basename "$task")" >"$task/decisions.writeback/serve-health.md"
  set_pending '[{"pr":7,"task":"task-a"}]'
}
run_block() {  # <filled block> <shell>: runs it in the world folder, sets rc and out
  rc=0; out="$(cd "$world_dir" && "$2" -c "$1" 2>&1)" || rc=$?
}
snapshot() { find "$VAULT" -print | LC_ALL=C sort; find "$VAULT" -type f -exec shasum {} + | LC_ALL=C sort; }

all_blocks="step9 pending-add decisions merged closed"
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
      run_block "$(filled_block "$block" "$task" "" 7)" "$shell"
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
    run_block "$(filled_block "$block" "$task" "" 7 "$broken_root")" "$shell"
    assert "$shell $block: a failure after the lock exits non-zero, not 4 (rc $rc)" '[ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]'
    assert "$shell $block: the lock is gone after the failure" '[ ! -e "$CONTRACT.lock" ]'
  done
done

for shell in $test_shells; do
  echo "$shell: gate step 9 (I4, M1)"
  setup_world "gate-$shell"; add_plan_items
  task="$VAULT/Tasks/task-a"
  write_brief "$task" '["abilities","interfaces"]'
  write_gate_patch "$task" "GET /health answers 200." gate-item
  cp "$CONTRACT" "$world_dir/contract.orig"
  run_block "$(filled_block step9 "$task" "" 0)" "$shell"
  assert "$shell step 9: exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell step 9: patch applied" '[ "$(yq ".sections.interfaces.items[0].text" "$CONTRACT")" = "GET /health answers 200." ]'
  assert "$shell step 9: contract.before.yaml is the original" 'cmp -s "$task/contract.before.yaml" "$world_dir/contract.orig"'
  assert "$shell step 9 I4: verified_commit stays while abilities has no patch section" '[ "$(yq .verified_commit "$CONTRACT")" = "$FIRST_COMMIT" ]'
  assert "$shell step 9 I4: the output names the section that stays stale" 'printf "%s\n" "$out" | grep -qxF "abilities"'
  assert "$shell step 9 M1: the plan item is removed" '[ "$(plan_ids)" = keep-me ]'
  assert "$shell step 9 M1: the output names the removed item for the undo" '[ "$(undo_ids)" = gate-item ]'
  run_block "$(filled_block step9 "$task" "" 0)" "$shell"
  assert "$shell step 9 rerun: exit 0, and the undo line still names the removed item ($out)" '[ "$rc" = 0 ] && [ "$(undo_ids)" = gate-item ]'
  gate_undo="$(fill "$(code_after "$confirmation" 'The undo command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task" '<applied keys, joined by commas>' interfaces '<removed ids, joined by commas>' "$(undo_ids)")"
  run_block "$gate_undo" "$shell"
  assert "$shell step 9: the logged undo restores interfaces and the plan item ($out)" '[ "$rc" = 0 ] && same_contract "$CONTRACT" "$world_dir/contract.orig"'

  echo "$shell: gate step 9 with every stale section patched, run twice"
  setup_world "gate2-$shell"
  task="$VAULT/Tasks/task-a2"
  write_brief "$task" '["interfaces"]'
  write_gate_patch "$task" "GET /health answers 204."
  cp "$CONTRACT" "$world_dir/contract.orig"
  run_block "$(filled_block step9 "$task" "" 0)" "$shell"
  assert "$shell step 9 I4: verified_commit moves to checked_commit, as a string" '[ "$rc" = 0 ] && [ "$(yq .verified_commit "$CONTRACT")" = 12e4567 ] && [ "$(yq ".verified_commit | tag" "$CONTRACT")" = "!!str" ]'
  run_block "$(filled_block step9 "$task" "" 0)" "$shell"
  assert "$shell step 9 second run: exit 0, and the snapshot keeps the text from before the gate" '[ "$rc" = 0 ] && cmp -s "$task/contract.before.yaml" "$world_dir/contract.orig"'
  undo_keys="$(fill "$(code_after "$confirmation" 'The undo command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task" '<applied keys, joined by commas>' interfaces " --planned '<removed ids, joined by commas>'" '')"
  undo_commit="$(fill "$(code_after "$confirmation" 'add the commit command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<verified_commit>' "$(yq .verified_commit "$task/contract.before.yaml")")"
  run_block "$undo_keys && $undo_commit" "$shell"
  assert "$shell step 9 undo: exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell step 9 undo: verified_commit is back, so the drift shows again" '[ "$(yq .verified_commit "$CONTRACT")" = "$FIRST_COMMIT" ]'
  assert "$shell step 9 undo: interfaces is back" '[ "$(yq ".sections.interfaces.items | length" "$CONTRACT")" = 0 ] && ! grep -qF "answers 204" "$CONTRACT"'

  echo "$shell: gate step 9 refused, a write-back lands, then accepted"
  setup_world "gate-refused-$shell"
  task="$VAULT/Tasks/task-a5"
  write_brief "$task" '["interfaces"]'
  printf 'sections:\n  interfaces:\n    items: []\n' >"$task/contract.gate-patch.yaml"
  run_block "$(filled_block step9 "$task" "" 0)" "$shell"
  assert "$shell step 9 refused: exit non-zero and no promoted snapshot" '[ "$rc" -ne 0 ] && [ ! -e "$task/contract.before.yaml" ]'
  printf 'sections:\n  abilities:\n    sources: [cmd/**]\n    items:\n      - text: A merged write-back.\n        refs: [cmd/main.go:1]\n' >"$world_dir/writeback.yaml"
  bash "$repo_root/scripts/contract-edit.sh" apply "$CONTRACT" "$world_dir/writeback.yaml" >/dev/null
  cp "$CONTRACT" "$world_dir/contract.after-writeback"
  write_gate_patch "$task" "GET /health answers 204."
  run_block "$(filled_block step9 "$task" "" 0)" "$shell"
  assert "$shell step 9 accepted: before copy is the contract after the write-back ($out)" '[ "$rc" = 0 ] && cmp -s "$task/contract.before.yaml" "$world_dir/contract.after-writeback" && [ ! -e "$task/contract.before.new.yaml" ]'
  undo_refused="$(fill "$(code_after "$confirmation" 'The undo command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task" '<applied keys, joined by commas>' interfaces " --planned '<removed ids, joined by commas>'" '')"
  run_block "$undo_refused" "$shell"
  assert "$shell step 9 refused-then-accepted undo: the write-back text stays ($out)" '[ "$rc" = 0 ] && grep -qF "A merged write-back." "$CONTRACT" && ! grep -qF "answers 204" "$CONTRACT"'

  echo "$shell: gate step 9 with a plan-only patch"
  setup_world "gate-plan-$shell"; add_plan_items
  task="$VAULT/Tasks/task-a3"
  write_brief "$task" '[]'
  write_gate_patch "$task" "" gate-item
  run_block "$(filled_block step9 "$task" "" 0)" "$shell"
  assert "$shell step 9 plan-only: exit 0, the item is removed, verified_commit moves ($out)" '[ "$rc" = 0 ] && [ "$(plan_ids)" = keep-me ] && [ "$(yq .verified_commit "$CONTRACT")" = 12e4567 ]'
  printf 'sections:\n  abilities:\n    sources: [cmd/**]\n    items:\n      - text: A later edit.\n        refs: [cmd/main.go:1]\n' >"$world_dir/later.yaml"
  bash "$repo_root/scripts/contract-edit.sh" apply "$CONTRACT" "$world_dir/later.yaml" >/dev/null
  undo_plan="$(fill "$(code_after "$confirmation" 'The undo command:')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task" " --sections '<applied keys, joined by commas>'" '' '<removed ids, joined by commas>' gate-item)"
  run_block "$undo_plan" "$shell"
  assert "$shell step 9 plan-only undo: the plan item is back and a later edit stays ($out)" '[ "$rc" = 0 ] && [ "$(plan_ids)" = gate-item,keep-me ] && grep -qF "A later edit." "$CONTRACT"'

  echo "$shell: gate step 9 with no patch file"
  setup_world "gate-none-$shell"
  task="$VAULT/Tasks/task-a4"
  write_brief "$task" '["interfaces"]'
  no_patch_block="$(raw_block step9 | grep -vF 'contract.before' | grep -vF 'contract-edit.sh" apply')"
  run_block "$(fill "$no_patch_block" '<scripts folder>' "$repo_root/scripts" '<task folder>' "$(quote "$task")")" "$shell"
  assert "$shell step 9 no patch: exit 0, still stale, verified_commit stays ($out)" '[ "$rc" = 0 ] && printf "%s\n" "$out" | grep -qxF "interfaces" && printf "%s\n" "$out" | grep -qxF "still stale:" && [ "$(yq .verified_commit "$CONTRACT")" = "$FIRST_COMMIT" ]'

  echo "$shell: MERGED and its undo (I2)"
  setup_world "merge-$shell"
  yq -i '.planned = [{"id": "gate-item", "title": "Gate item", "why": "x"}, {"id": "b-item", "title": "B item", "why": "y"}, {"id": "a-item", "title": "A item", "why": "z"}, {"id": "keep-me", "title": "Keep me", "why": "w"}]' "$CONTRACT"
  set_pending '[{"pr":7,"task":"task-a"},{"pr":8,"task":"task-b"}]'
  task_a="$VAULT/Tasks/task-a"; task_b="$VAULT/Tasks/task-b"; mkdir -p "$task_b"
  write_brief "$task_a" '["interfaces"]'
  write_gate_patch "$task_a" "A gate text." gate-item
  run_block "$(filled_block step9 "$task_a" "" 0)" "$shell"
  assert "$shell task A gate: exit 0 ($out)" '[ "$rc" = 0 ]'
  write_writeback_patch "$task_b" "B edit text." b-item
  run_block "$(filled_block merged "$task_b" "" 8)" "$shell"
  assert "$shell task B MERGED: exit 0 ($out)" '[ "$rc" = 0 ]'
  write_writeback_patch "$task_a" "A write-back text." a-item
  run_block "$(filled_block merged "$task_a" "" 7)" "$shell"
  assert "$shell task A MERGED: exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell task A MERGED: the output names the applied key and the removed plan item" 'printf "%s\n" "$out" | grep -qxF interfaces && [ "$(undo_ids)" = a-item ]'
  assert "$shell task A MERGED: the plan item is removed" '[ "$(plan_ids)" = keep-me ]'
  assert "$shell task A MERGED: the pending item is gone" '[ "$(pending_of)" = "[]" ]'
  assert "$shell task A MERGED: the write-back text is in" '[ "$(yq ".sections.interfaces.items[0].text" "$CONTRACT")" = "A write-back text." ]'
  cp "$task_a/contract.writeback.before.yaml" "$world_dir/writeback.before" || true
  run_block "$(filled_block merged "$task_a" "" 7)" "$shell"
  assert "$shell task A MERGED second run: exit 0, and the snapshot keeps the text from before the write-back ($out)" '[ "$rc" = 0 ] && cmp -s "$task_a/contract.writeback.before.yaml" "$world_dir/writeback.before"'
  assert "$shell task A MERGED second run: the undo line still names the removed plan item" '[ "$(undo_ids)" = a-item ]'
  merged_undo="$(fill "$(code_after "$deliver" 'set the undo of the `contract write-back` target to')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task_a" '<applied keys, joined by commas>' interfaces '<removed ids, joined by commas>' "$(undo_ids)")"
  run_block "$merged_undo" "$shell"
  assert "$shell MERGED undo: exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell MERGED undo I2: the edit of task B stays and the write-back text of task A is gone" '[ "$(yq ".sections.interfaces.items[0].text" "$CONTRACT")" = "B edit text." ] && ! grep -qF "A write-back text." "$CONTRACT"'
  assert "$shell MERGED undo: the plan item is back, and the removals of the gate and of task B stay" '[ "$(plan_ids)" = a-item,keep-me ]'

  echo "$shell: MERGED with a plan-only patch, run twice"
  setup_world "merge-plan-$shell"; add_plan_items
  set_pending '[{"pr":7,"task":"task-a"}]'
  task_a="$VAULT/Tasks/task-a"; write_brief "$task_a" '[]'
  PLAN_ID=gate-item yq -n '.remove_planned = [strenv(PLAN_ID)]' >"$task_a/contract.patch.yaml"
  cp "$CONTRACT" "$world_dir/contract.orig"
  run_block "$(filled_block merged "$task_a" "" 7)" "$shell"
  run_block "$(filled_block merged "$task_a" "" 7)" "$shell"
  assert "$shell plan-only MERGED rerun: exit 0, the item is gone, and the undo line names it ($out)" '[ "$rc" = 0 ] && [ "$(plan_ids)" = keep-me ] && [ "$(undo_ids)" = gate-item ]'
  plan_undo="$(fill "$(code_after "$deliver" 'set the undo of the `contract write-back` target to')" '<scripts>' "$repo_root/scripts" '<contract_file>' "$CONTRACT" \
    '<task folder>' "$task_a" " --sections '<applied keys, joined by commas>'" '' '<removed ids, joined by commas>' "$(undo_ids)")"
  run_block "$plan_undo" "$shell"
  assert "$shell plan-only MERGED undo: the plan item is back ($out)" '[ "$rc" = 0 ] && [ "$(plan_ids)" = gate-item,keep-me ]'

  echo "$shell: CLOSED"
  setup_world "closed-$shell"
  set_pending '[{"pr":9,"task":"task-c"}]'
  cp "$CONTRACT" "$world_dir/contract.orig"
  mkdir -p "$contract_folder/decisions"
  printf -- '---\nid: "0001"\nstatus: accepted\ntask: "[[Tasks/task-c/spec]]"\n---\n\n# 0001 C choice\n' >"$contract_folder/decisions/0001-c-choice.md"
  printf -- '---\nid: "0002"\nstatus: accepted\ntask: "[[Tasks/task-d/spec]]"\n---\n\nSee [[Tasks/task-c/spec]].\n' >"$contract_folder/decisions/0002-d-choice.md"
  run_block "$(filled_block closed "$VAULT/Tasks/task-c" "" 9)" "$shell"
  assert "$shell CLOSED: exit 0, pending empty, body unchanged" '[ "$rc" = 0 ] && [ "$(pending_of)" = "[]" ] && [ "$(yq -o json "del(.pending)" "$CONTRACT")" = "$(yq -o json "del(.pending)" "$world_dir/contract.orig")" ]'
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

done

echo "bash: Contract files runs contract-deliver.sh and records its undo"
files_part="$(awk 'index($0, "### Contract files") == 1 { on = 1 } on && index($0, "## Contract write-back") == 1 { exit } on' "$deliver")"
files_record="$(printf '%s\n' "$files_part" | grep -o '{"target":"write the contract files"[^`]*}' || true)"
assert "Contract files calls contract-deliver.sh write" 'printf "%s\n" "$files_part" | grep -qF "contract-deliver.sh\" write '"'"'<task folder>'"'"' '"'"'<contract_file>'"'"' <task_id>"'
assert "Contract files records contract-deliver.sh undo as the undo" '[ "$(jq -r .undo <<<"$files_record")" = "bash <scripts>/contract-deliver.sh undo '"'"'<task folder>'"'"' '"'"'<contract_file>'"'"' <task_id>" ]'
assert "Contract files copies disagreements.md into report.md" 'printf "%s\n" "$files_part" | grep -qF "disagreements.md" && printf "%s\n" "$files_part" | grep -qF "## Doc and code disagree"'
setup_world "files-run"
task="$VAULT/Tasks/$task_id"; prepare_inputs "$task"
yq '.sections.abilities.items = [{"text": "New text.", "refs": ["cmd/main.go:1"]}]' "$CONTRACT" >"$task/contract.draft.yaml"
cp "$CONTRACT" "$world_dir/contract.orig"
run_block "scripts='$repo_root/scripts'; $(fill "$(code_after "$deliver" '2. Run')" '<task folder>' "$(quote "$task")" '<contract_file>' "$(quote "$CONTRACT")" '<task_id>' "$task_id")" bash
assert "Contract files: the write command exits 0 and saves the file lines ($out)" '[ "$rc" = 0 ] && grep -qxF "replaced: $CONTRACT (old copy: $contract_folder/_archive/$task_id/svc.contract.yaml)" "$task/contract-files.txt" && grep -qxF "new: $contract_folder/decisions/0001-baseline.md" "$task/contract-files.txt"'
run_block "$(fill "$(jq -r .undo <<<"$files_record")" '<scripts>' "$repo_root/scripts" '<task folder>' "$task" '<contract_file>' "$CONTRACT" '<task_id>' "$task_id")" bash
assert "Contract files: the recorded undo restores the contract ($out)" '[ "$rc" = 0 ] && cmp -s "$CONTRACT" "$world_dir/contract.orig" && [ ! -e "$contract_folder/decisions" ]'

retro_skill="$repo_root/skills/run-retro/SKILL.md"
retro_block() {  # <retro folder> <stale JSON> <chosen names, one per line> [yes|no: remove the plan items]
  fill "$(block_after "$retro_skill" 'D6. After the answer')" '<scripts folder>' "$repo_root/scripts" '<retro folder>' "$1" '<retro name>' 2026-W47 \
    '<contract file>' "$(quote "$CONTRACT")" '<checked commit>' c4ec123 '<stale_sections JSON>' "$2" '<chosen section names, one per line>' "$3" \
    '<yes or no>' "${4:-no}"
}
write_retro_patch() {  # <patch file> [--remove-planned <id>] <section key>...: one item per key, with the text "Retro <key> text."
  local patch="$1"; shift
  printf 'sections: {}\n' >"$patch"
  if [ "${1:-}" = --remove-planned ]; then PLAN_ID="$2" yq -i '.remove_planned = [strenv(PLAN_ID)]' "$patch"; shift 2; fi
  for key in "$@"; do
    KEY="$key" yq -i '.sections[strenv(KEY)] = {"sources": ["any/**"], "items": [{"text": "Retro " + strenv(KEY) + " text.", "refs": ["cmd/main.go:1"]}]}' "$patch"
  done
}
for shell in $test_shells; do
  echo "$shell: run-retro contract drift block"
  setup_world "retro-$shell"
  retro_dir="$VAULT/Retros"; mkdir -p "$retro_dir"
  write_retro_patch "$retro_dir/2026-W47.contract-patch.yaml" interfaces abilities
  cp "$CONTRACT" "$world_dir/contract.orig"
  run_block "$(retro_block "$retro_dir" '["abilities","interfaces"]' 'interfaces')" "$shell"
  assert "$shell retro: only some sections chosen, exit 0 ($out)" '[ "$rc" = 0 ]'
  assert "$shell retro: the chosen section is applied, the other is not" '[ "$(yq ".sections.interfaces.items[0].text" "$CONTRACT")" = "Retro interfaces text." ] && ! grep -qF "Retro abilities text." "$CONTRACT"'
  assert "$shell retro: verified_commit does not move" '[ "$(yq .verified_commit "$CONTRACT")" = "$FIRST_COMMIT" ] && printf "%s\n" "$out" | grep -qxF "abilities"'
  assert "$shell retro: the before copy is the original and no lock is left" 'cmp -s "$retro_dir/2026-W47.contract-before.yaml" "$world_dir/contract.orig" && [ ! -e "$CONTRACT.lock" ]'
  run_block "$(retro_block "$retro_dir" '["abilities","interfaces"]' $'abilities\ninterfaces')" "$shell"
  assert "$shell retro: all stale sections chosen, verified_commit moves ($out)" '[ "$rc" = 0 ] && [ "$(yq .verified_commit "$CONTRACT")" = c4ec123 ] && grep -qF "Retro abilities text." "$CONTRACT"'
  assert "$shell retro: the second run keeps the first before copy" 'cmp -s "$retro_dir/2026-W47.contract-before.yaml" "$world_dir/contract.orig"'
  echo "$shell: run-retro all with a stale section that has no patch section"
  setup_world "retro-all-$shell"
  retro_dir="$VAULT/Retros"; mkdir -p "$retro_dir"
  write_retro_patch "$retro_dir/2026-W47.contract-patch.yaml" interfaces
  run_block "$(retro_block "$retro_dir" '["abilities","interfaces"]' 'interfaces')" "$shell"
  assert "$shell retro all: applies the section it has, verified_commit stays, names the section left ($out)" '[ "$rc" = 0 ] && [ "$(yq ".sections.interfaces.items[0].text" "$CONTRACT")" = "Retro interfaces text." ] && [ "$(yq .verified_commit "$CONTRACT")" = "$FIRST_COMMIT" ] && printf "%s\n" "$out" | grep -qxF "abilities"'
  echo "$shell: run-retro patch with remove_planned"
  for plan_answer in no yes; do
    setup_world "retro-plan-$plan_answer-$shell"; add_plan_items
    retro_dir="$VAULT/Retros"; mkdir -p "$retro_dir"
    write_retro_patch "$retro_dir/2026-W47.contract-patch.yaml" --remove-planned gate-item interfaces abilities
    cp "$CONTRACT" "$world_dir/contract.orig"
    run_block "$(retro_block "$retro_dir" '["abilities","interfaces"]' 'abilities' "$plan_answer")" "$shell"
    assert "$shell retro plan items $plan_answer: exit 0, only the chosen section is applied ($out)" '[ "$rc" = 0 ] && grep -qF "Retro abilities text." "$CONTRACT" && ! grep -qF "Retro interfaces text." "$CONTRACT"'
    if [ "$plan_answer" = no ]; then
      assert "$shell retro plan items no: the plan item stays and no undo ids are printed" '[ "$(plan_ids)" = gate-item,keep-me ] && [ -z "$(undo_ids)" ]'
    else
      assert "$shell retro plan items yes: the plan item is removed and named for the undo" '[ "$(plan_ids)" = keep-me ] && [ "$(undo_ids)" = gate-item ]'
      run_block "$(retro_block "$retro_dir" '["abilities","interfaces"]' 'abilities' yes)" "$shell"
      assert "$shell retro plan items yes, rerun: the undo line still names the item ($out)" '[ "$rc" = 0 ] && [ "$(undo_ids)" = gate-item ]'
      run_block "bash '$repo_root/scripts/contract-edit.sh' apply '$CONTRACT' '$retro_dir/2026-W47.contract-before.yaml' --sections abilities --planned '$(undo_ids)'" "$shell"
      assert "$shell retro plan items yes: the D7 undo restores the contract ($out)" '[ "$rc" = 0 ] && same_contract "$CONTRACT" "$world_dir/contract.orig"'
    fi
  done
  setup_world "retro-plan-only-$shell"; add_plan_items
  retro_dir="$VAULT/Retros"; mkdir -p "$retro_dir"
  write_retro_patch "$retro_dir/2026-W47.contract-patch.yaml" --remove-planned gate-item interfaces
  run_block "$(retro_block "$retro_dir" '["interfaces"]' '' yes)" "$shell"
  assert "$shell retro plan items only: exit 0, the item is removed, no section changes, verified_commit stays ($out)" '[ "$rc" = 0 ] && [ "$(plan_ids)" = keep-me ] && ! grep -qF "Retro interfaces text." "$CONTRACT" && [ "$(yq .verified_commit "$CONTRACT")" = "$FIRST_COMMIT" ]'

  setup_world "retro-lock-$shell"
  mkdir "$CONTRACT.lock"
  run_block "$(retro_block "$retro_dir" '[]' 'interfaces')" "$shell"
  assert "$shell retro: a busy lock exits 4" '[ "$rc" = 4 ]'
  rmdir "$CONTRACT.lock"
done

finish
