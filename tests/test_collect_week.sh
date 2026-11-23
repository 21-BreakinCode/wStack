#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/collect-week.sh"
vault="$repo_root/tests/fixtures/week/My Vault"
out="$(bash "$script" --vault "$vault" --tasks-dir Tasks --today 2026-11-18)"
assert "every finished task is read, whatever its date" '[ "$(jq length <<<"$out")" = 5 ]'
assert "old finished folder is present" '[ "$(jq -r "[.[] | select(.task_id == \"2026-10-20-old-task\")] | length" <<<"$out")" = 1 ]'
assert "retry fixture has retries 3" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-16-fix-date-parser\") | .run_log.retries" <<<"$out")" = 3 ]'
assert "stopped_for_user is parsed JSON" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-16-fix-date-parser\") | .run_log.stopped_for_user[0].stage" <<<"$out")" = verify ]'
assert "folder path keeps the space" '[ "$(jq -r ".[1].folder" <<<"$out")" = "$vault/Tasks/2026-11-12-export-notes" ]'
assert "report frontmatter is present" '[ "$(jq -r ".[1].report.approval_needed" <<<"$out")" = false ]'
# retro_read mark, state, age_days, facts_file
mark_vault="$(mktemp -d)/mark vault"
trap 'rm -rf "$(dirname "$mark_vault")"' EXIT
mk_task() {  # <id> <status> <retro_read>
  mkdir -p "$mark_vault/Tasks/$1"
  printf -- '---\ntask_id: %s\nstatus: %s\nretro_read: %s\n---\n' "$1" "$2" "$3" > "$mark_vault/Tasks/$1/spec.md"
}
mk_task 2026-11-10-long delivered ""
mk_task 2026-11-28-read delivered 2026-11-29
mk_task 2026-11-25-open executing ""
mk_task 2026-11-20-cancelled cancelled ""
mkdir -p "$mark_vault/Tasks/_archive/2026-11-01-old"
mk_task _archive/2026-11-01-old delivered ""
printf -- '---\ncontract_file: %s/Services/app/app.md\n---\n' "$mark_vault" > "$mark_vault/Tasks/2026-11-10-long/contract-brief.md"
mark_out="$(bash "$script" --vault "$mark_vault" --tasks-dir Tasks --today 2026-11-30)"
assert "finished task 20 days old is read" 'jq -e ".[] | select(.task_id==\"2026-11-10-long\") | .state==\"finished\"" <<<"$mark_out" >/dev/null'
assert "task with retro_read is skipped" '! jq -e ".[] | select(.task_id==\"2026-11-28-read\")" <<<"$mark_out" >/dev/null'
assert "open task carries state and age_days" 'jq -e ".[] | select(.task_id==\"2026-11-25-open\") | .state==\"open\" and .age_days==5" <<<"$mark_out" >/dev/null'
assert "cancelled task is finished" 'jq -e ".[] | select(.task_id==\"2026-11-20-cancelled\") | .state==\"finished\"" <<<"$mark_out" >/dev/null'
assert "finished task carries age_days" 'jq -e ".[] | select(.task_id==\"2026-11-10-long\") | .age_days==20" <<<"$mark_out" >/dev/null'
assert "archive is never read" '! jq -e ".[] | select(.task_id==\"2026-11-01-old\")" <<<"$mark_out" >/dev/null'
assert "facts_file comes from contract-brief.md" 'jq -e ".[] | select(.task_id==\"2026-11-10-long\") | .facts_file==\"$mark_vault/Services/app/app.facts.md\"" <<<"$mark_out" >/dev/null'
assert "no contract-brief.md gives null" 'jq -e ".[] | select(.task_id==\"2026-11-25-open\") | .facts_file==null" <<<"$mark_out" >/dev/null'
assert "--days is gone" '! bash "$script" --vault "$mark_vault" --tasks-dir Tasks --days 7 2>/dev/null'
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
# a bad id in one task must not stop the run or another task's stats
mkdir -p "$stats_vault/Tasks/2026-11-18-bad-id" "$stats_vault/Tasks/2026-11-18-only-bad-id"
printf -- '---\ntask_id: x\nsession_ids: ["%s", "not-a-uuid"]\n---\n' "$stats_session" > "$stats_vault/Tasks/2026-11-18-bad-id/spec.md"
printf -- '---\ntask_id: y\nsession_ids: ["not-a-uuid"]\n---\n' > "$stats_vault/Tasks/2026-11-18-only-bad-id/spec.md"
bad_id_out="$(HOME="$stats_home" bash "$script" --vault "$stats_vault" --tasks-dir Tasks --today 2026-11-18)"
assert "bad id is dropped, good id still counted" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-18-bad-id\") | .transcript_stats.found" <<<"$bad_id_out")" = 1 ]'
assert "only bad ids gives null" '[ "$(jq -c ".[] | select(.task_id == \"2026-11-18-only-bad-id\") | .transcript_stats" <<<"$bad_id_out")" = null ]'
assert "other task keeps its stats" '[ "$(jq -r ".[] | select(.task_id == \"2026-11-18-with-sessions\") | .transcript_stats.found" <<<"$bad_id_out")" = 1 ]'
assert "session_ids gives transcript_stats with found 1" '[ "$(jq -r ".[0].transcript_stats.found" <<<"$stats_out")" = 1 ]'
assert "transcript_stats counts the compaction" '[ "$(jq -r ".[0].transcript_stats.compactions" <<<"$stats_out")" = 1 ]'
# stats failure: an unreadable transcript gives null, one stderr line, exit 0
chmod 000 "$stats_home/.claude/projects/-proj/$stats_session.jsonl"
trap 'chmod 644 "$stats_home/.claude/projects/-proj/$stats_session.jsonl" 2>/dev/null || true; rm -rf "$stats_home" "$(dirname "$mark_vault")"' EXIT
fail_rc=0; fail_out="$(HOME="$stats_home" bash "$script" --vault "$stats_vault" --tasks-dir Tasks --today 2026-11-18 2>"$stats_home/err")" || fail_rc=$?
assert "stats failure exits 0 with transcript_stats null" '[ "$fail_rc" = 0 ] && [ "$(jq -c ".[] | select(.task_id == \"2026-11-18-with-sessions\") | .transcript_stats" <<<"$fail_out")" = null ]'
assert "stats failure prints one stderr line naming the task (jq may add its own)" '[ "$(grep -c "transcript stats failed for 2026-11-18-with-sessions" "$stats_home/err")" = 1 ]'
chmod 644 "$stats_home/.claude/projects/-proj/$stats_session.jsonl"
rm -rf "$stats_home"
assert "bad vault exits 1" '! bash "$script" --vault "$vault" --tasks-dir Nope --today 2026-11-18 2>/dev/null'
finish
