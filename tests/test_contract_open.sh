#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-open.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
source "$(bash "$repo_root/tests/fixtures/contract/setup.sh" "$work_dir/world")"
page="$HOME/.wstack/pages/contracts/svc.html"
note="$(dirname "$CONTRACT")/svc.md"

out="$(cd "$REPO" && bash "$script" --vault "$VAULT" --print)"
assert "no argument finds the current repository and renders the missing page" '[ "$out" = "$page" ] && [ -f "$page" ]'

out="$(cd "$work_dir" && bash "$script" --vault "$VAULT" --print svc)"
assert "a service name finds its contract" '[ "$out" = "$page" ]'

out="$(cd "$work_dir" && bash "$script" --vault "$VAULT" --print --note svc)"
assert "--note gives the vault note" '[ "$out" = "$note" ] && [ -f "$note" ]'

echo stale >"$page"
touch -t 202001010000 "$page"
bash "$script" --vault "$VAULT" --print svc >/dev/null
assert "a page older than the contract is rendered again" '! grep -qx stale "$page"'

echo kept >"$page"
touch "$page"
bash "$script" --vault "$VAULT" --print svc >/dev/null
assert "a fresh page is not rendered again" 'grep -qx kept "$page"'

set +e; err="$(cd "$work_dir" && bash "$script" --vault "$VAULT" --print nosuch 2>&1 >/dev/null)"; rc=$?; set -e
assert "an unknown service exits 1 and lists the rendered pages ($err)" '[ $rc = 1 ] && printf "%s\n" "$err" | grep -qx "  svc"'

set +e; (cd "$work_dir" && bash "$script" --vault "$VAULT" --print) >/dev/null 2>&1; rc=$?; set -e
assert "an unmapped folder with no argument exits 1" '[ $rc = 1 ]'

set +e; bash "$script" --vault "$VAULT" --print "../x" >/dev/null 2>&1; rc=$?; set -e
assert "a bad service name exits 2" '[ $rc = 2 ]'
set +e; bash "$script" --print svc >/dev/null 2>&1; rc=$?; set -e
assert "a missing --vault exits 2" '[ $rc = 2 ]'
finish
