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
      - text: A folder is read-only when a bucket is set.
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
    why: A failed commit loses the message.
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

assert "html escapes text" 'grep -qF "&lt;script&gt;" "$page" && ! grep -q "<script" "$page"'
assert "html has the summary card counts" 'grep -q "5 gotchas" "$page" && grep -q "1 planned" "$page" && grep -q "main" "$page"'
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
finish
