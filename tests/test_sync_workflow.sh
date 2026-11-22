#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
workflow="$repo_root/.github/workflows/sync-catalog.yml"

assert "workflow file exists" '[ -f "$workflow" ]'
[ -f "$workflow" ] || { finish; exit; }

for needle in 'CC_PLUGINS_TOKEN' 'repository: 21-BreakinCode/cc-plugins' 'cicd.sh SYNC' 'cicd.sh GEN' 'cicd.sh VERIFY'; do
  assert "workflow names '$needle'" 'grep -qF -- "$needle" "$workflow"'
done

verify_line="$(grep -nF 'cicd.sh VERIFY' "$workflow" | head -1 | cut -d: -f1)"
push_line="$(grep -nF 'git push' "$workflow" | head -1 | cut -d: -f1)"
assert "VERIFY comes before git push" '[ -n "$verify_line" ] && [ -n "$push_line" ] && [ "$verify_line" -lt "$push_line" ]'
guard_line="$(grep -nF -- '[ -n "$CC_PLUGINS_TOKEN" ]' "$workflow" | head -1 | cut -d: -f1)"
checkout_line="$(grep -nF 'repository: 21-BreakinCode/cc-plugins' "$workflow" | head -1 | cut -d: -f1)"
assert "token guard comes before the cc-plugins checkout" '[ -n "$guard_line" ] && [ -n "$checkout_line" ] && [ "$guard_line" -lt "$checkout_line" ]'
assert "workflow has a concurrency block" 'grep -q "^concurrency:" "$workflow"'
assert "workflow has workflow_dispatch" 'grep -q "workflow_dispatch:" "$workflow"'

push_block="$(awk '/^  push:/{p=1;next} p && /^  [a-z_]+:/{p=0} p' "$workflow")"
assert "push trigger is limited to main" 'printf "%s\n" "$push_block" | grep -qE "branches:.*\[ *main *\]|^ +- main$"'
for path_entry in '.claude-plugin/plugin.json' 'CHANGELOG.md' 'skills/**'; do
  assert "push trigger lists path '$path_entry'" 'printf "%s\n" "$push_block" | grep -qF -- "$path_entry"'
done
path_count="$(printf '%s\n' "$push_block" | grep -cE '^ +- ' || true)"
assert "push trigger lists exactly three paths" '[ "$path_count" -eq 3 ]'
finish
