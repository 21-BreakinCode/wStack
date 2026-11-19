#!/usr/bin/env bash
# Live test, costs money, not run by run-all.sh. Run: bash tests/live/test_deliver.sh
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
set_field="$plugin_root/scripts/frontmatter-set.sh"
mkdir -p "$vault"

# run_fixture <slug> <work type> <cwd> <deliver targets> <non-undoable steps>
# Builds a verified task (status verifying, review result pass), runs the work mode once.
# Sets task_dir and reply_text.
run_fixture() {
  local slug="$1" work_type="$2" cwd="$3" targets="$4" non_undoable="$5"
  local task_id
  task_dir="$(bash "$plugin_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir "$tasks_dir" \
    --slug "$slug" --date 2026-11-18 --work-type "$work_type" --repo local/repo | tail -1)"
  task_id="$(basename "$task_dir")"
  bash "$set_field" "$task_dir/spec.md" workspace_cwd "$cwd"
  bash "$set_field" "$task_dir/spec.md" approved_at 2026-11-18T00:00:00Z
  bash "$set_field" "$task_dir/spec.md" status verifying
  bash "$set_field" "$task_dir/run-log.md" started_at 2026-11-18T00:01:00Z
  bash "$set_field" "$task_dir/review.md" result pass 2>/dev/null || {
    cp "$plugin_root/templates/review.md" "$task_dir/review.md"
    sed -i.bak "s/{{task_id}}/$task_id/" "$task_dir/review.md" && rm -f "$task_dir/review.md.bak"
    bash "$set_field" "$task_dir/review.md" result pass
  }
  awk 'NR==1&&$0=="---"{f=1} {print} f&&NR>1&&$0=="---"{exit}' "$task_dir/spec.md" > "$work_dir/frontmatter"
  {
    cat "$work_dir/frontmatter"
    printf '\n## Goal\nDeliver the finished work.\n\n## Verification plan\nDone and passed.\n\n'
    printf '## Non-undoable steps\n%s\n\n## Deliver targets\n%s\n' "$non_undoable" "$targets"
  } > "$task_dir/spec.md"
  printf -- '- 2026-11-18T00:01:30Z step wrote the work to %s\n' "${work_product:-the branch}" >> "$task_dir/run-log.md"
  printf -- '- 2026-11-18T00:02:00Z step Verify passed, review.md result is pass\n' >> "$task_dir/run-log.md"

  reply_text="$(env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
    PATH="$plugin_root/tests/fixtures/bin:$PATH" WSTACK_VAULT_PATH="$vault" WSTACK_TASKS_DIR="$tasks_dir" \
    FAKE_PR_LIST="${FAKE_PR_LIST:-[]}" \
    bash -c 'cd "$1" && claude -p --plugin-dir "$2" --permission-mode bypassPermissions --model sonnet \
      --max-budget-usd "$4" "/wstack:start-task --task $3" </dev/null' _ "$cwd" "$plugin_root" "$task_id" "${LIVE_BUDGET_USD:-2}" \
    2>&1 || echo "claude exited non-zero" >&2)"
  printf '%s\n' "$reply_text"
}

echo "== Fixture 1: deliver-undoable"
home_cwd="$work_dir/cwd-note"; mkdir -p "$home_cwd"
printf '# Tea\nTea is a drink made from leaves.\n' > "$vault/Tea notes.md"
work_product="$vault/Tea notes.md" run_fixture deliver-undoable thinking "$home_cwd" "- new Obsidian note" "None."
rc=0; [ -f "$vault/Tea notes.md" ] || rc=1; check "the note exists in the vault" "$rc"
status_value="$(sed -n 's/^status: *//p' "$task_dir/spec.md")"
rc=0; [ "$status_value" = delivered ] || rc=1; check "status is delivered (was: $status_value)" "$rc"
last_line="$(printf '%s\n' "$reply_text" | sed '/^[[:space:]]*$/d' | tail -1)"
rc=0; case "$last_line" in *"?"*) rc=1 ;; esac; check "reply does not end on a question (last line: $last_line)" "$rc"
reply_lower="$(printf '%s' "$reply_text" | tr '[:upper:]' '[:lower:]')"
rc=0; case "$reply_lower" in *"approve"*|*"yes or no"*|*"may i"*|*"shall i"*) rc=1 ;; esac
check "reply asks for no approval" "$rc"
targets_json="$(sed -n 's/^targets: *//p' "$task_dir/report.md")"
rc=0; [ "$(printf '%s' "$targets_json" | jq 'length')" = 1 ] || rc=1; check "report.md targets has one item" "$rc"
rc=0; [ -n "$(printf '%s' "$targets_json" | jq -r '.[0].undo // empty')" ] || rc=1; check "the target has a non-empty undo" "$rc"
rc=0; [ -n "$(sed -n 's/^ended_at: *//p' "$task_dir/run-log.md")" ] || rc=1; check "run-log.md has ended_at" "$rc"

echo "== Fixture 2: deliver-merge-waits"
repo="$work_dir/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name tester
printf 'echo hello\n' > "$repo/app.sh"
git -C "$repo" add app.sh
git -C "$repo" commit -q -m "feat: add app"
git -C "$repo" switch -q -c wstack/deliver-merge-waits
printf 'echo hello world\n' > "$repo/app.sh"
git -C "$repo" commit -q -am "feat: change greeting"
git -C "$repo" switch -q main
main_head_before="$(git -C "$repo" rev-parse main)"
: > "$FAKE_LOG"
FAKE_PR_LIST='[{"number":7,"url":"https://github.com/o/r/pull/7"}]' \
  run_fixture deliver-merge-waits code "$repo" $'- open a pull request\n- merge' "- merge"
status_value="$(sed -n 's/^status: *//p' "$task_dir/spec.md")"
rc=0; [ "$status_value" = awaiting-deliver-approval ] || rc=1; check "status is awaiting-deliver-approval (was: $status_value)" "$rc"
rc=0; case "$(cat "$FAKE_LOG")" in *"pr merge"*) rc=1 ;; esac; check "fake gh log has no pr merge" "$rc"
reply_lower="$(printf '%s' "$reply_text" | tr '[:upper:]' '[:lower:]')"
rc=1; case "$reply_lower" in *merge*) case "$reply_lower" in *approv*|*"yes or no"*|*"go ahead"*|*confirm*) rc=0 ;; esac ;; esac
check "reply asks the user to approve the merge" "$rc"
rc=0; [ "$(git -C "$repo" rev-parse main)" = "$main_head_before" ] || rc=1; check "main has no new commit" "$rc"

echo "Failed: $fail_count"
[ "$fail_count" -eq 0 ]
