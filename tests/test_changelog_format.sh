#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
changelog="$repo_root/CHANGELOG.md"

bad_headings="$(grep '^## ' "$changelog" | grep -Ev '^## [0-9]+\.[0-9]+\.[0-9]+ - [0-9]{4}-[0-9]{2}-[0-9]{2}$' || true)"
assert "every version heading reads '## <x.y.z> - <date>'" '[ -z "$bad_headings" ]'

bad_bullets="$(awk '/^## /{in_versions=1} in_versions && /^- /' "$changelog" | grep -Ev '^- \*\*(feat|fix|docs|change|breaking):\*\* ' || true)"
[ -z "$bad_bullets" ] || printf '    untyped bullet: %s\n' "$bad_bullets"
assert "every bullet reads '- **<type>:** <text>'" '[ -z "$bad_bullets" ]'

empty_versions="$(awk '/^## /{if(v!=""&&n==0)print v; v=$2; n=0} /^- \*\*(feat|fix|docs|change|breaking):\*\* /{n++} END{if(v!=""&&n==0)print v}' "$changelog")"
assert "every version has at least one typed bullet" '[ -z "$empty_versions" ]'
finish
