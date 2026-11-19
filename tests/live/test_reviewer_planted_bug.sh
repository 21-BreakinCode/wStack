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

# run_reviewer <fixture name> <run number>. Sets task_dir and stream_file.
run_reviewer() {
  local fixture="$1" run_number="$2"
  task_dir="$work_dir/$fixture-$run_number/2026-11-18-add-is-adult"
  stream_file="$work_dir/$fixture-$run_number.jsonl"
  mkdir -p "$task_dir"
  cp "$plugin_root/tests/fixtures/$fixture/"* "$task_dir/"
  env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
    PATH="$plugin_root/tests/fixtures/bin:$PATH" WSTACK_VAULT_PATH="$work_dir" WSTACK_TASKS_DIR=Tasks \
    FAKE_LOG="$work_dir/gh.log" \
    bash -c 'cd "$1" && claude -p --plugin-dir "$2" --permission-mode bypassPermissions --model sonnet \
      --max-budget-usd "$4" --output-format stream-json --verbose \
      "Dispatch the wstack:reviewer agent. Give it the task folder $3 and the change in $3/change.diff. Then reply with what it returned." </dev/null' \
    _ "$work_dir" "$plugin_root" "$task_dir" "${LIVE_BUDGET_USD:-1}" >"$stream_file" 2>"$stream_file.err" \
    || echo "claude exited non-zero" >&2
}

# check_dispatch: asserts on $stream_file that the reviewer subagent ran and found the script by absolute path.
check_dispatch() {
  local label="$1" dispatch_count script_call_count
  dispatch_count="$(jq -s '[.[] | select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and (.name == "Agent" or .name == "Task") and .input.subagent_type == "wstack:reviewer")] | length' "$stream_file")"
  check "$label: an Agent call names wstack:reviewer" "$([ "$dispatch_count" -ge 1 ] && echo 0 || echo 1)"
  script_call_count="$(jq -s '[.[] | select(.type == "assistant" and .parent_tool_use_id != null) | .message.content[]?
    | select(.type == "tool_use" and .name == "Bash")
    | select((.input.command | contains("/scripts/frontmatter-set.sh")) and (.input.command | contains("${CLAUDE_PLUGIN_ROOT}") | not))] | length' "$stream_file")"
  check "$label: the subagent ran frontmatter-set.sh by absolute path, no literal CLAUDE_PLUGIN_ROOT" "$([ "$script_call_count" -ge 1 ] && echo 0 || echo 1)"
}

# Show the run's review.md when a check failed, before the trap deletes it.
dump_if_failed() {
  [ "$fail_count" -eq "$fails_before" ] && return 0
  echo "--- review.md of the failed run ($task_dir)"; cat "$task_dir/review.md"; echo "--- end"
}

# Prints "yes" when a correctness blocking:yes block has a Where line naming age.sh:4, the line with "> 18" in the fixture.
has_planted_finding() {
  awk '
    /^### [^ ]+ correctness blocking:yes$/ { in_block = 1; next }
    /^### / { in_block = 0 }
    in_block && /^- Where:/ && $0 ~ /age\.sh:4([^0-9]|$)/ { found = 1 }
    END { print found ? "yes" : "no" }
  ' "$1/review.md"
}

runs="${LIVE_RUNS:-3}"
run_number=1
while [ "$run_number" -le "$runs" ]; do
  echo "== Bug fixture, run $run_number"
  fails_before="$fail_count"
  run_reviewer planted-bug "$run_number"
  check_dispatch "run $run_number bug"
  blocking_count="$(sed -n 's/^blocking_findings: *//p' "$task_dir/review.md")"
  rc=1; [ "$(has_planted_finding "$task_dir")" = yes ] && rc=0
  check "run $run_number: a correctness blocking:yes block names age.sh:4, the line with > 18" "$rc"
  rc=1; case "$blocking_count" in ''|*[!0-9]*) ;; *) [ "$blocking_count" -ge 1 ] && rc=0 ;; esac
  check "run $run_number: blocking_findings is 1 or more (was: $blocking_count)" "$rc"
  dump_if_failed

  echo "== Clean fixture, run $run_number"
  fails_before="$fail_count"
  run_reviewer planted-bug-clean "$run_number"
  check_dispatch "run $run_number clean"
  blocking_count="$(sed -n 's/^blocking_findings: *//p' "$task_dir/review.md")"
  rc=1; [ "$blocking_count" = 0 ] && rc=0
  check "run $run_number: blocking_findings is 0 (was: $blocking_count)" "$rc"
  findings_text="$(awk '/^## Findings/{f=1;next} /^## /{f=0} f' "$task_dir/review.md")"
  rc=1; case "$findings_text" in *"No findings."*) rc=0 ;; esac
  check "run $run_number: ## Findings holds No findings." "$rc"
  dump_if_failed
  run_number=$((run_number + 1))
done

echo "Failed: $fail_count"
[ "$fail_count" -eq 0 ]
