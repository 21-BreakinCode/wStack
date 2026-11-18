#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/pr-attach.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export PATH="$repo_root/tests/fixtures/bin:$PATH"
export WSTACK_EVIDENCE_ROOT="$work_dir/evidence"
export FAKE_LOG="$work_dir/gh.log"
echo "body" > "$work_dir/body.md"
ffmpeg -loglevel error -f lavfi -i testsrc=duration=1:size=320x180:rate=1 -frames:v 1 "$work_dir/shot.png"
cwebp -quiet "$work_dir/shot.png" -o "$work_dir/shot.webp"
ffmpeg -loglevel error -f lavfi -i testsrc=duration=2:size=320x180:rate=10 -c:v libvpx "$work_dir/clip.webm"

run() { bash "$script" --task-id t1 --title "My PR" --body-file "$work_dir/body.md" --max-mb "${MAX_MB:-5}" "$@" "$work_dir/shot.webp" "$work_dir/clip.webm"; }
cp "$work_dir/shot.png" "$work_dir/issue#12.png"

: > "$FAKE_LOG"
out="$(run --base main)"
assert "jpg attached" 'grep -qE -- "--attach [^ ]+/gh/shot\.jpg" "$FAKE_LOG"'
assert "mp4 attached" 'grep -qE -- "--attach [^ ]+/gh/clip\.mp4" "$FAKE_LOG"'
assert "base passed" 'grep -q -- "--base main" "$FAKE_LOG"'
assert "gh copies exist" '[ -f "$WSTACK_EVIDENCE_ROOT/t1/gh/shot.jpg" ] && [ -f "$WSTACK_EVIDENCE_ROOT/t1/gh/clip.mp4" ]'
assert "pr url printed" '[[ "$out" == *"/pull/1"* ]]'

: > "$FAKE_LOG"
out="$(FAKE_REPO_URL=https://ghe.example.com/o/r run)"
assert "ghes skipped message" '[[ "$out" == *"attachments skipped: not github.com"* ]]'
assert "ghes no attach" '! grep -q -- "--attach" "$FAKE_LOG"'
assert "ghes still creates pr" 'grep -q "pr create" "$FAKE_LOG"'

: > "$FAKE_LOG"
FAKE_REPO_URL=https://ghe.example.com/o/r run --allow-ghes >/dev/null
assert "allow-ghes attaches" 'grep -q -- "--attach" "$FAKE_LOG"'

status=0
out="$(FAKE_PR_FAIL=1 run)" || status=$?
assert "upload failure exits 0" '[ "$status" -eq 0 ]'
assert "upload failure message" '[[ "$out" == *"attachment upload failed"* ]]'
assert "upload failure prints url" '[[ "$out" == *"/pull/1"* ]]'

: > "$FAKE_LOG"
out="$(MAX_MB=0.0001 run)"
assert "unfit file still creates pr" 'grep -q "pr create" "$FAKE_LOG"'
assert "unfit run keeps other attachment" 'grep -q -- "--attach [^ ]*shot.jpg" "$FAKE_LOG" && ! grep -q "clip.mp4" "$FAKE_LOG"'
assert "unfit file named" '[[ "$out" == *"attachment upload failed: $work_dir/clip.webm"* ]]'
assert "unfit reason printed" '[[ "$out" == *"/pull/1"* ]]'

: > "$FAKE_LOG"
bash "$script" --task-id t2 --title T --body-file "$work_dir/body.md" --max-mb 5 "$work_dir/issue#12.png" >/dev/null
attach_arg="$(grep -o -- '--attach [^ ]*' "$FAKE_LOG")"
assert "hash name attached" '[[ "$attach_arg" == *"issue_12.jpg" ]]'
assert "no hash in attach path" '[[ "$attach_arg" != *"#"* ]]'

status=0
err="$(FAKE_PR_FAIL=nourl run 2>&1 >/dev/null)" || status=$?
assert "no-url failure exits 3" '[ "$status" -eq 3 ]'
assert "no-url failure message" '[[ "$err" == *"pull request not created: fatal: branch not pushed"* ]]'
finish
