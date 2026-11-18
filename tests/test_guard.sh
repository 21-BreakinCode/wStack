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
check ask  'cf r2 objects delete some/key --bucket-name b'
check ask  'cf r2 objects bulk-delete --bucket-name b --prefix evidence/'
check ask  'cf r2 buckets jobs create b --job-type prefixDelete --prefix evidence/'
check ask  'cf --profile work r2 buckets delete b'
check ask  'cf -q r2 objects delete k --bucket-name b'
check ask  'cf r2 --profile work objects bulk-delete --bucket-name b'
check pass 'cf r2 objects list --bucket-name b --prefix evidence/'
check pass 'cf r2 objects put k --bucket-name b --file f.webp'
check pass 'cf r2 buckets list'
check pass 'cf r2 buckets get b'
check ask  'npm publish'
check ask  'docker push img:1 && echo done'
check pass 'npm test'
check pass 'WSTACK_APPROVED=1 gh pr merge 12 --merge'

check ask  'git push origin refs/heads/main'
check ask  'git push origin +wstack/x:main'
check ask  'git push origin wstack/x && git push --force'
check ask  'git push origin wstack/x; git push origin main'
check ask  'git push origin wstack/x || git push origin main'
check ask  'echo x && git push origin wstack/x; git push origin main'
check ask  $'git push origin wstack/x\ngit push origin main'
check ask  'WSTACK_APPROVED=1 true && gh pr merge 1'
check ask  'true && git push origin main'
check ask  'git -C /x push origin main'
check ask  'git -C /x push --force'
check ask  'git -c user.name=a push origin HEAD:main'
check pass 'WSTACK_APPROVED=1 gh pr merge 1'
check pass 'true && WSTACK_APPROVED=1 gh pr merge 1'
check pass 'git push origin wstack/x && git push origin wstack/y'
check pass 'git -C /x push -u origin wstack/x'
assert "git -C main repo bare push: ask" '[ "$(decide_in "$feature_repo" Bash "git -C $main_repo push")" = "ask" ]'
assert "git -C feature repo bare push from main cwd: pass" '[ "$(decide_in "$main_repo" Bash "git -C $feature_repo push")" = "pass" ]'
assert "bare git push on main: ask" '[ "$(decide_in "$main_repo" Bash "git push")" = "ask" ]'
assert "git push origin on main: ask" '[ "$(decide_in "$main_repo" Bash "git push origin")" = "ask" ]'
check ask  'bash /p/scripts/evidence-delete.sh --task-id 2000-01-02-x --bucket b'
check ask  '/p/scripts/evidence-delete.sh --task-id 2000-01-02-x --bucket b'
check ask  'bash "/Users/me/.claude/plugins/wstack/scripts/evidence-delete.sh" --task-id 2000-01-02-x --bucket b'
check ask  'cd x && bash scripts/evidence-delete.sh --task-id 2000-01-02-x --bucket b'
check pass 'bash /p/scripts/evidence-delete.sh --task-id 2000-01-02-x --bucket b --dry-run'
check pass 'WSTACK_APPROVED=1 bash /p/scripts/evidence-delete.sh --task-id 2000-01-02-x --bucket b'
check pass 'bash /p/scripts/evidence-upload.sh --task-id 2000-01-02-x --dir d'
assert "tool Write: pass" '[ "$(decide_in "$feature_repo" Write "gh pr merge 1")" = "pass" ]'

deny_output="$(jq -n --arg cwd "$feature_repo" '{tool_name:"Bash",tool_input:{command:"gh pr merge 1"},cwd:$cwd}' \
  | WSTACK_GUARD_MODE=deny "$BASH" "$guard")"
assert "deny mode decision" '[ "$(printf "%s" "$deny_output" | jq -r .hookSpecificOutput.permissionDecision)" = "deny" ]'
assert "deny reason names WSTACK_APPROVED=1" '[[ "$deny_output" == *"WSTACK_APPROVED=1"* ]]'

no_jq_output="$(echo '{}' | PATH=/nonexistent "$BASH" "$guard")"
assert "missing jq asks" '[[ "$no_jq_output" == *"\"permissionDecision\":\"ask\""* && "$no_jq_output" == *"install jq"* ]]'

finish
