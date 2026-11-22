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
# M8: 7 days means today and the 6 days before, so a boundary task is in only one retro
boundary_vault="$(mktemp -d)/boundary vault"
trap 'rm -rf "$(dirname "$boundary_vault")"' EXIT
mkdir -p "$boundary_vault/Tasks/2026-11-12-six-days-ago" "$boundary_vault/Tasks/2026-11-11-seven-days-ago" "$boundary_vault/Tasks/2026-11-18-today"
boundary_ids="$(bash "$script" --vault "$boundary_vault" --tasks-dir Tasks --today 2026-11-18 | jq -r '[.[].task_id] | join(",")')"
assert "today-6 is in, today is in, today-7 is out" '[ "$boundary_ids" = "2026-11-12-six-days-ago,2026-11-18-today" ]'
assert "task with retro-note.md has_retro_note true" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-17-write-intro\") | .has_retro_note" <<<"$out")" = true ]'
assert "task without retro-note.md has_retro_note false" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-16-fix-date-parser\") | .has_retro_note" <<<"$out")" = false ]'
assert "no session_ids gives null transcript_stats" '[ "$(jq -c ".[] | select(.task_id == \"2026-11-16-fix-date-parser\") | .transcript_stats" <<<"$out")" = null ]'
# transcript_stats comes from spec.session_ids
stats_home="$(mktemp -d)"
stats_vault="$stats_home/vault"
stats_session=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
mkdir -p "$stats_vault/Tasks/2026-11-18-with-sessions" "$stats_home/.claude/projects/-proj"
printf -- '---\ntask_id: 2026-11-18-with-sessions\nsession_ids: ["%s"]\n---\n' "$stats_session" > "$stats_vault/Tasks/2026-11-18-with-sessions/spec.md"
cp "$repo_root/tests/fixtures/transcripts/session-a.jsonl" "$stats_home/.claude/projects/-proj/$stats_session.jsonl"
stats_out="$(HOME="$stats_home" bash "$script" --vault "$stats_vault" --tasks-dir Tasks --today 2026-11-18)"
rm -rf "$stats_home"
assert "session_ids gives transcript_stats with found 1" '[ "$(jq -r ".[0].transcript_stats.found" <<<"$stats_out")" = 1 ]'
assert "transcript_stats counts the compaction" '[ "$(jq -r ".[0].transcript_stats.compactions" <<<"$stats_out")" = 1 ]'
assert "bad vault exits 1" '! bash "$script" --vault "$vault" --tasks-dir Nope --today 2026-11-18 2>/dev/null'
finish
