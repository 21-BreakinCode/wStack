#!/usr/bin/env bash
# Live test, costs money, not run by run-all.sh. Run: bash tests/live/test_verify_failure_path.sh
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wstack-live.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
fail_count=0
check() { # check <description> <exit-status-of-condition>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail_count=$((fail_count + 1)); fi
}

vault="$work_dir/vault"; tasks_dir="Tasks"
export FAKE_LOG="$work_dir/gh.log"
mkdir -p "$vault"
: > "$FAKE_LOG"

# run_fixture <slug> <goal> <verification plan> <retry limit> <retries before the run>
# Sets task_dir and reply_text. Runs the work mode once on a task at status verifying.
run_fixture() {
  local slug="$1" goal="$2" plan="$3" retry_limit="$4" start_retries="$5"
  task_dir="$(bash "$plugin_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir "$tasks_dir" \
    --slug "$slug" --date 2026-11-18 --work-type thinking | tail -1)"
  local task_id; task_id="$(basename "$task_dir")"
  local set_field="$plugin_root/scripts/frontmatter-set.sh"
  bash "$set_field" "$task_dir/spec.md" workspace_cwd "$work_dir"
  bash "$set_field" "$task_dir/spec.md" approved_at 2026-11-18T00:00:00Z
  bash "$set_field" "$task_dir/spec.md" status verifying
  bash "$set_field" "$task_dir/run-log.md" started_at 2026-11-18T00:01:00Z
  bash "$set_field" "$task_dir/run-log.md" retries "$start_retries"
  awk 'NR==1&&$0=="---"{f=1} {print} f&&NR>1&&$0=="---"{exit}' "$task_dir/spec.md" > "$work_dir/frontmatter"
  {
    cat "$work_dir/frontmatter"
    printf '\n## Goal\n%s\n\n## Scope\nIn: one new note in the vault. Out: anything else.\n\n' "$goal"
    printf '## Verification plan\n%s\n\n## Non-undoable steps\nNone.\n\n## Deliver targets\n- new Obsidian note\n' "$plan"
  } > "$task_dir/spec.md"
  printf -- '- 2026-11-18T00:01:00Z step wrote the note, work is done, status set to verifying\n' >> "$task_dir/run-log.md"

  reply_text="$(env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
    PATH="$plugin_root/tests/fixtures/bin:$PATH" WSTACK_VAULT_PATH="$vault" WSTACK_TASKS_DIR="$tasks_dir" \
    WSTACK_RETRY_LIMIT="$retry_limit" \
    bash -c 'cd "$1" && claude -p --plugin-dir "$2" --permission-mode bypassPermissions --model sonnet \
      --max-budget-usd "$4" "/wstack:start-task --task $3" </dev/null' _ "$work_dir" "$plugin_root" "$task_id" "${LIVE_BUDGET_USD:-2}" \
    2>&1 || echo "claude exited non-zero" >&2)"
  printf '%s\n' "$reply_text"
}

echo "== Fixture 1: a check that can never pass, retry limit 2"
run_fixture never-passes "Write one short note about tea in the vault. The task is done only when the file /nonexistent exists." \
  "Check: the file /nonexistent exists. Pass rule: test -f /nonexistent exits 0. Evidence: the exit code." 2 0
retries_value="$(sed -n 's/^retries: *//p' "$task_dir/run-log.md")"
status_value="$(sed -n 's/^status: *//p' "$task_dir/spec.md")"
stops_json="$(sed -n 's/^stopped_for_user: *//p' "$task_dir/run-log.md")"
rc=0; [ "$retries_value" = 2 ] || rc=1; check "retries is 2 (was: $retries_value)" "$rc"
rc=0; [ "$status_value" = waiting-user ] || rc=1; check "status is waiting-user (was: $status_value)" "$rc"
rc=0; [ "$(printf '%s' "$stops_json" | jq 'length')" = 1 ] || rc=1; check "stopped_for_user has one item" "$rc"
rc=0; [ "$(printf '%s' "$stops_json" | jq -r '.[0].reason | contains("retry_limit")')" = true ] || rc=1
check "stop reason contains retry_limit" "$rc"
rc=0; [ "$(printf '%s' "$stops_json" | jq -r '.[0].stage')" = verify ] || rc=1; check "stop item stage is verify" "$rc"

echo "== Fixture 2: the verification plan contradicts the goal"
run_fixture spec-wrong "Write a note of about 300 words about tea in the vault." \
  "Check: the note has fewer than 50 words. Pass rule: wc -w of the note is below 50. Evidence: the word count." 3 1
status_value="$(sed -n 's/^status: *//p' "$task_dir/spec.md")"
rc=0; [ "$status_value" = drafting ] || rc=1; check "status is drafting (was: $status_value)" "$rc"
retries_value="$(sed -n 's/^retries: *//p' "$task_dir/run-log.md")"
rc=0; [ "$retries_value" = 0 ] || rc=1; check "retries was reset to 0 (was: $retries_value)" "$rc"
reply_lower="$(printf '%s' "$reply_text" | tr '[:upper:]' '[:lower:]')"
rc=1
case "$reply_lower" in *contradict*|*conflict*|*inconsisten*) rc=0 ;; esac
check "reply names the contradiction" "$rc"
last_line="$(printf '%s\n' "$reply_text" | sed '/^[[:space:]]*$/d' | tail -1)"
rc=1
case "$last_line" in *"?"*) rc=0 ;; esac
check "reply ends on a question (last line: $last_line)" "$rc"

echo "Failed: $fail_count"
[ "$fail_count" -eq 0 ]
