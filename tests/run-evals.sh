#!/usr/bin/env bash
# Usage: tests/run-evals.sh <claude plugin eval args...>
# Runs the plugin evals from a staged copy of the plugin, because the eval sandbox has no installed
# plugins and so cannot satisfy the answer-me-with-html dependency. The copy drops that dependency.
# It also replaces preflight.sh with a stub that prints OK: the sandbox hides git and claude, so the real
# base check can never pass there (preflight has its own test). It fills the placeholder
# __AMJS__ (am.mjs of the installed plugin) and __WEEK_FIXTURE__ (the staged tests/fixtures/week). The eval vault is the sandbox working directory (case env sets it to "."):
# the sandbox lets a run write only there.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT

install_path="$(claude plugin list --json | jq -r '[.[] | select(.id == "answer-me-with-html@answer-me-with-html" and .enabled == true)] | first | .installPath // empty')"
real_amjs="$install_path/answer-me-with-html/scripts/am.mjs"
[ -n "$install_path" ] && [ -f "$real_amjs" ] || { echo "run-evals: answer-me-with-html is not installed" >&2; exit 2; }

mkdir -p "$stage_dir/plugin"
tar -C "$repo_root" --exclude=.git --exclude=evals/results --exclude=tests/tmp --exclude=tests/spikes -cf - . | tar -C "$stage_dir/plugin" -xf -
jq 'del(.dependencies)' "$repo_root/.claude-plugin/plugin.json" > "$stage_dir/plugin.json"
mv "$stage_dir/plugin.json" "$stage_dir/plugin/.claude-plugin/plugin.json"
# The sandbox cannot read ~/.claude, so the staged copy carries a copy of am.mjs.
mkdir -p "$stage_dir/plugin/answer-me-with-html-copy"
cp -R "$install_path/answer-me-with-html/." "$stage_dir/plugin/answer-me-with-html-copy/"
amjs="$stage_dir/plugin/answer-me-with-html-copy/scripts/am.mjs"
# The sandbox also blocks binding a local port, so check-page-width.sh gets a stub. It prints 375, unless the
# case env sets EVAL_WSTACK_STUB_WIDTH_FIRST: then the first call per page prints that width and exits 1.
cat > "$stage_dir/plugin/scripts/check-page-width.sh" <<'STUB'
#!/usr/bin/env bash
call_marker="$(dirname "$1")/.width-check-called"
if [ -n "${EVAL_WSTACK_STUB_WIDTH_FIRST:-}" ] && [ ! -e "$call_marker" ]; then
  touch "$call_marker"; echo "$EVAL_WSTACK_STUB_WIDTH_FIRST"; exit 1
fi
echo 375
STUB
# preflight.sh stub: base prints OK. With EVAL_WSTACK_STUB_PLAN_MISSING set, plan reports a missing tool.
cat > "$stage_dir/plugin/scripts/preflight.sh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = plan ] && [ -n "${EVAL_WSTACK_STUB_PLAN_MISSING:-}" ]; then
  echo "MISSING playwright-cli: npm i -g @playwright/cli@0.1.24"; exit 1
fi
echo "OK preflight stubbed for evals"
STUB
for prompt_file in "$stage_dir"/plugin/evals/*/prompt.md; do
  sed -i '' -e "s|__AMJS__|$amjs|g" -e "s|__WEEK_FIXTURE__|$stage_dir/plugin/tests/fixtures/week|g" "$prompt_file"
done

# Pass --json <file> to keep the results: the staged copy is deleted on exit.
env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
  claude plugin eval "$stage_dir/plugin" --runs 1 --trust-plugin --no-publish --ablation none \
  --allow-tools Bash Write Edit "$@"
