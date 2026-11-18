#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/launch-task.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"; mkdir -p "$HOME"
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export FAKE_LOG="$work_dir/log" HERDR_ENV=1 WSTACK_HERDR_SESSION=wstack-test FAKE_AGENT_NAME=fix-login-2 WSTACK_TRUST_TIMEOUT=2
vault="$work_dir/vault"; mkdir -p "$vault"
new_task() {  # <slug> <work_type>
  bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug "$1" --date 2026-11-18 --work-type "$2" | tail -n 1
}
flags="--remote-control fix-login --name fix-login --permission-mode bypassPermissions"

code_dir="$(new_task fix-login code)"
: >"$FAKE_LOG"
out="$(bash "$script" --task-dir "$code_dir" --repo-path "$work_dir/repo")"
assert "code: worktree create" 'grep -qxF -- "--session wstack-test worktree create --cwd $work_dir/repo --branch wstack/fix-login --label fix-login --no-focus" "$FAKE_LOG"'
assert "code: agent start" 'grep -qxF -- "--session wstack-test agent start fix-login --kind claude --pane w2:p1 -- $flags" "$FAKE_LOG"'
assert "code: prompt" 'grep -qxF -- "--session wstack-test agent prompt fix-login /wstack:start-task --task 2026-11-18-fix-login" "$FAKE_LOG"'
assert "code: focus" 'grep -qxF -- "--session wstack-test workspace focus w2" "$FAKE_LOG"'
assert "code: workspace_cwd" '[ "$(fm_get "$code_dir/spec.md" workspace_cwd)" = "/fake/worktrees/wstack-branch" ]'
assert "code: output json" '[ "$(jq -c . <<<"$out")" = "{\"workspace_id\":\"w2\",\"agent\":\"fix-login\",\"cwd\":\"/fake/worktrees/wstack-branch\"}" ]'

think_dir="$(new_task fix-login thinking)"
: >"$FAKE_LOG"
bash "$script" --task-dir "$think_dir" --mobile >/dev/null
task_cwd="$HOME/.wstack/tasks/2026-11-18-fix-login-2"
assert "thinking: task dir made" '[ -d "$task_cwd" ]'
assert "thinking: workspace create" 'grep -qxF -- "--session wstack-test workspace create --cwd $task_cwd --label fix-login-2 --no-focus" "$FAKE_LOG"'
assert "thinking: mobile prompt" 'grep -qxF -- "--session wstack-test agent prompt fix-login-2 /wstack:start-task --task 2026-11-18-fix-login-2 --mobile" "$FAKE_LOG"'
assert "thinking: workspace_cwd" '[ "$(fm_get "$think_dir/spec.md" workspace_cwd)" = "$task_cwd" ]'

rc=0; HERDR_ENV=0 bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "outside herdr exits 3" '[ "$rc" = 3 ] && grep -q "not running inside herdr" "$work_dir/err"'

rc=0; FAKE_AGENT_EXISTS=1 bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "name taken exits 4" '[ "$rc" = 4 ] && grep -q "agent name taken" "$work_dir/err"'

: >"$FAKE_LOG"; rm -f "$FAKE_LOG.started"
FAKE_NOT_READY=trust bash "$script" --task-dir "$think_dir" >/dev/null
assert "trust: reads pane" 'grep -q "agent read fix-login-2 --source recent-unwrapped --lines 40" "$FAKE_LOG"'
assert "trust: accepted" 'grep -qxF -- "--session wstack-test pane send-keys w3:p1 Down Enter" "$FAKE_LOG"'

: >"$FAKE_LOG"; rm -f "$FAKE_LOG.started"
rc=0; FAKE_NOT_READY=other bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "other not-ready exits 5 with pane text" '[ "$rc" = 5 ] && grep -q "something else is blocking" "$work_dir/err" && ! grep -q send-keys "$FAKE_LOG"'

rm -f "$FAKE_LOG.started"
rc=0; FAKE_NOT_READY=trust FAKE_NEVER_READY=1 bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "trust timeout exits 5" '[ "$rc" = 5 ] && grep -q "not ready" "$work_dir/err"'
finish
