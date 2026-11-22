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
assert "reader: sources comment on the line after its heading" 'grep -q "on the line after its heading" "$reader"'
assert "reader finds a stale dependency through the Service Mapping" 'grep -F "stale_dependencies" "$reader" | grep -qF "Service Mapping"'
assert "reader: a missing plan.md means no plan item" 'grep -qF "If \`plan.md\` does not exist, the service has no planned item." "$reader"'
assert "reader: patch can hold only Remove from plan" 'grep -q "can hold only" "$reader"'
assert "reader: patch covers Consumers and Gotchas" 'grep -q "also covers \`Consumers\` and \`Gotchas\`" "$reader"'
assert "historian reads team ADRs" 'grep -q "docs/adr/" "$repo_root/agents/contract-historian.md"'
historian="$repo_root/agents/contract-historian.md"
assert "historian: a missing decisions/ goes on" 'grep -F "decisions/" "$historian" | grep -qF "If the folder does not exist"'
assert "historian: a withdrawn decision is not the reason" 'grep -F "status: withdrawn" "$historian" | grep -qF "Skip it, or name it as withdrawn."'
assert "historian: a missing docs/adr/ goes on" 'grep -F "docs/adr/" "$historian" | grep -qF "If the folder does not exist"'
assert "reviewer has contract-mismatch" 'grep -q "| \`contract-mismatch\` | yes |" "$repo_root/agents/reviewer.md"'
analyst="$repo_root/agents/retro-analyst.md"
assert "analyst reads retro-note.md and transcript_stats" 'grep -qF "retro-note.md" "$analyst" && grep -qF "transcript_stats" "$analyst"'
assert "analyst has a Questions block and no question without a session id" 'grep -qF "## Questions" "$analyst" && grep -qF "A task with an empty \`session_ids\` gets no question." "$analyst"'
assert "analyst looks for the same top_bash command in two or more tasks" 'grep -qF "The same \`top_bash\` command in two or more tasks." "$analyst"'
assert "analyst trusts the stats over a note, a log, or an answer" 'grep -qF "trust the stats and name the mismatch" "$analyst"'
assert "analyst: no proposals can still come with questions" 'grep -qF "can still have a \`## Questions\` block" "$analyst"'
finish
