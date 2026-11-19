#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/collect-week.sh"
vault="$repo_root/tests/fixtures/week/My Vault"
out="$(bash "$script" --vault "$vault" --tasks-dir Tasks --today 2026-11-18)"
assert "four tasks in the window" '[ "$(jq length <<<"$out")" = 4 ]'
assert "old folder is absent" '[ "$(jq -r "[.[] | select(.task_id == \"2026-10-20-old-task\")] | length" <<<"$out")" = 0 ]'
assert "retry fixture has retries 3" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-16-fix-date-parser\") | .run_log.retries" <<<"$out")" = 3 ]'
assert "stopped_for_user is parsed JSON" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-16-fix-date-parser\") | .run_log.stopped_for_user[0].stage" <<<"$out")" = verify ]'
assert "folder path keeps the space" '[ "$(jq -r ".[0].folder" <<<"$out")" = "$vault/Tasks/2026-11-12-export-notes" ]'
assert "report frontmatter is present" '[ "$(jq -r ".[0].report.approval_needed" <<<"$out")" = false ]'
assert "bad vault exits 1" '! bash "$script" --vault "$vault" --tasks-dir Nope --today 2026-11-18 2>/dev/null'
finish
