#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
render="$repo_root/scripts/render-page.sh"
export AM_HOME="$work_dir/am-home"
printf '# Title\n\n## Goal\n\nShort text.\n' > "$work_dir/draft.md"

# fake am.mjs that fails
echo 'process.exit(3)' > "$work_dir/fail.mjs"
fail_exit=0
fail_output="$(WSTACK_AMJS="$work_dir/fail.mjs" bash "$render" "$work_dir/draft.md" "$work_dir/out.html" 2>&1)" || fail_exit=$?
assert "render failure exits 2" '[ "$fail_exit" -eq 2 ]'
assert "render failure names the install command" '[[ "$fail_output" == *"claude plugin install answer-me-with-html@answer-me-with-html"* ]]'

# am.mjs path that does not exist
missing_exit=0
WSTACK_AMJS="$work_dir/none.mjs" bash "$render" "$work_dir/draft.md" "$work_dir/out.html" >/dev/null 2>&1 || missing_exit=$?
assert "missing am.mjs exits 2" '[ "$missing_exit" -eq 2 ]'

# missing draft
nodraft_exit=0
WSTACK_AMJS="$work_dir/fail.mjs" bash "$render" "$work_dir/none.md" "$work_dir/out.html" >/dev/null 2>&1 || nodraft_exit=$?
assert "missing draft exits 2" '[ "$nodraft_exit" -eq 2 ]'

# fake am.mjs that writes a page; the width check decides the exit code
cat > "$work_dir/fake.mjs" <<'JS'
import { writeFileSync } from "node:fs";
const out = process.argv[process.argv.indexOf("-o") + 1];
const wide = process.env.FAKE_WIDE === "1";
writeFileSync(out, `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><body>${wide ? '<table style="width:900px"><tr><td>x</td></tr></table>' : "<p>ok</p>"}`);
JS
if command -v playwright-cli >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  fit_exit=0
  WSTACK_AMJS="$work_dir/fake.mjs" bash "$render" "$work_dir/draft.md" "$work_dir/fit.html" >/dev/null 2>&1 || fit_exit=$?
  assert "fake render that fits exits 0" '[ "$fit_exit" -eq 0 ] && [ -f "$work_dir/fit.html" ]'
  wide_exit=0
  wide_output="$(FAKE_WIDE=1 WSTACK_AMJS="$work_dir/fake.mjs" bash "$render" "$work_dir/draft.md" "$work_dir/wide.html" 2>&1)" || wide_exit=$?
  assert "fake render that is too wide exits 1 and prints the width" '[ "$wide_exit" -eq 1 ] && [[ "$wide_output" == *9* ]]'
else
  echo "SKIP width-check cases: playwright-cli or node missing"
fi

# real render
real_amjs="${WSTACK_AMJS:-}"
if [ -z "$real_amjs" ]; then
  install_path="$(claude plugin list --json 2>/dev/null | jq -r '[.[] | select(.id == "answer-me-with-html@answer-me-with-html" and .enabled == true)] | first | .installPath // empty' 2>/dev/null || true)"
  [ -z "$install_path" ] || real_amjs="$install_path/answer-me-with-html/scripts/am.mjs"
fi
if [ -f "$real_amjs" ] && command -v playwright-cli >/dev/null 2>&1; then
  real_exit=0
  bash "$render" "$work_dir/draft.md" "$work_dir/real/spec.html" >/dev/null 2>&1 || real_exit=$?
  assert "real render fits at 375 and creates the folder" '[ "$real_exit" -eq 0 ] && [ -s "$work_dir/real/spec.html" ]'
else
  echo "SKIP real render: answer-me-with-html or playwright-cli not found"
fi
finish
