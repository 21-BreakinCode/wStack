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
assert "reader reads the YAML and the team_docs globs" 'grep -qF "<app_name>.contract.yaml" "$reader" && grep -qF "the files that the \`sources\` globs of \`team_docs\` match" "$reader" && ! grep -qF "@path" "$reader"'
assert "reader finds a stale dependency through the Service Mapping" 'grep -F "stale_dependencies" "$reader" | grep -qF "Service Mapping"'
assert "reader: an empty planned list means no plan item" 'grep -qF "If \`planned\` is empty, the service has no planned item." "$reader" && ! grep -qF "plan.md" "$reader"'
assert "reader: patch can hold only remove_planned" 'grep -qF "It can hold only \`remove_planned\`." "$reader"'
assert "reader: patch covers consumers and gotchas" 'grep -qF "also covers \`consumers\` and \`gotchas\`" "$reader"'
assert "reader writes a YAML patch that carries sources" 'grep -qF "The patch is YAML with a \`sections:\` map." "$reader" && grep -qF "Each section in the map is the whole new section, with its \`sources\` list" "$reader" && grep -qF "remove_planned: [<id>, ...]" "$reader"'
assert "reader quotes a ref that holds a comma" 'grep -qF "put a ref that holds a comma in double quotes" "$reader"'
assert "historian reads team ADRs" 'grep -q "docs/adr/" "$repo_root/agents/contract-historian.md"'
historian="$repo_root/agents/contract-historian.md"
assert "historian: a missing decisions/ goes on" 'grep -F "decisions/" "$historian" | grep -qF "If the folder does not exist"'
assert "historian: a withdrawn decision is not the reason" 'grep -F "status: withdrawn" "$historian" | grep -qF "Skip it, or name it as withdrawn."'
assert "historian: a missing docs/adr/ goes on" 'grep -F "docs/adr/" "$historian" | grep -qF "If the folder does not exist"'
assert "reviewer judges whether each ref shows its claim" 'grep -qx "Contract:" "$repo_root/agents/reviewer.md" && grep -qF "Does its ref show the claim?" "$repo_root/agents/reviewer.md" && grep -qF "A wrong claim is a blocking finding of kind \`spec-mismatch\`." "$repo_root/agents/reviewer.md"'
assert "reviewer: a new project needs sources and each answer as a plan item" 'grep -qF "Check that each section that needs \`sources\` has them: \`team_docs\`, \`abilities\`, \`interfaces\`, and \`depends_on\`. Also check that each answer under \`## Contract changes\` in the spec is a plan item under \`planned\`." "$repo_root/agents/reviewer.md" && ! grep -qF "has content" "$repo_root/agents/reviewer.md"'
assert "reviewer has contract-mismatch" 'grep -q "| \`contract-mismatch\` | yes |" "$repo_root/agents/reviewer.md"'
analyst="$repo_root/agents/retro-analyst.md"
assert "analyst reads retro-note.md and transcript_stats" 'grep -qF "retro-note.md" "$analyst" && grep -qF "transcript_stats" "$analyst"'
assert "analyst reads state, age_days, facts_file and needs a finished task as evidence" 'grep -qF "\`age_days\`" "$analyst" && grep -qF "\`facts_file\`" "$analyst" && grep -qF "Open tasks are context only" "$analyst" && grep -qF "at least one finished task" "$analyst"'
assert "analyst has a Questions block and no question without a session id" 'grep -qF "## Questions" "$analyst" && grep -qF "A task with an empty \`session_ids\` gets no question." "$analyst"'
assert "analyst looks for the same top_bash command in two or more tasks" 'grep -qF "The same \`top_bash\` command in two or more tasks." "$analyst"'
assert "analyst trusts the stats over a note, a log, or an answer" 'grep -qF "trust the stats and name the mismatch" "$analyst"'
assert "analyst: no proposals can still come with questions" 'grep -qF "can still have a \`## Questions\` block" "$analyst"'
assert "analyst and run-retro descriptions name the tasks that no retro read yet" 'grep "^description:" "$analyst" | grep -qF "that no retro read yet" && grep "^description:" "$repo_root/skills/run-retro/SKILL.md" | grep -qF "that no retro read yet" && ! grep -qF "past week" "$analyst" "$repo_root/skills/run-retro/SKILL.md"'
assert "analyst proposes fact candidates with a facts file" 'grep -qF "## Fact candidates" "$analyst" && grep -qF "Facts file:" "$analyst"'
assert "reader reads the facts file and replies with Project facts" 'grep -qF ".facts.md" "$reader" && grep -qF "### Project facts" "$reader"'
assert "reviewer judges skipped cases and stale references" 'grep -qF "skipped cases" "$repo_root/agents/reviewer.md" && grep -qF "stale reference" "$repo_root/agents/reviewer.md"'
finish
