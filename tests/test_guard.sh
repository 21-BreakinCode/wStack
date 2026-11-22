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
check ask  'pnpm publish'
check ask  'yarn publish'
check ask  'cargo publish'
check ask  'git checkout main && git merge wstack/feature && git push'
check ask  '(git push origin main)'
check ask  'git push origin --all'
check ask  'docker push img:1 && echo done'
check pass 'npm test'

check ask  'git push origin refs/heads/main'
check ask  'git push origin +wstack/x:main'
check ask  'git push origin wstack/x && git push --force'
check ask  'git push origin wstack/x; git push origin main'
check ask  'git push origin wstack/x || git push origin main'
check ask  'echo x && git push origin wstack/x; git push origin main'
check ask  $'git push origin wstack/x\ngit push origin main'
check ask  'true && git push origin main'
check ask  'git -C /x push origin main'
check ask  'git -C /x push --force'
check ask  'git -c user.name=a push origin HEAD:main'
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
check pass 'bash /p/scripts/evidence-upload.sh --task-id 2000-01-02-x --dir d'
# named, not run: a command that only names a guarded command passes
check pass 'cat -n scripts/evidence-delete.sh'
check pass 'for f in scripts/evidence-delete.sh scripts/evidence-upload.sh; do cat -n "$f"; done'
check ask  'bash scripts/evidence-delete.sh x'
check ask  './scripts/evidence-delete.sh x'
check ask  'scripts/evidence-delete.sh x'
check pass 'grep -n "gh pr merge" notes.md'
check pass 'cat docs/terraform apply.md'
check ask  'npx wrangler deploy'
check ask  'echo done && sudo npm publish'
check ask  'echo npm publish'
check pass 'grep -rn "gh pr merge" .'
check pass 'git diff -- scripts/evidence-delete.sh'
check ask  'less scripts/evidence-delete.sh'
check ask  "less '+!gh pr merge 5' f"
check ask  "more scripts/evidence-delete.sh"
check ask  "rg --pre 'gh pr merge 5' x"
check ask  "rg --pre=scripts/evidence-delete.sh x f"
check ask  "/tmp/cat 'gh pr merge 5'"
check ask  "for c in 'gh pr merge 5'; do \$c; done"
check ask  'for f in scripts/evidence-delete.sh; do "$f" x; done'
check ask  "stat -f 'gh pr merge 5' f | ksh"
check ask  "stat -f 'gh pr merge 5' f | awk '{system(\$0)}'"
check ask  "stat -f 'gh pr merge 5' f | while read -r c; do \$c; done"
check ask  "git log -1 --format='tformat:gh pr merge 5' | ksh"
check ask  "git --namespace log -c alias.x='!gh pr merge 5' x"
check ask  "git --git-dir log -c alias.x='!gh pr merge 5' x"
check ask  "git --work-tree log -c alias.x='!gh pr merge 5' x"
check ask  "git --attr-source log -c alias.x='!gh pr merge 5' x"
check ask  "rg '--pre' scripts/evidence-delete.sh init f"
check ask  "rg --hostname-bin=scripts/evidence-delete.sh x f"
check ask  'git -c diff.external=scripts/evidence-delete.sh diff'
check ask  "git -p log 'gh pr merge 5'"
check pass 'grep -rn "gh pr merge" .'
check pass 'git -C /tmp log --oneline -- scripts/evidence-delete.sh'
check pass 'for f in scripts/evidence-delete.sh; do cat "$f"; done'
check pass 'cat scripts/evidence-delete.sh | head -5'
check ask  'rg "npm publish" docs'
check ask  "sed -n 'e gh pr merge 5' f"
check ask  "sed -n 's/.*/gh pr merge 5/e' f"
check ask  "git grep -O'gh pr merge 5' -e x"
check ask  "git grep --open-files-in-pager='npm publish' x"
check ask  "bat --paging=always --pager 'gh pr merge 5' f"
check ask  "git -c core.pager='gh pr merge 5' log"
check pass 'git log -p scripts/evidence-delete.sh'
check pass 'cat scripts/evidence-delete.sh'
# fail closed: wrappers, flags, keywords, and fan-out stay guarded
check ask  'echo 5 | xargs gh pr merge'
check ask  'nohup gh pr merge 5'
check ask  'timeout 60 npm publish'
check ask  'sudo -u me gh pr merge 5'
check ask  'env -i gh pr merge 5'
check ask  'if gh pr merge 5; then echo ok; fi'
check ask  'while gh pr merge 5; do break; done'
check ask  'find . -exec gh pr merge 5 \;'
check ask  'parallel cf r2 objects delete {} --bucket-name b ::: k1 k2'
check ask  'echo `gh pr merge 5`'
check ask  "bash -c 'sudo gh pr merge 5'"
check ask  "bash -c 'bash scripts/evidence-delete.sh x'"
check ask  '/bin/bash scripts/evidence-delete.sh x'
check ask  'bash -x scripts/evidence-delete.sh x'
check ask  'source scripts/evidence-delete.sh x'
check ask  'npx -y wrangler deploy'
check ask  'pnpm dlx wrangler deploy'
check ask  'yarn npm publish'
# I5: forms the first word walk missed
check ask  'PATH=~/.local/git/bin:$PATH git push -f origin x'
check ask  'GIT_SSH_COMMAND="ssh -i ~/.ssh/github" git push --force origin main'
check ask  'gh pr -R o/r merge 1'
check ask  'gh pr --repo o/r merge 1'
check ask  'git push --mirror'
check ask  'git push origin :wstack/x'
check ask  'gh pr close 1 -d'
check pass 'git push origin HEAD'
check pass 'gh pr -R o/r list'
check pass 'gh pr close 1'
assert "git push origin HEAD on main: ask" '[ "$(decide_in "$main_repo" Bash "git push origin HEAD")" = "ask" ]'
assert "git push origin @ on main: ask" '[ "$(decide_in "$main_repo" Bash "git push origin @")" = "ask" ]'

# A3-7 full path, A3-16 checkout judged per segment
check ask  '/usr/bin/git push origin main'
check ask  '/usr/local/bin/gh pr merge 1'
check ask  '/usr/bin/git checkout main && /usr/bin/git push'
check pass 'git commit -m "run git checkout main" && git push'
check ask  'git checkout main && git push'
check ask  'FOO=1 git checkout main && git push'
check ask  'env X=1 git checkout main && git push'
check ask  'env git checkout main && git push'
check ask  'command git checkout main && git push'
check ask  'sudo git checkout main && git push'
check ask  'time git checkout main && git push'
check ask  'nice git checkout main && git push'
check ask  'bash -c '\''git checkout main && git push'\'''
check ask  'sh -c "git checkout main && git push"'
check ask  'zsh -c '\''git checkout main && git push'\'''
check ask  'eval "git checkout main && git push"'
check ask  'if true; then git checkout main; fi; git push'
check ask  '{ git checkout main; git push; }'
check ask  '! git checkout main || git push'
check ask  'for i in 1; do git checkout main; done; git push'
check ask  '"/usr/bin/git" checkout main && git push'
assert "tool Write: pass" '[ "$(decide_in "$feature_repo" Write "gh pr merge 1")" = "pass" ]'

no_jq_output="$(echo '{}' | PATH=/nonexistent "$BASH" "$guard")"
assert "missing jq asks" '[[ "$no_jq_output" == *"\"permissionDecision\":\"ask\""* && "$no_jq_output" == *"install jq"* ]]'

finish
