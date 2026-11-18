#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/resume-task.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"; mkdir -p "$HOME"
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export FAKE_LOG="$work_dir/log" HERDR_ENV=1 WSTACK_HERDR_SESSION=wstack-test FAKE_AGENT_NAME=my-task
vault="$work_dir/vault"; mkdir -p "$vault" "$work_dir/cwd"
task_dir="$(bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug my-task --date 2026-11-18 | tail -n 1)"
fm_set "$task_dir/spec.md" workspace_cwd "$work_dir/cwd"

: >"$FAKE_LOG"
out="$(FAKE_AGENT_EXISTS=1 bash "$script" --task-dir "$task_dir")"
assert "focused" '[ "$out" = focused ]'
assert "focus workspace of agent" 'grep -qxF -- "--session wstack-test workspace focus w9" "$FAKE_LOG"'
assert "no restart when live" '! grep -q "agent start" "$FAKE_LOG"'

: >"$FAKE_LOG"
out="$(bash "$script" --task-dir "$task_dir")"
assert "restarted" '[ "$out" = restarted ]'
assert "restart workspace" 'grep -qxF -- "--session wstack-test workspace create --cwd $work_dir/cwd --label my-task --no-focus" "$FAKE_LOG"'
assert "restart with --continue" 'grep -qxF -- "--session wstack-test agent start my-task --kind claude --pane w3:p1 -- --remote-control my-task --name my-task --permission-mode bypassPermissions --continue" "$FAKE_LOG"'
assert "restart focus" 'grep -qxF -- "--session wstack-test workspace focus w3" "$FAKE_LOG"'

fm_set "$task_dir/spec.md" workspace_cwd "$work_dir/gone"
rc=0; bash "$script" --task-dir "$task_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "missing dir exits 1" '[ "$rc" = 1 ] && grep -q "working directory $work_dir/gone is gone; start a new task" "$work_dir/err"'
finish
