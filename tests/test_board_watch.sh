#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
source "$repo_root/scripts/lib/frontmatter.sh"
script="$repo_root/scripts/board-watch.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"; mkdir -p "$HOME/.claude/projects/-fake-project"
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export FAKE_LOG="$work_dir/log"
unset HERDR_ENV
vault="$work_dir/vault"; mkdir -p "$vault"
cp -R "$repo_root/tests/fixtures/board-transcripts/." "$HOME/.claude/projects/-fake-project/"
touch -t "$(date -v-2H +%Y%m%d%H%M)" "$HOME"/.claude/projects/-fake-project/aaaaaaaa-0000-4000-8000-000000000001/subagents/agent-stale.jsonl
folder="$(bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug watch-me --date "$(date +%Y-%m-%d)" --idea x | tail -n 1)"
fm_set "$folder/spec.md" status executing
bash "$repo_root/scripts/session-id-add.sh" "$folder/spec.md" aaaaaaaa-0000-4000-8000-000000000001

frame="$(/bin/bash "$script" --vault "$vault" --tasks-dir T --once)" && status=0 || status=$?
assert "--once exits 0" '[ "$status" = 0 ]'
assert "header line holds the group and the slug" 'grep -qE "^other +watch-me +executing" <<<"$frame"'
assert "header line holds changes" 'grep -qE "^other +watch-me .* changes:" <<<"$frame"'
assert "tool line holds the tool and the hint" 'grep -qE "^  tool: Bash +Run the unit tests" <<<"$frame"'
assert "one line per running subagent, none for finished or stale" '[ "$(grep -c "^  subagent:" <<<"$frame")" = 1 ] && grep -qE "^  subagent: Explore +Find the login handlers +Grep" <<<"$frame"'
stalled_folder="$(bash "$repo_root/scripts/new-task-folder.sh" --vault "$vault" --tasks-dir T --slug stuck-one --date "$(date +%Y-%m-%d)" --idea x | tail -n 1)"
fm_set "$stalled_folder/spec.md" status executing
mkdir -p "$HOME/.claude/projects/-stalled-project"
printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","name":"Bash","input":{"description":"Run the tests"}}]}}\n' \
  "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S.123Z)" > "$HOME/.claude/projects/-stalled-project/bbbbbbbb-0000-4000-8000-000000000001.jsonl"
bash "$repo_root/scripts/session-id-add.sh" "$stalled_folder/spec.md" bbbbbbbb-0000-4000-8000-000000000001
frame="$(HERDR_ENV=1 FAKE_AGENT_STATES=stuck-one=idle,watch-me=working /bin/bash "$script" --vault "$vault" --tasks-dir T --once)"
assert "a stalled RD line holds its idle minutes" 'grep -E "^stalled +stuck-one " <<<"$frame" | grep -qE "idle [0-9]+m"'
assert "a working RD line has no idle minutes" '! grep -E "^working +watch-me " <<<"$frame" | grep -q "idle [0-9]*m"'
assert "--once does not clear the screen" '! grep -q "$(printf "\033")" <<<"$frame"'
assert "no vault folder prints a no-RD line and exits 0" '[ "$(/bin/bash "$script" --vault "$work_dir/none" --tasks-dir T --once)" = "no RD is open" ]'
status=0; /bin/bash "$script" --vault "$vault" --tasks-dir T --once --interval 0 >/dev/null 2>&1 || status=$?
assert "a zero interval exits 1" '[ "$status" = 1 ]'
status=0; /bin/bash "$script" --vault "$vault" --tasks-dir T --once --interval abc >/dev/null 2>&1 || status=$?
assert "a text interval exits 1" '[ "$status" = 1 ]'
fake_bin="$work_dir/bin"; mkdir -p "$fake_bin"
status=0; frame="$(WSTACK_BOARD_ACTIVE_MINUTES=abc /bin/bash "$script" --vault "$vault" --tasks-dir T --once 2>&1)" || status=$?
assert "a board.sh warning shows in the frame" 'grep -q "positive integer" <<<"$frame"'
cp "$repo_root/scripts/board-watch.sh" "$work_dir/board-watch.sh"
printf '#!/usr/bin/env bash\necho "boom from board" >&2\nexit 4\n' > "$work_dir/board.sh"
status=0; frame="$(/bin/bash "$work_dir/board-watch.sh" --vault "$vault" --tasks-dir T --once 2>&1)" || status=$?
assert "a board.sh failure shows its stderr and exits 1 with --once" '[ "$status" = 1 ] && grep -q "boom from board" <<<"$frame"'
finish
