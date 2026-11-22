#!/usr/bin/env bash
# Runs the resume restore block and the pause trace block of the skill text, in bash and in zsh when zsh exists.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
resume_skill="$repo_root/skills/resume-work/SKILL.md"
pause_skill="$repo_root/skills/pause-work/SKILL.md"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"; mkdir -p "$HOME"
test_shells=bash
if command -v zsh >/dev/null 2>&1; then test_shells="bash zsh"; fi
note_time=2026-11-22T10-00-00Z

sh_block_after() {  # <file> <text>: the first sh block after the first line that holds <text>
  awk -v marker="$2" '
    !found && index($0, marker) { found = 1; next }
    found && /^[[:space:]]*```sh[[:space:]]*$/ { inside = 1; next }
    inside && /^[[:space:]]*```[[:space:]]*$/ { exit }
    inside { sub(/^[[:space:]]+/, ""); print }
  ' "$1"
}
restore_block="$(sh_block_after "$resume_skill" '- Task note: read the status and `paused_from` first' | sed "s/<time>/$note_time/g")"
assert "restore block is in the skill text" 'grep -qF "if [ \"\$current_status\" = paused ]; then" <<<"$restore_block"'

run_restore() {  # <shell> <case> <status> <paused_from> [user_status]: sets rc and task_dir
  task_dir="$work_dir/$1-$2/my task"
  mkdir -p "$task_dir"
  printf -- '---\ntask_id: my-task\nstatus: %s\npaused_from: %s\n---\n\n# Spec\n' "$3" "$4" >"$task_dir/spec.md"
  printf '# Pause\n' >"$task_dir/pause.md"
  local preset
  preset="scripts='$repo_root/scripts'; task_dir='$task_dir'"
  [ "$#" -lt 5 ] || preset="$preset; user_status='$5'"
  rc=0; "$1" -c "$preset
$restore_block" >/dev/null 2>&1 || rc=$?
}
renamed() { [ ! -e "$task_dir/pause.md" ] && [ -f "$task_dir/pause-$note_time.md" ]; }
note_kept() { [ -f "$task_dir/pause.md" ] && [ ! -e "$task_dir/pause-$note_time.md" ]; }

for shell in $test_shells; do
  run_restore "$shell" cancelled cancelled executing
  assert "$shell: a status that is not paused stays" '[ "$rc" = 0 ] && [ "$(fm_get "$task_dir/spec.md" status)" = cancelled ] && [ -z "$(fm_get "$task_dir/spec.md" paused_from)" ] && renamed'
  run_restore "$shell" normal paused waiting-user
  assert "$shell: paused restores paused_from" '[ "$rc" = 0 ] && [ "$(fm_get "$task_dir/spec.md" status)" = waiting-user ] && [ -z "$(fm_get "$task_dir/spec.md" paused_from)" ] && renamed'
  run_restore "$shell" typo paused exectuing
  assert "$shell: a typo stops the block and keeps paused_from and the note" '[ "$rc" != 0 ] && [ "$(fm_get "$task_dir/spec.md" status)" = paused ] && [ "$(fm_get "$task_dir/spec.md" paused_from)" = exectuing ] && note_kept'
  run_restore "$shell" empty paused ''
  assert "$shell: an empty paused_from with no answer stops the block" '[ "$rc" != 0 ] && [ "$(fm_get "$task_dir/spec.md" status)" = paused ] && note_kept'
  run_restore "$shell" user paused '' drafting
  assert "$shell: the user status wins" '[ "$rc" = 0 ] && [ "$(fm_get "$task_dir/spec.md" status)" = drafting ] && renamed'
done

# The parent of the shell that runs the trace block is the session. Its command line holds the folder, so it must not be listed.
# Its child holds the folder too and must be listed as traced. The shell that runs the block holds "grep -F", so the block skips it.
trace_folder="$work_dir/trace folder"
trace_block="$(sh_block_after "$pause_skill" 'Run this in one Bash call. It lists the candidates' | sed "s|<path>|$trace_folder|g")"
session_script='echo "session=$$"
"$0" -c "sleep 5; :" "$1" 2>/dev/null & child=$!
echo "child=$child"
"$0" -c "$TRACE_BLOCK"
pkill -P "$child" sleep 2>/dev/null || true
kill "$child" 2>/dev/null || true
:'
for shell in $test_shells; do
  trace_out="$(TRACE_BLOCK="$trace_block" bash -c "$session_script" "$shell" "$trace_folder")"
  session_pid="$(sed -n 's/^session=//p' <<<"$trace_out")"
  child_pid="$(sed -n 's/^child=//p' <<<"$trace_out")"
  assert "$shell: the trace lists a child of the session as traced" '[ -n "$child_pid" ] && grep -q "^traced $child_pid " <<<"$trace_out"'
  assert "$shell: the trace never lists the session process" '[ -n "$session_pid" ] && ! grep -qE "^(traced|other) $session_pid " <<<"$trace_out"'
done
finish
