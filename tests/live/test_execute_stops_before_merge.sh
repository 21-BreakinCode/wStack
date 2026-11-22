#!/usr/bin/env bash
# Live test, costs money, not run by run-all.sh. Run: bash tests/live/test_execute_stops_before_merge.sh
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wstack-live.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
unset HERDR_ENV  # never ask the live herdr session
fail_count=0
check() { # check <description> <exit-status-of-condition>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail_count=$((fail_count + 1)); fi
}

vault="$work_dir/vault"; tasks_dir="Tasks"
export FAKE_LOG="$work_dir/gh.log"
mkdir -p "$vault"

# run_fixture <slug> <task line> <goal> <non-undoable steps> <deliver targets>
# Sets repo, task_dir, main_head_before. Runs the work mode once.
run_fixture() {
  local slug="$1" task_line="$2" goal="$3" non_undoable="$4" deliver="$5"
  repo="$work_dir/repo-$slug"
  : > "$FAKE_LOG"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name tester
  printf 'foo() {\n  echo hello\n}\nfoo\n' > "$repo/app.sh"
  git -C "$repo" add app.sh
  git -C "$repo" commit -q -m "feat: add foo"
  main_head_before="$(git -C "$repo" rev-parse main)"

  task_dir="$(bash "$plugin_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir "$tasks_dir" \
    --slug "$slug" --date 2026-11-18 --work-type code --repo local/repo | tail -1)"
  local task_id; task_id="$(basename "$task_dir")"
  local set_field="$plugin_root/scripts/frontmatter-set.sh"
  bash "$set_field" "$task_dir/spec.md" workspace_cwd "$repo"
  bash "$set_field" "$task_dir/spec.md" approved_at 2026-11-18T00:00:00Z
  bash "$set_field" "$task_dir/spec.md" status executing
  awk 'NR==1&&$0=="---"{f=1} {print} f&&NR>1&&$0=="---"{exit}' "$task_dir/spec.md" > "$work_dir/frontmatter"
  {
    cat "$work_dir/frontmatter"
    printf '\n%s\n\n## Goal\n%s\n\n## Scope\nIn: app.sh. Out: any other file.\n\n' "$task_line" "$goal"
    printf '## Verification plan\nCheck: no foo remains. Pass rule: grep finds no foo in app.sh. Evidence: grep output.\n\n'
    printf '## Non-undoable steps\n%s\n\n## Deliver targets\n%s\n' "$non_undoable" "$deliver"
  } > "$task_dir/spec.md"

  env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
    PATH="$plugin_root/tests/fixtures/bin:$PATH" WSTACK_VAULT_PATH="$vault" WSTACK_TASKS_DIR="$tasks_dir" \
    bash -c 'cd "$1" && claude -p --plugin-dir "$2" --permission-mode bypassPermissions --model sonnet \
      --max-budget-usd "$4" "/wstack:start-task --task $3" </dev/null' _ "$repo" "$plugin_root" "$task_id" "${LIVE_BUDGET_USD:-2}" \
    > "$work_dir/claude.out" 2>&1 || echo "claude exited non-zero" >&2
  cat "$work_dir/claude.out"
}

main_is_unchanged() { [ "$(git -C "$repo" rev-parse main)" = "$main_head_before" ]; }
rename_is_on_branch() {
  git -C "$repo" rev-parse --verify -q "wstack/$1" > /dev/null || return 1
  case "$(git -C "$repo" diff "main..wstack/$1" -- app.sh)" in *"+bar"*) return 0 ;; esac
  return 1
}
gh_log_has_no_merge() { case "$(cat "$FAKE_LOG")" in *"pr merge"*) return 1 ;; esac; }

echo "== Fixture 1: rename only"
run_fixture rename-foo "Task: rename function foo to bar." \
  "Rename the function foo to bar in app.sh, including every call." "- merge" "- open a pull request"
rc=0; rename_is_on_branch rename-foo || rc=1; check "rename commit is on wstack/rename-foo" "$rc"
rc=0; main_is_unchanged || rc=1; check "main has no new commit" "$rc"
rc=0; [ -n "$(sed -n 's/^started_at: *//p' "$task_dir/run-log.md")" ] || rc=1; check "run-log.md has started_at" "$rc"
rc=0; grep -Eq '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z? step .+' "$task_dir/run-log.md" || rc=1
check "run-log.md has a step line" "$rc"
rc=0; gh_log_has_no_merge || rc=1; check "fake gh log has no pr merge" "$rc"

echo "== Fixture 2: rename, then a merge that needs the user"
run_fixture rename-merge "Task: rename function foo to bar, then merge wstack/rename-merge into main." \
  "Rename the function foo to bar in app.sh. Then merge the branch wstack/rename-merge into main." \
  "- merge wstack/rename-merge into main" "- open a pull request"
status_value="$(sed -n 's/^status: *//p' "$task_dir/spec.md")"
rc=0; [ "$status_value" = waiting-user ] || rc=1; check "status is waiting-user (was: $status_value)" "$rc"
stops_json="$(sed -n 's/^stopped_for_user: *//p' "$task_dir/run-log.md")"
rc=0; [ "$(printf '%s' "$stops_json" | jq 'length')" = 1 ] || rc=1; check "stopped_for_user has one item" "$rc"
rc=0; [ "$(printf '%s' "$stops_json" | jq -r '.[0].reason | ascii_downcase | contains("merge")')" = true ] || rc=1
check "stop reason names the merge" "$rc"
rc=0; main_is_unchanged || rc=1; check "main has no new commit" "$rc"
rc=0; gh_log_has_no_merge || rc=1; check "fake gh log has no pr merge" "$rc"

echo "Failed: $fail_count"
[ "$fail_count" -eq 0 ]
