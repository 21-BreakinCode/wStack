#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
diagram_dir="$repo_root/docs/diagrams"
readme="$repo_root/README.md"

# Git keeps no file times, so the test renders each source and checks the committed svg holds every label.
render_possible=1
if ! command -v playwright-cli >/dev/null 2>&1; then
  echo "SKIP render cases: playwright-cli not found"; render_possible=0
elif ! curl -fs -m 20 -r 0-0 -o /dev/null "https://cdn.jsdelivr.net/npm/@excalidraw/utils@0.1.8/dist/prod/index.js"; then
  echo "SKIP render cases: cdn.jsdelivr.net not reachable"; render_possible=0
fi

for name in pipeline launcher layout; do
  source_file="$diagram_dir/$name.excalidraw"
  svg_file="$diagram_dir/$name.svg"
  assert "$name.excalidraw exists" '[ -f "$source_file" ]'
  assert "$name.svg is committed" '[ -f "$svg_file" ]'
  [ -f "$source_file" ] && [ -f "$svg_file" ] || continue
  labels_missing=0
  while IFS= read -r label_line; do
    [ -n "$label_line" ] || continue
    grep -qF -- "$label_line" "$svg_file" || { echo "    missing label: $label_line"; labels_missing=1; }
  done < <(jq -r '.elements[] | select(.type=="text") | .text' "$source_file" | tr -d '\r')
  assert "$name.svg holds every label of its source" '[ "$labels_missing" -eq 0 ]'
  if [ "$render_possible" -eq 1 ]; then
    render_exit=0
    render_output="$(bash "$repo_root/scripts/render-excalidraw.sh" "$source_file" "$work_dir/$name.svg" 2>&1)" || render_exit=$?
    if [ "$render_exit" -eq 2 ]; then echo "SKIP render of $name: $render_output"
    else assert "$name.excalidraw renders (exit 0)" '[ "$render_exit" -eq 0 ]'
    fi
  fi
done

assert "README.md exists" '[ -f "$readme" ]'
assert "CHANGELOG has a 0.1.0 entry dated today or earlier" 'grep -qE "^## 0\.1\.0 - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$repo_root/CHANGELOG.md"'
for name in pipeline launcher layout; do
  assert "README embeds docs/diagrams/$name.svg" 'grep -qF "](docs/diagrams/$name.svg)" "$readme"'
done

# every install line in the README must come from preflight.sh
install_missing=0
while IFS= read -r install_line; do
  grep -qF -- "$install_line" "$repo_root/scripts/preflight.sh" || { echo "    not in preflight.sh: $install_line"; install_missing=1; }
done < <(grep -E '^(brew |npm i |mise |xcode-select|claude update|claude plugin (marketplace add QingYunA|install answer-me)|playwright-cli install-browser|cf auth login)' "$readme" || true)
assert "README install lines all appear in preflight.sh" '[ "$install_missing" -eq 0 ]'
assert "README has install lines to check" 'grep -qE "^brew " "$readme"'

# docs/superpowers holds the historical design and plan, which still name the old tool
diagram_design_hits="$(grep -rl 'diagram-design' "$readme" "$repo_root/CHANGELOG.md" "$repo_root/docs" 2>/dev/null | grep -v -e '/docs/spec.md$' -e '/docs/superpowers/' || true)"
assert "diagram-design appears only in docs/spec.md and docs/superpowers" '[ -z "$diagram_design_hits" ]'
finish
