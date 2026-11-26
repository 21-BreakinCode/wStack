#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-ref-shift.sh"
work_dir="$(mktemp -d)"
export HOME="$work_dir/home"; mkdir -p "$HOME"
trap 'rm -rf "$work_dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

repo="$work_dir/repo"
git init -q -b main "$repo"
printf 'a\nb\nc\n' > "$repo/a.py"; printf 'x\ny\n' > "$repo/b.py"
git -C "$repo" add -A; git -C "$repo" commit -q -m A
commit_a="$(git -C "$repo" rev-parse HEAD)"
printf 'a2\nb\nc\n' > "$repo/a.py"
git -C "$repo" commit -q -am B
commit_b="$(git -C "$repo" rev-parse HEAD)"

contract="$work_dir/svc.contract.yaml"
cat > "$contract" <<YAML
verified_commit: "$commit_a"
sections:
  abilities:
    items:
      - text: One.
        refs: ["a.py:1", "b.py:2"]
      - text: Two.
        refs: ["other/repo@abc123:x.py:1"]
planned: []
diagrams:
  flow:
    edges:
      - from: a
        to: b
        refs: ["a.py:3"]
YAML

run() { set +e; out="$(bash "$script" "$@" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"; }

run "$repo" "$contract" "$commit_a" "$commit_b"
assert "exits 0" '[ $rc = 0 ]'
assert "changed refs listed" 'printf "%s\n" "$out" | grep -qxF "changed: a.py:1" && printf "%s\n" "$out" | grep -qxF "changed: a.py:3"'
assert "unchanged ref is not listed" '! printf "%s\n" "$out" | grep -qF "b.py:2"'
assert "cross-repo ref with no initiation file is unchecked" 'printf "%s\n" "$out" | grep -qxF "unchecked: other/repo@abc123:x.py:1: no local clone of other/repo"'
assert "count line" '[ "$(printf "%s\n" "$out" | tail -1)" = "refs: 2 changed, 0 shifted, 1 unchanged, 1 unchecked" ]'

printf 'v1\n' > "$repo/資料.py"; git -C "$repo" add -A; git -C "$repo" commit -q -m C
commit_c="$(git -C "$repo" rev-parse HEAD)"
printf 'v2\n' > "$repo/資料.py"; git -C "$repo" commit -q -am D
wide_contract="$work_dir/wide.contract.yaml"
printf 'sections:\n  abilities:\n    items:\n      - text: One.\n        refs: ["資料.py:1"]\n' > "$wide_contract"
run "$repo" "$wide_contract" "$commit_c" "$(git -C "$repo" rev-parse HEAD)"
assert "a non-ASCII file name matches its ref" 'printf "%s\n" "$out" | grep -qxF "changed: 資料.py:1"'

# Cross-repo refs: an org folder with an initiation file, and a clone of northwind/ledger under workspace_root whose HEAD moved.
org_dir="$work_dir/vault/Northwind"; ledger="$work_dir/ws/ledger"
mkdir -p "$org_dir/Services/svc" "$work_dir/ws"
printf -- '---\norg: Northwind\nworkspace_root: %s\n---\n\n## Service Mapping\n\n| app_name | repo_path | lifeos_subpath |\n| --- | --- | --- |\n| svc | %s | Services/svc |\n' \
  "$work_dir/ws" "$repo" > "$org_dir/handover_handler__initiation.md"
git init -q -b main "$ledger"
printf '1\n2\n3\n' > "$ledger/keep.py"; printf '1\n2\n3\n' > "$ledger/move.py"
git -C "$ledger" add -A; git -C "$ledger" commit -q -m L1
git -C "$ledger" remote add origin git@github.com:northwind/ledger.git
ledger_old="$(git -C "$ledger" rev-parse HEAD)"
printf '1\n2b\n3\n' > "$ledger/move.py"; git -C "$ledger" commit -q -am L2
ledger_head="$(git -C "$ledger" rev-parse HEAD)"
cross_contract="$org_dir/Services/svc/svc.contract.yaml"
cat > "$cross_contract" <<YAML
sections:
  abilities:
    items:
      - text: One.
        refs: ["northwind/ledger@$ledger_old:keep.py:1", "northwind/ledger@${ledger_old:0:7}:keep.py:3"]
      - text: Two.
        refs: ["northwind/ledger@$ledger_old:move.py:2", "northwind/ledger@${ledger_head:0:7}:keep.py:2"]
      - text: Three.
        refs: ["northwind/ledger@deadbeef:keep.py:1", "northwind/gone@abc123:x.py:1", "b.py:2"]
YAML
run "$repo" "$cross_contract" "$commit_a" "$commit_b"
assert "cross-repo run exits 0 ($err)" '[ $rc = 0 ]'
assert "cross-repo file that did not change shifts to the clone HEAD" 'printf "%s\n" "$out" | grep -qxF "shift: northwind/ledger@$ledger_old:keep.py:1 -> northwind/ledger@$ledger_head:keep.py:1"'
assert "a short commit shifts to the full HEAD sha" 'printf "%s\n" "$out" | grep -qxF "shift: northwind/ledger@${ledger_old:0:7}:keep.py:3 -> northwind/ledger@$ledger_head:keep.py:3"'
assert "cross-repo file that changed is changed" 'printf "%s\n" "$out" | grep -qxF "changed: northwind/ledger@$ledger_old:move.py:2"'
assert "cross-repo ref at the clone HEAD is not listed" '! printf "%s\n" "$out" | grep -qF "${ledger_head:0:7}:keep.py:2"'
assert "unknown commit in the clone is unchecked" 'printf "%s\n" "$out" | grep -qxF "unchecked: northwind/ledger@deadbeef:keep.py:1: unknown commit"'
assert "repo with no clone is unchecked" 'printf "%s\n" "$out" | grep -qxF "unchecked: northwind/gone@abc123:x.py:1: no local clone of northwind/gone"'
assert "cross-repo count line ($out)" '[ "$(printf "%s\n" "$out" | tail -1)" = "refs: 1 changed, 2 shifted, 2 unchanged, 2 unchecked" ]'

draft="$work_dir/task/contract.draft.yaml"
mkdir -p "$(dirname "$draft")"; cp "$cross_contract" "$draft"
run "$repo" "$draft" "$commit_a" "$commit_b"
assert "a draft outside the org folder finds no clone" 'printf "%s\n" "$out" | grep -qxF "unchecked: northwind/ledger@$ledger_old:keep.py:1: no local clone of northwind/ledger"'
run "$repo" "$draft" "$commit_a" "$commit_b" --mapping-from "$org_dir/Services/new-svc/new-svc.contract.yaml"
assert "--mapping-from finds the clone for a draft" '[ $rc = 0 ] && [ "$(printf "%s\n" "$out" | tail -1)" = "refs: 1 changed, 2 shifted, 2 unchanged, 2 unchecked" ]'
run "$repo" "$draft" "$commit_a" "$commit_b" --mapping-from
assert "--mapping-from with no path exits 2" '[ $rc = 2 ] && [[ "$err" == contract-ref-shift:* ]]'

# A real clone of northwind/wharf: a fetch moves its origin/HEAD, and its HEAD stays.
wharf_seed="$work_dir/wharf-seed"; wharf_origin="$work_dir/wharf.git"; wharf="$work_dir/ws/wharf"
git init -q --bare -b main "$wharf_origin"
git init -q -b main "$wharf_seed"
printf '1\n2\n' > "$wharf_seed/dock.py"; printf '1\n2\n' > "$wharf_seed/crane.py"
git -C "$wharf_seed" add -A; git -C "$wharf_seed" commit -q -m W1; git -C "$wharf_seed" push -q "$wharf_origin" main
wharf_old="$(git -C "$wharf_seed" rev-parse HEAD)"
git clone -q "$wharf_origin" "$wharf"
printf '1\n2b\n' > "$wharf_seed/crane.py"; git -C "$wharf_seed" commit -q -am W2; git -C "$wharf_seed" push -q "$wharf_origin" main
wharf_new="$(git -C "$wharf_seed" rev-parse HEAD)"
git -C "$wharf" fetch -q origin main
wharf_contract="$org_dir/Services/svc/wharf.contract.yaml"
printf 'sections:\n  abilities:\n    items:\n      - text: One.\n        refs: ["northwind/wharf@%s:dock.py:1", "northwind/wharf@%s:crane.py:2"]\n' \
  "$wharf_old" "$wharf_old" > "$wharf_contract"
run "$repo" "$wharf_contract" "$commit_a" "$commit_b"
assert "the wharf clone's HEAD did not move" '[ "$(git -C "$wharf" rev-parse HEAD)" = "$wharf_old" ]'
assert "a cross-repo ref shifts to the clone's origin/HEAD ($out)" 'printf "%s\n" "$out" | grep -qxF "shift: northwind/wharf@$wharf_old:dock.py:1 -> northwind/wharf@$wharf_new:dock.py:1"'
assert "a file that changed up to origin/HEAD is changed" 'printf "%s\n" "$out" | grep -qxF "changed: northwind/wharf@$wharf_old:crane.py:2"'
assert "origin/HEAD count line" '[ "$(printf "%s\n" "$out" | tail -1)" = "refs: 1 changed, 1 shifted, 0 unchanged, 0 unchecked" ]'

run "$repo" "$contract" "$commit_a" deadbeef
assert "bad commit exits 2" '[ $rc = 2 ] && [[ "$err" == contract-ref-shift:* ]]'
run "$repo" "$contract" "$commit_a"
assert "missing argument exits 2" '[ $rc = 2 ] && [[ "$err" == contract-ref-shift:* ]]'
run "$repo" "$work_dir/none.yaml" "$commit_a" "$commit_b"
assert "missing contract exits 2" '[ $rc = 2 ] && [[ "$err" == contract-ref-shift:* ]]'

finish
