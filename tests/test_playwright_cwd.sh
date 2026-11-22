#!/usr/bin/env bash
# A3-2: playwright-cli must run in a throwaway folder, never in the caller's folder.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/bin" "$work_dir/caller"

cat > "$work_dir/bin/playwright-cli" <<'FAKE'
#!/usr/bin/env bash
pwd -P >> "$FAKE_PW_CWD_LOG" || exit 1
echo "$*" >> "$FAKE_PW_ARGS_LOG"
case " $* " in
  *" --raw eval "*) echo 100 ;;
  *" run-code "*) echo '"<svg></svg>"' ;;
esac
FAKE
chmod +x "$work_dir/bin/playwright-cli"
export FAKE_PW_CWD_LOG="$work_dir/cwd.log" FAKE_PW_ARGS_LOG="$work_dir/args.log"
export PATH="$work_dir/bin:$PATH"
caller_dir="$(cd "$work_dir/caller" && pwd -P)"

echo '<!doctype html><body>x' > "$work_dir/caller/page.html"
echo '{"elements":[]}' > "$work_dir/caller/scene.excalidraw"
cd "$work_dir/caller"
width_exit=0
bash "$repo_root/scripts/check-page-width.sh" page.html >/dev/null 2>&1 || width_exit=$?
render_exit=0
bash "$repo_root/scripts/render-excalidraw.sh" scene.excalidraw out.svg >/dev/null 2>&1 || render_exit=$?

assert "check-page-width exits 0" '[ "$width_exit" -eq 0 ]'
assert "render-excalidraw exits 0 and writes the svg in the caller folder" '[ "$render_exit" -eq 0 ] && [ -f "$caller_dir/out.svg" ]'
assert "playwright-cli ran exactly 7 times, close included" '[ "$(wc -l < "$FAKE_PW_CWD_LOG")" -eq 7 ] && [ "$(grep -c " close" "$FAKE_PW_ARGS_LOG")" -eq 2 ]'
assert "playwright-cli never ran in the caller folder" '! grep -qx "$caller_dir" "$FAKE_PW_CWD_LOG"'
# A3-1: the web check picks a free port, never a fixed one
assert "capture-evidence picks a free port" 'grep -q "s.bind((\"127.0.0.1\", 0))" "$repo_root/skills/capture-evidence/SKILL.md"'
finish
