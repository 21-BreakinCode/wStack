#!/usr/bin/env bash
# Live test, costs money, not run by run-all.sh. Run: bash tests/live/test_reviewer_planted_bug.sh
# Dispatches the wstack:reviewer agent (the way verify.md does) on a bug fixture and a clean fixture,
# 3 runs each, each on a fresh copy. Env: LIVE_BUDGET_USD caps one run (default 1), LIVE_RUNS sets runs (default 3).
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wstack-live.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
fail_count=0
check() { # check <description> <exit-status-of-condition>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail_count=$((fail_count + 1)); fi
}

# run_reviewer <fixture name> <run number>. Sets task_dir.
run_reviewer() {
  local fixture="$1" run_number="$2" reply_text
  task_dir="$work_dir/$fixture-$run_number/2026-11-18-add-is-adult"
  mkdir -p "$task_dir"
  cp "$plugin_root/tests/fixtures/$fixture/"* "$task_dir/"
  reply_text="$(env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
    PATH="$plugin_root/tests/fixtures/bin:$PATH" WSTACK_VAULT_PATH="$work_dir" WSTACK_TASKS_DIR=Tasks \
    FAKE_LOG="$work_dir/gh.log" \
    bash -c 'cd "$1" && claude -p --plugin-dir "$2" --permission-mode bypassPermissions --model sonnet \
      --max-budget-usd "$4" "Dispatch the wstack:reviewer agent. Give it the task folder $3 and the change in $3/change.diff. Then reply with what it returned." </dev/null' \
      _ "$work_dir" "$plugin_root" "$task_dir" "${LIVE_BUDGET_USD:-1}" 2>&1 || echo "claude exited non-zero" >&2)"
  printf 'reply: %s\n' "$reply_text"
}

# Prints "yes" when a correctness blocking:yes block has a Where line naming age.sh:3, the line with "> 18" in the fixture.
has_planted_finding() {
  awk '
    /^### [^ ]+ correctness blocking:yes$/ { in_block = 1; next }
    /^### / { in_block = 0 }
    in_block && /^- Where:/ && $0 ~ /age\.sh:3([^0-9]|$)/ { found = 1 }
    END { print found ? "yes" : "no" }
  ' "$1/review.md"
}

runs="${LIVE_RUNS:-3}"
run_number=1
while [ "$run_number" -le "$runs" ]; do
  echo "== Bug fixture, run $run_number"
  run_reviewer planted-bug "$run_number"
  blocking_count="$(sed -n 's/^blocking_findings: *//p' "$task_dir/review.md")"
  rc=1; [ "$(has_planted_finding "$task_dir")" = yes ] && rc=0
  check "run $run_number: a correctness blocking:yes block names age.sh:3, the line with > 18" "$rc"
  rc=1; case "$blocking_count" in ''|*[!0-9]*) ;; *) [ "$blocking_count" -ge 1 ] && rc=0 ;; esac
  check "run $run_number: blocking_findings is 1 or more (was: $blocking_count)" "$rc"

  echo "== Clean fixture, run $run_number"
  run_reviewer planted-bug-clean "$run_number"
  blocking_count="$(sed -n 's/^blocking_findings: *//p' "$task_dir/review.md")"
  rc=1; [ "$blocking_count" = 0 ] && rc=0
  check "run $run_number: blocking_findings is 0 (was: $blocking_count)" "$rc"
  run_number=$((run_number + 1))
done

echo "Failed: $fail_count"
[ "$fail_count" -eq 0 ]
