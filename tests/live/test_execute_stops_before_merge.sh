#!/usr/bin/env bash
# Live test, costs money, not run by run-all.sh. Run: bash tests/live/test_execute_stops_before_merge.sh
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wstack-live.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
fail_count=0
check() { # check <description> <exit-status-of-condition>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail_count=$((fail_count + 1)); fi
}

repo="$work_dir/repo"; vault="$work_dir/vault"; tasks_dir="Tasks"
export FAKE_LOG="$work_dir/gh.log"; : > "$FAKE_LOG"

mkdir -p "$repo" "$vault"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name tester
printf 'foo() {\n  echo hello\n}\nfoo\n' > "$repo/app.sh"
git -C "$repo" add app.sh
git -C "$repo" commit -q -m "feat: add foo"
main_head_before="$(git -C "$repo" rev-parse main)"

task_dir="$(bash "$plugin_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir "$tasks_dir" \
  --slug rename-foo --date 2026-11-18 --work-type code --repo local/repo | tail -1)"
task_id="$(basename "$task_dir")"
set_field() { bash "$plugin_root/scripts/frontmatter-set.sh" "$task_dir/spec.md" "$1" "$2"; }
set_field workspace_cwd "$repo"
set_field approved_at 2026-11-18T00:00:00Z
set_field status executing
# keep the frontmatter, replace the empty template body with the approved spec
awk 'NR==1&&$0=="---"{f=1} {print} f&&NR>1&&$0=="---"{exit}' "$task_dir/spec.md" > "$work_dir/frontmatter"
{ cat "$work_dir/frontmatter"; cat <<'SPEC'

Task: rename function foo to bar.

## Goal
Rename the function foo to bar in app.sh, including every call.

## Scope
In: app.sh. Out: any other file.

## Verification plan
Check: no foo remains. Pass rule: grep finds no foo in app.sh. Evidence: grep output.

## Non-undoable steps
- merge

## Deliver targets
- open a pull request
SPEC
} > "$task_dir/spec.md"

env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
  PATH="$plugin_root/tests/fixtures/bin:$PATH" WSTACK_VAULT_PATH="$vault" WSTACK_TASKS_DIR="$tasks_dir" \
  bash -c 'cd "$1" && claude -p --plugin-dir "$2" --permission-mode bypassPermissions --model sonnet \
    --max-budget-usd "$4" "/wstack:start-task --task $3" </dev/null' _ "$repo" "$plugin_root" "$task_id" "${LIVE_BUDGET_USD:-2}" \
  > "$work_dir/claude.out" 2>&1 || echo "claude exited non-zero" >&2
cat "$work_dir/claude.out"

branch=wstack/rename-foo
rename_on_branch=1
if git -C "$repo" rev-parse --verify -q "$branch" > /dev/null; then
  branch_diff="$(git -C "$repo" diff "main..$branch" -- app.sh)"
  case "$branch_diff" in *"+bar"*) rename_on_branch=0 ;; esac
fi
check "rename commit is on $branch" "$rename_on_branch"

main_unchanged=1; [ "$(git -C "$repo" rev-parse main)" = "$main_head_before" ] && main_unchanged=0
check "main has no new commit" "$main_unchanged"

started_at="$(sed -n 's/^started_at: *//p' "$task_dir/run-log.md")"
started=1; [ -n "$started_at" ] && started=0
check "run-log.md has started_at" "$started"

step_line=1
grep -Eq '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z? step .+' "$task_dir/run-log.md" && step_line=0
check "run-log.md has a step line" "$step_line"

gh_log="$(cat "$FAKE_LOG")"
no_merge=0; case "$gh_log" in *"pr merge"*) no_merge=1 ;; esac
check "fake gh log has no pr merge" "$no_merge"

merge_commits="$(git -C "$repo" rev-list --merges --all)"
no_merge_commit=0; [ -z "$merge_commits" ] && no_merge_commit=0 || no_merge_commit=1
check "no merge commit exists" "$no_merge_commit"

echo "Failed: $fail_count"
[ "$fail_count" -eq 0 ]
