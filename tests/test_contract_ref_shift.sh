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
assert "cross-repo ref is unchecked" 'printf "%s\n" "$out" | grep -qxF "unchecked: other/repo@abc123:x.py:1: cross-repo"'
assert "count line" '[ "$(printf "%s\n" "$out" | tail -1)" = "refs: 2 changed, 1 unchanged, 1 unchecked" ]'

printf 'v1\n' > "$repo/資料.py"; git -C "$repo" add -A; git -C "$repo" commit -q -m C
commit_c="$(git -C "$repo" rev-parse HEAD)"
printf 'v2\n' > "$repo/資料.py"; git -C "$repo" commit -q -am D
wide_contract="$work_dir/wide.contract.yaml"
printf 'sections:\n  abilities:\n    items:\n      - text: One.\n        refs: ["資料.py:1"]\n' > "$wide_contract"
run "$repo" "$wide_contract" "$commit_c" "$(git -C "$repo" rev-parse HEAD)"
assert "a non-ASCII file name matches its ref" 'printf "%s\n" "$out" | grep -qxF "changed: 資料.py:1"'

run "$repo" "$contract" "$commit_a" deadbeef
assert "bad commit exits 2" '[ $rc = 2 ] && [[ "$err" == contract-ref-shift:* ]]'
run "$repo" "$contract" "$commit_a"
assert "missing argument exits 2" '[ $rc = 2 ] && [[ "$err" == contract-ref-shift:* ]]'
run "$repo" "$work_dir/none.yaml" "$commit_a" "$commit_b"
assert "missing contract exits 2" '[ $rc = 2 ] && [[ "$err" == contract-ref-shift:* ]]'

finish
