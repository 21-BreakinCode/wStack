#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
guard="$repo_root/scripts/guard.sh"
export FAKE_LOG="$work_dir/fake.log"
export PATH="$repo_root/tests/fixtures/bin:$PATH"

main_repo="$work_dir/main-repo"; feature_repo="$work_dir/feature-repo"
for repo in "$main_repo" "$feature_repo"; do git init -q -b main "$repo"; done
git -C "$feature_repo" symbolic-ref HEAD refs/heads/wstack/feature

decide_in() {  # <cwd> <tool> <command> -> decision or "pass"
  local payload output
  payload="$(jq -n --arg tool "$2" --arg cmd "$3" --arg cwd "$1" \
    '{tool_name:$tool, tool_input:{command:$cmd}, cwd:$cwd}')"
  output="$(printf '%s' "$payload" | "$BASH" "$guard")"
  if [ -z "$output" ]; then echo pass; else printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}
decide() { decide_in "$feature_repo" Bash "$1"; }

check() {  # <expected> <command>
  expected="$1"; actual="$(decide "$2")"
  assert "$1: $2" '[ "$actual" = "$expected" ]'
}

check ask  'gh pr merge 12 --merge'
check ask  'cd repo && gh pr merge 1'
check ask  "bash -c 'gh pr merge 1'"
check ask  'FOO=1 gh pr merge 1'
check ask  'gh api -X PUT repos/o/r/pulls/12/merge'
check ask  'git push origin main'
check ask  'git push origin HEAD:main'
check ask  'git push -f origin wstack/x'
check ask  'git push --force-with-lease origin wstack/x'
check ask  'git push origin --delete wstack/x'
check pass 'git push -u origin wstack/fix-login'
check pass 'git push'
check pass 'gh pr create --title x --body y'
check ask  'gh pr close 3 --delete-branch'
check ask  'gh repo delete o/r --yes'
check ask  'cf r2 objects bulk-delete --bucket b'
check ask  'cf r2 buckets delete b'
check ask  'npm publish'
check ask  'docker push img:1 && echo done'
check pass 'npm test'
check pass 'WSTACK_APPROVED=1 gh pr merge 12 --merge'

assert "bare git push on main: ask" '[ "$(decide_in "$main_repo" Bash "git push")" = "ask" ]'
assert "git push origin on main: ask" '[ "$(decide_in "$main_repo" Bash "git push origin")" = "ask" ]'
assert "tool Write: pass" '[ "$(decide_in "$feature_repo" Write "gh pr merge 1")" = "pass" ]'

deny_output="$(jq -n --arg cwd "$feature_repo" '{tool_name:"Bash",tool_input:{command:"gh pr merge 1"},cwd:$cwd}' \
  | WSTACK_GUARD_MODE=deny "$BASH" "$guard")"
assert "deny mode decision" '[ "$(printf "%s" "$deny_output" | jq -r .hookSpecificOutput.permissionDecision)" = "deny" ]'
assert "deny reason names WSTACK_APPROVED=1" '[[ "$deny_output" == *"WSTACK_APPROVED=1"* ]]'

no_jq_output="$(echo '{}' | PATH=/nonexistent "$BASH" "$guard")"
assert "missing jq asks" '[[ "$no_jq_output" == *"\"permissionDecision\":\"ask\""* && "$no_jq_output" == *"install jq"* ]]'

assert "fake gh log stayed empty" '[ ! -s "$FAKE_LOG" ]'
finish
