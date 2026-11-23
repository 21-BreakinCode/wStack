#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/launch-task.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home dir"; mkdir -p "$HOME"
export HERDR_CONFIG_PATH="$work_dir/herdr config.toml"
printf '[worktrees]\ndirectory = "%s/wt"\n' "$work_dir" >"$HERDR_CONFIG_PATH"
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export FAKE_LOG="$work_dir/log" HERDR_ENV=1 WSTACK_HERDR_SESSION=wstack-test FAKE_AGENT_NAME=fix-login-2 WSTACK_TRUST_TIMEOUT=2
vault="$work_dir/my vault"; mkdir -p "$vault"
new_task() {  # <slug> <work_type>
  bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug "$1" --date 2026-11-18 --work-type "$2" | tail -n 1
}
# has_call <herdr args...>: the fake logged exactly this call, one printf %q line, so argument boundaries are checked
has_call() { grep -qxF -- "$(printf '%q ' --session wstack-test "$@")" "$FAKE_LOG"; }

code_dir="$(new_task fix-login code)"
: >"$FAKE_LOG"
out="$(bash "$script" --task-dir "$code_dir" --repo-path "$work_dir/repo dir")"
assert "code: worktree create" 'has_call worktree create --cwd "$work_dir/repo dir" --branch wstack/fix-login --label fix-login --no-focus'
assert "code: agent start" 'has_call agent start fix-login --kind claude --pane w2:p1 -- --remote-control fix-login --name fix-login --permission-mode bypassPermissions'
assert "code: prompt" 'has_call agent prompt fix-login "/wstack:start-task --task 2026-11-18-fix-login"'
assert "code: focus" 'has_call workspace focus w2'
assert "code: workspace_cwd" '[ "$(fm_get "$code_dir/spec.md" workspace_cwd)" = "/fake/work trees/wstack-branch" ]'
assert "code: output json" '[ "$(jq -c . <<<"$out")" = "{\"workspace_id\":\"w2\",\"agent\":\"fix-login\",\"cwd\":\"/fake/work trees/wstack-branch\"}" ]'

think_dir="$(new_task fix-login thinking)"
: >"$FAKE_LOG"
bash "$script" --task-dir "$think_dir" --mobile >/dev/null
task_cwd="$HOME/.wstack/tasks/2026-11-18-fix-login-2"
assert "thinking: task dir made" '[ -d "$task_cwd" ]'
assert "thinking: workspace create" 'has_call workspace create --cwd "$task_cwd" --label fix-login-2 --no-focus'
assert "thinking: mobile prompt" 'has_call agent prompt fix-login-2 "/wstack:start-task --task 2026-11-18-fix-login-2 --mobile"'
assert "thinking: workspace_cwd" '[ "$(fm_get "$think_dir/spec.md" workspace_cwd)" = "$task_cwd" ]'

# C1: a contract task reads only origin/<base_branch>, so it gets a workspace in the repository, not a worktree
contract_dir="$(new_task set-contract contract)"
: >"$FAKE_LOG"
bash "$script" --task-dir "$contract_dir" --repo-path "$work_dir/repo dir" >/dev/null
assert "contract: workspace create in the repository" 'has_call workspace create --cwd "$work_dir/repo dir" --label set-contract --no-focus'
assert "contract: no worktree" '! grep -q "worktree create" "$FAKE_LOG"'
assert "contract: workspace_cwd is the repository" '[ "$(fm_get "$contract_dir/spec.md" workspace_cwd)" = "$work_dir/repo dir" ]'

rc=0; HERDR_ENV=0 bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "outside herdr exits 3" '[ "$rc" = 3 ] && grep -q "not running inside herdr" "$work_dir/err"'

# I9: outside herdr this session does the work, so workspace_cwd is the current folder or the repository
outside_dir="$work_dir/outside dir"; mkdir -p "$outside_dir"
rc=0; (cd "$outside_dir" && HERDR_ENV=0 bash "$script" --task-dir "$think_dir" >/dev/null 2>&1) || rc=$?
assert "outside herdr, thinking: exit 3 sets workspace_cwd to the current folder" '[ "$rc" = 3 ] && [ "$(fm_get "$think_dir/spec.md" workspace_cwd)" = "$outside_dir" ]'
# A3-3: outside herdr a code task gets its own worktree on wstack/<slug>, not the main checkout
real_repo="$work_dir/real repo"
git init -q -b main "$real_repo"
git -C "$real_repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
outside_code_dir="$(new_task outside-code code)"
rc=0; (cd "$outside_dir" && HERDR_ENV=0 bash "$script" --task-dir "$outside_code_dir" --repo-path "$real_repo" >/dev/null 2>&1) || rc=$?
code_worktree="$work_dir/wt/real repo/wstack-outside-code"
assert "outside herdr, code: exit 3 sets workspace_cwd to a worktree under the configured root" '[ "$rc" = 3 ] && [ "$(fm_get "$outside_code_dir/spec.md" workspace_cwd)" = "$code_worktree" ]'
assert "outside herdr, code: the worktree is on wstack/outside-code" '[ "$(git -C "$code_worktree" symbolic-ref --short HEAD)" = wstack/outside-code ]'
assert "outside herdr, code: the main checkout stays on main" '[ "$(git -C "$real_repo" symbolic-ref --short HEAD)" = main ]'
rc=0; (cd "$outside_dir" && HERDR_ENV=0 bash "$script" --task-dir "$outside_code_dir" --repo-path "$real_repo" >/dev/null 2>&1) || rc=$?
assert "outside herdr, code: a second launch reuses the worktree" '[ "$rc" = 3 ] && [ "$(fm_get "$outside_code_dir/spec.md" workspace_cwd)" = "$code_worktree" ]'
bad_code_dir="$(new_task outside-bad code)"
rc=0; (cd "$outside_dir" && HERDR_ENV=0 bash "$script" --task-dir "$bad_code_dir" --repo-path "$work_dir/repo dir" >/dev/null 2>"$work_dir/err") || rc=$?
assert "outside herdr, code: not a git repository exits 6 and cancels" '[ "$rc" = 6 ] && grep -q "could not create worktree" "$work_dir/err" && [ "$(fm_get "$bad_code_dir/spec.md" status)" = cancelled ]'
git -C "$real_repo" branch wstack/left-over
left_over_dir="$(new_task left-over code)"
rc=0; (cd "$outside_dir" && HERDR_ENV=0 bash "$script" --task-dir "$left_over_dir" --repo-path "$real_repo" >/dev/null 2>"$work_dir/err") || rc=$?
assert "outside herdr, code: a leftover wstack branch exits 6 and names the branch" '[ "$rc" = 6 ] && grep -q "wstack/left-over" "$work_dir/err" && [ ! -e "$work_dir/wt/real repo/wstack-left-over" ]'
# one config per case: missing key, relative value, single quotes with a trailing comment
launch_outside_with_config() {  # <slug> <config content>; prints workspace_cwd
  local task_folder; task_folder="$(new_task "$1" code)"
  printf '%s\n' "$2" >"$work_dir/case.toml"
  (cd "$outside_dir" && HERDR_ENV=0 HERDR_CONFIG_PATH="$work_dir/case.toml" bash "$script" --task-dir "$task_folder" --repo-path "$real_repo" >/dev/null 2>&1) || true
  fm_get "$task_folder/spec.md" workspace_cwd
}
cwd_no_key="$(launch_outside_with_config no-key '[other]
directory = "/elsewhere"')"
cwd_relative="$(launch_outside_with_config rel-root '[worktrees]
directory = "rel/wt"')"
cwd_quoted="$(launch_outside_with_config quoted-root "[worktrees]
directory = '$work_dir/wt2' # note")"
assert "configured root holds the worktree" '[ "$(fm_get "$outside_code_dir/spec.md" workspace_cwd)" = "$work_dir/wt/real repo/wstack-outside-code" ] && [ -e "$work_dir/wt/real repo/wstack-outside-code/.git" ]'
assert "missing key falls back to ~/.herdr/worktrees" '[[ "$cwd_no_key" == "$HOME/.herdr/worktrees/"* ]]'
assert "relative value falls back" '[[ "$cwd_relative" == "$HOME/.herdr/worktrees/"* ]]'
assert "single quotes and a trailing comment resolve" '[[ "$cwd_quoted" == "$work_dir/wt2/"* ]]'
outside_contract_dir="$(new_task outside-contract contract)"
rc=0; (cd "$outside_dir" && HERDR_ENV=0 bash "$script" --task-dir "$outside_contract_dir" --repo-path "$work_dir/repo dir" >/dev/null 2>&1) || rc=$?
assert "outside herdr, contract: exit 3 sets workspace_cwd to the repository" '[ "$rc" = 3 ] && [ "$(fm_get "$outside_contract_dir/spec.md" workspace_cwd)" = "$work_dir/repo dir" ]'

rc=0; FAKE_AGENT_EXISTS=1 bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "name taken exits 4" '[ "$rc" = 4 ] && grep -q "agent name taken" "$work_dir/err"'
assert "name taken sets status cancelled" '[ "$(fm_get "$think_dir/spec.md" status)" = cancelled ]'

: >"$FAKE_LOG"; rm -f "$FAKE_LOG.started"
FAKE_NOT_READY=trust bash "$script" --task-dir "$think_dir" >/dev/null
assert "trust: reads pane" 'grep -q "agent read fix-login-2 --source recent-unwrapped --lines 40" "$FAKE_LOG"'
assert "trust: accepted" 'has_call pane send-keys w3:p1 Down Enter'

: >"$FAKE_LOG"; rm -f "$FAKE_LOG.started"
rc=0; FAKE_NOT_READY=other bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "other not-ready exits 5 with pane text" '[ "$rc" = 5 ] && grep -q "something else is blocking" "$work_dir/err" && ! grep -q send-keys "$FAKE_LOG"'

rm -f "$FAKE_LOG.started"
rc=0; FAKE_NOT_READY=trust FAKE_NEVER_READY=1 bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "trust timeout exits 5" '[ "$rc" = 5 ] && grep -q "not ready" "$work_dir/err"'
rm -f "$FAKE_LOG.started"
rc=0; FAKE_NOT_READY=other bash "$script" --task-dir "$think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "exit 5 prints workspace id and close command" 'grep -q "workspace w3 is still open" "$work_dir/err" && grep -q "herdr --session wstack-test workspace close w3" "$work_dir/err"'

rm -f "$FAKE_LOG.started"
rc=0; FAKE_NOT_READY=other bash "$script" --task-dir "$code_dir" --repo-path "$work_dir/repo dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "code exit 5 prints worktree remove and branch delete" 'grep -q "worktree remove --workspace w2" "$work_dir/err" && grep -q "branch -D wstack/fix-login" "$work_dir/err"'
assert "exit 5 hint quotes the repository path" 'grep -qF "git -C \"$work_dir/repo dir\" branch -D" "$work_dir/err"'
assert "exit 5 closes nothing" '! grep -qE "workspace close|worktree remove" "$FAKE_LOG"'

failing_code_dir="$(new_task fail-code code)"
rc=0; FAKE_CREATE_FAIL=1 bash "$script" --task-dir "$failing_code_dir" --repo-path "$work_dir/repo dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "worktree create failure exits 6" '[ "$rc" = 6 ] && grep -q "could not create workspace: herdr: boom" "$work_dir/err"'
assert "worktree create failure sets status cancelled" '[ "$(fm_get "$failing_code_dir/spec.md" status)" = cancelled ]'
failing_think_dir="$(new_task fail-think thinking)"
rc=0; FAKE_CREATE_FAIL=1 bash "$script" --task-dir "$failing_think_dir" >/dev/null 2>"$work_dir/err" || rc=$?
assert "workspace create failure exits 6" '[ "$rc" = 6 ] && grep -q "could not create workspace: herdr: boom" "$work_dir/err"'
finish
