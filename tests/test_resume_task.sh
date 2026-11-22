#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/resume-task.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home dir"; mkdir -p "$HOME"
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export FAKE_LOG="$work_dir/log" HERDR_ENV=1 WSTACK_HERDR_SESSION=wstack-test FAKE_AGENT_NAME=my-task
has_call() { grep -qxF -- "$(printf '%q ' --session wstack-test "$@")" "$FAKE_LOG"; }
vault="$work_dir/my vault"; mkdir -p "$vault" "$work_dir/cwd dir"
task_dir="$(bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug my-task --date 2026-11-18 | tail -n 1)"
fm_set "$task_dir/spec.md" workspace_cwd "$work_dir/cwd dir"

: >"$FAKE_LOG"
out="$(FAKE_AGENT_EXISTS=1 bash "$script" --task-dir "$task_dir")"
assert "focused" '[ "$out" = focused ]'
assert "focus workspace of agent" 'has_call workspace focus w9'
assert "no restart when live" '! grep -q "agent start" "$FAKE_LOG"'

: >"$FAKE_LOG"
out="$(bash "$script" --task-dir "$task_dir")"
assert "restarted" '[ "$out" = restarted ]'
assert "restart workspace" 'has_call workspace create --cwd "$work_dir/cwd dir" --label my-task --no-focus'
assert "restart with --continue" 'has_call agent start my-task --kind claude --pane w3:p1 -- --remote-control my-task --name my-task --permission-mode bypassPermissions --continue'
assert "restart focus" 'has_call workspace focus w3'

fm_set "$task_dir/spec.md" session_ids '["0f8fad5b-d9cb-469f-a165-70867728950e","1b4e28ba-2fa1-11d2-883f-0016d3cca427"]'
: >"$FAKE_LOG"
bash "$script" --task-dir "$task_dir" >/dev/null
assert "restart with --resume <last id>" 'has_call agent start my-task --kind claude --pane w3:p1 -- --remote-control my-task --name my-task --permission-mode bypassPermissions --resume 1b4e28ba-2fa1-11d2-883f-0016d3cca427'
fm_set "$task_dir/spec.md" session_ids '[]'
: >"$FAKE_LOG"
bash "$script" --task-dir "$task_dir" >/dev/null
assert "empty session_ids restarts with --continue" 'grep -q -- "--continue" "$FAKE_LOG" && ! grep -q -- "--resume" "$FAKE_LOG"'
grep -v '^session_ids:' "$task_dir/spec.md" >"$work_dir/nofield.md" && mv "$work_dir/nofield.md" "$task_dir/spec.md"
: >"$FAKE_LOG"
bash "$script" --task-dir "$task_dir" >/dev/null
assert "no session_ids field restarts with --continue" 'grep -q -- "--continue" "$FAKE_LOG" && ! grep -q -- "--resume" "$FAKE_LOG"'
for bad_value in '["not-a-uuid"]' '{"a":1}' '[oops'; do
  fm_set "$task_dir/spec.md" session_ids "$bad_value"
  : >"$FAKE_LOG"
  bash "$script" --task-dir "$task_dir" >/dev/null 2>"$work_dir/err"
  assert "bad session_ids $bad_value warns and uses --continue" 'grep -q "session_ids is not a list of session ids" "$work_dir/err" && grep -q -- "--continue" "$FAKE_LOG" && ! grep -q -- "--resume" "$FAKE_LOG"'
done

fm_set "$task_dir/spec.md" workspace_cwd "$work_dir/gone"
rc=0; bash "$script" --task-dir "$task_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "missing dir exits 1" '[ "$rc" = 1 ] && grep -q "working directory $work_dir/gone is gone; start a new task" "$work_dir/err"'
fm_set "$task_dir/spec.md" workspace_cwd "$work_dir/cwd dir"
rm -f "$FAKE_LOG.started"
rc=0; FAKE_NOT_READY=other bash "$script" --task-dir "$task_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "exit 5 prints workspace id and close command" '[ "$rc" = 5 ] && grep -q "herdr --session wstack-test workspace close w3" "$work_dir/err"'
rc=0; FAKE_CREATE_FAIL=1 bash "$script" --task-dir "$task_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "create failure exits 6" '[ "$rc" = 6 ] && grep -q "could not create workspace: herdr: boom" "$work_dir/err"'
rc=0; FAKE_AGENT_EXISTS=1 FAKE_FOCUS_FAIL=1 bash "$script" --task-dir "$task_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "live path focus failure exits 5" '[ "$rc" = 5 ] && grep -q "could not focus workspace w9" "$work_dir/err"'
rc=0; FAKE_NOT_READY= FAKE_FOCUS_FAIL=1 bash "$script" --task-dir "$task_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "restart path focus failure exits 5 with cleanup" '[ "$rc" = 5 ] && grep -q "workspace close w3" "$work_dir/err"'
finish
