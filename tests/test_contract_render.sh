#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
render="$repo_root/scripts/contract-render.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"
mkdir -p "$HOME" "$work_dir/vault"
contract="$work_dir/vault/svc.contract.yaml"
sha="abc1234def5678"

cat > "$contract" <<YAML
app_name: svc
repo: acme-org/svc
base_branch: main
verified_commit: "$sha"
verified_at: "2026-11-21T10:00:00Z"
pending: []
ignore: []
tags: [type/contract, project/acme/svc]
summary: Test service that stores things.
openapi: docs/openapi.json
sections:
  team_docs:
    sources: [README.md, "docs/**"]
  abilities:
    sources: ["cmd/**"]
    items:
      - text: A folder is read-only when \`bucket\` is set, and \`a\` < \`b\`.
        refs: ["app/a.py:12,40-42", "app/b.py:98, 131, 146"]
      - text: "# Starts with a hash and says: yes"
        refs: [app/c.py:1]
  interfaces:
    sources: ["api/**"]
    items:
      - text: '<script>alert(1)</script> {"errors": [...]}'
        refs: [api/routes.go:3-5]
  depends_on:
    sources: [pyproject.toml]
    items:
      - text: Calls other-svc with no timeout.
        refs: [app/client.py:10]
        app: other-svc
        mapped_commit: "4f3c2a1"
  consumers:
    items:
      - text: gen sends the tag enum.
        refs: ["acme-org/gen@ca3a273:src/media.ts:22"]
  gotchas:
    items:
      - text: Workers ack before commit.
        refs: [app/w.py:40-42]
        planned: ack-after-commit
      - text: Retry has no cap.
        refs: [app/r.py:5]
        planned: gone-item
      - text: "> quoted start"
        refs: [app/q.py:1]
      - text: "- dash start"
        refs: [app/q.py:2]
      - text: Plain gotcha.
        refs: [app/q.py:3]
  open_questions:
    items: []
planned:
  - id: ack-after-commit
    title: Ack after the commit
    why: A failed \`commit()\` loses the message.
    refs: [app/w.py:52-56]
YAML

out="$("$render" "$contract")"
note="$work_dir/vault/svc.md"
page="$HOME/.wstack/pages/contracts/svc.html"
assert "prints both paths" '[ "$out" = "$note
$page" ]'
assert "writes both files" '[ -f "$note" ] && [ -f "$page" ]'

body_first="$(awk 'c==2 && NF {print; exit} /^---$/ {c++}' "$note")"
assert "note starts with the generated notice" '[[ "$body_first" == *svc.contract.yaml* && "$body_first" == *"edits are lost"* ]]'
assert "note keeps the tags" 'sed -n 1,6p "$note" | grep -q "type/contract" && sed -n 1,6p "$note" | grep -q "^tags:"'

order="$(grep -E '^## ' "$note" | tr '\n' '|')"
assert "note section order" '[ "$order" = "## Gotchas|## Abilities|## Interfaces|## Depends on|## Consumers|## Planned|## Team docs|" ]'
assert "empty open questions get no heading" '! grep -q "Open questions" "$note" && ! grep -q "Open questions" "$page"'
assert "summary and freshness sit before Gotchas" '[ "$(grep -n "Test service that stores things" "$note" | cut -d: -f1)" -lt "$(grep -n "^## Gotchas" "$note" | cut -d: -f1)" ] && grep -q "$sha" "$note"'
assert "refs fold in a callout" 'grep -qF "> [!quote]- refs (2)" "$note"'
assert "ref links to GitHub at verified_commit" 'grep -qF "https://github.com/acme-org/svc/blob/$sha/api/routes.go#L3-L5" "$note"'
assert "comma list links the first range only" 'grep -qF "blob/$sha/app/b.py#L98)" "$note" && grep -qF "blob/$sha/app/a.py#L12)" "$note"'
assert "link text is the ref as written" 'grep -qF "[app/a.py:12,40-42]" "$note"'
assert "cross-repo ref links to its own repo and commit" 'grep -qF "https://github.com/acme-org/gen/blob/ca3a273/src/media.ts#L22" "$note"'
assert "openapi links to the file at verified_commit" 'grep -qF "https://github.com/acme-org/svc/blob/$sha/docs/openapi.json" "$note"'
assert "gotcha links its plan item" 'grep -qF "[[#Ack after the commit" "$note" && grep -q "^### Ack after the commit" "$note"'
assert "link to a removed plan item says plan item removed" 'grep -q "plan item removed" "$note" && grep -q "plan item removed" "$page"'
assert "leading hash is neutralized" '! grep -qE "^- # Starts" "$note" && grep -qF "Starts with a hash and says: yes" "$note"'
assert "leading quote and dash are neutralized" '! grep -qE "^- (>|-) " "$note" && grep -qF "quoted start" "$note" && grep -qF "dash start" "$note"'

assert "html shows inline code as <code>" 'grep -qF "read-only when <code>bucket</code> is set, and <code>a</code> &lt; <code>b</code>." "$page" && grep -qF "A failed <code>commit()</code> loses" "$page"'
assert "html has no raw backtick" '! grep -qF '"'"'`'"'"' "$page"'
assert "a card has no margin above its first child or below its last" 'grep -qF ".card > :first-child { margin-top: 0; }" "$page" && grep -qF ".card > :last-child { margin-bottom: 0; }" "$page"'
assert "html escapes text" 'grep -qF "&lt;script&gt;" "$page" && ! grep -q "<script" "$page"'
assert "html has the summary card counts" 'grep -q "5 gotchas" "$page" && grep -q "1 planned" "$page" && grep -q "main" "$page"'
assert "html pluralizes the ability and dependency counts" 'grep -q "2 abilities" "$page" && grep -q "1 dependency" "$page"'
assert "html has no invented plurals" '! grep -qE "abilitys|dependencys|planneds" "$page"'
assert "html refs sit in details" 'grep -q "<details" "$page" && grep -qF "https://github.com/acme-org/svc/blob/$sha/api/routes.go#L3-L5" "$page"'
assert "html is self-contained with viewport" 'grep -q "name=\"viewport\"" "$page" && grep -q "overflow-wrap: anywhere" "$page" && ! grep -qE "<script|<link" "$page"'

before_note="$(shasum "$note")"; before_page="$(shasum "$page")"
"$render" "$contract" >/dev/null
assert "render twice gives the same bytes" '[ "$before_note" = "$(shasum "$note")" ] && [ "$before_page" = "$(shasum "$page")" ]'

rc=0; "$render" "$work_dir/missing.yaml" >/dev/null 2>"$work_dir/err" || rc=$?
assert "missing file exits 2 with a cause" '[ "$rc" -eq 2 ] && [ -s "$work_dir/err" ]'

rc=0; bash "$repo_root/scripts/check-page-width.sh" "$page" >"$work_dir/width.out" 2>"$work_dir/width.err" || rc=$?
if [ "$rc" -eq 2 ] && grep -q "playwright-cli not found" "$work_dir/width.err"; then
  echo "  SKIP  html fits 375 px (playwright-cli missing)"
else
  assert "html fits 375 px" '[ "$rc" -eq 0 ]'
fi
assert "a contract without diagrams has no Diagrams heading" '! grep -q "^## Diagrams" "$note"'
assert "a page without diagrams has no Diagrams heading" '! grep -q "<h2>Diagrams</h2>" "$page"'

diagram_vault="$work_dir/diagram-vault"
mkdir -p "$diagram_vault/diagrams"
{ cat "$contract"; cat "$repo_root/tests/fixtures/contract/diagrams-block.yaml"; } > "$diagram_vault/svc.contract.yaml"
"$render" "$diagram_vault/svc.contract.yaml" >/dev/null
diagram_note="$diagram_vault/svc.md"
summary_line="$(grep -n "Test service that stores things" "$diagram_note" | cut -d: -f1)"
diagrams_line="$(grep -n "^## Diagrams" "$diagram_note" | cut -d: -f1)"
gotchas_line="$(grep -n "^## Gotchas" "$diagram_note" | cut -d: -f1)"
assert "the note shows Diagrams after the summary and before Gotchas" '[ "$summary_line" -lt "$diagrams_line" ] && [ "$diagrams_line" -lt "$gotchas_line" ]'
for heading in "Component flow" "Architecture (clean)"; do
  assert "the note has the heading $heading with a text block" '[ "$(grep -A2 -F "### $heading" "$diagram_note" | sed -n 3p)" = "\`\`\`text" ]'
done
assert "the sequence in the note is a numbered list" '[ "$(grep -A2 -F "### Sequence: Create an item" "$diagram_note" | sed -n 3p)" = "1. web-ui → api: POST /items" ]'
assert "the states in the note start with the initial state" '[ "$(grep -A2 -F "### States: Item status" "$diagram_note" | sed -n 3p)" = "Start: new" ]'
assert "the page has four SVG diagrams" 'grep -qF "<h2>Diagrams</h2>" "$page" && [ "$(grep -o "<svg" "$page" | wc -l | tr -d " ")" = "4" ]'
assert "the page lists the flow parts as cards, at most 2 columns, top aligned" 'grep -qF "class=\"cards\"" "$page" && grep -qF ".cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(340px, 100%), 1fr)); gap: 12px; align-items: start; }" "$page"'
assert "the figure stays in the column" 'grep -qF "main { max-width: 760px; margin: 0 auto; }" "$page" && grep -qF ".diagram { margin: 12px 0; }" "$page"'
assert "each SVG sits in a centered scroll box up to 1200 px" '[ "$(grep -o "<div class=\"scroll\"><svg" "$page" | wc -l | tr -d " ")" = "4" ] && grep -qF ".diagram .scroll { overflow-x: auto; position: relative; left: 50%; transform: translateX(-50%); width: min(1200px, calc(100vw - 32px)); }" "$page"'
assert "each SVG is centered at full size" 'grep -qF ".diagram svg { display: block; max-width: none; margin: 0 auto; }" "$page"'

cat > "$diagram_vault/diagrams/flow.html" <<HTML
<html><head><meta name="wstack-subject" content="flow"><meta name="wstack-subject-hash" content="0000"></head></html>
HTML
"$render" "$diagram_vault/svc.contract.yaml" >/dev/null
assert "the note lists deep dives with their state" 'grep -q "^### Deep dives" "$diagram_note" && grep -qF -- "- [flow.html](diagrams/flow.html) (stale)" "$diagram_note"'
fresh_hash="$(yq -o=json "$diagram_vault/svc.contract.yaml" | /usr/bin/python3 "$repo_root/scripts/contract_diagrams.py" hash flow)"
sed -i.bak "s/0000/$fresh_hash/" "$diagram_vault/diagrams/flow.html"
"$render" "$diagram_vault/svc.contract.yaml" >/dev/null
assert "a fresh deep dive has no mark" 'grep -qF -- "- [flow.html](diagrams/flow.html)" "$diagram_note" && ! grep -qF "flow.html](diagrams/flow.html) (" "$diagram_note"'

note_before="$(cat "$diagram_note")"
yq -i '.diagrams.architecture = "clean"' "$diagram_vault/svc.contract.yaml"
rc=0; "$render" "$diagram_vault/svc.contract.yaml" >/dev/null 2>&1 || rc=$?
assert "a render crash exits non-zero and keeps the old note" '[ "$rc" != "0" ] && [ "$(cat "$diagram_note")" = "$note_before" ]'
finish
