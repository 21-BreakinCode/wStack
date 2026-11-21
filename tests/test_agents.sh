#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
for agent_file in "$repo_root"/agents/*.md; do
  agent="$(basename "$agent_file" .md)"
  assert "$agent: name matches file" '[ "$(sed -n "s/^name: //p" "$agent_file")" = "$agent" ]'
  assert "$agent: model sonnet" 'grep -qx "model: sonnet" "$agent_file"'
done
reader="$repo_root/agents/contract-reader.md"
assert "reader names the check" 'grep -q "scripts/contract-check.sh" "$reader"'
assert "reader has the patch marker" 'grep -qx "=== PATCH ===" "$reader"'
assert "reader never reads decisions" 'grep -q "never reads \`decisions/\`" "$reader"'
assert "historian reads team ADRs" 'grep -q "docs/adr/" "$repo_root/agents/contract-historian.md"'
assert "reviewer has contract-mismatch" 'grep -q "| \`contract-mismatch\` | yes |" "$repo_root/agents/reviewer.md"'
finish
