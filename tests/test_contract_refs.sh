#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-refs.sh"
setup="$repo_root/tests/fixtures/contract/setup.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
case_count=0
new_world() {
  case_count=$((case_count + 1))
  source "$(bash "$setup" "$work_dir/case $case_count")"
  printf 'one\ntwo\nthree\nfour\nlast-no-newline' > "$REPO/cmd/main.go"   # 5 lines, no trailing newline
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "five lines"
  FIRST_COMMIT="$(git -C "$REPO" rev-parse HEAD)"
  sed -i.bak "s|^verified_commit: .*|verified_commit: \"$FIRST_COMMIT\"|" "$CONTRACT"
}
run() { set +e; out="$(bash "$script" "$REPO" "$CONTRACT" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"; }
set_refs() {  # <ref>... goes into abilities
  local refs_json; refs_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
  yq -i ".sections.abilities.items = [{\"text\": \"Claim.\", \"refs\": $refs_json}]" "$CONTRACT"
}
add_other_clone() {  # makes workspace_root/other with remote git@github.com:acme-org/other.git, one 3-line file
  other="$(dirname "$REPO")/other"
  git init -q -b main "$other"
  printf 'a\nb\nc\n' > "$other/x.txt"
  git -C "$other" add -A; git -C "$other" commit -q -m x
  git -C "$other" remote add origin git@github.com:acme-org/other.git
  other_commit="$(git -C "$other" rev-parse HEAD)"
}

new_world; set_refs "cmd/main.go:1-5" "api/routes.go:1"; run
assert "all refs hold exits 0" '[ $rc = 0 ] && [ "$out" = "refs: 2 checked, 0 bad, 0 unchecked" ]'

new_world; set_refs "cmd/gone.go:1"; run
assert "missing file is bad" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -q "^bad: cmd/gone.go:1: " && printf "%s\n" "$out" | grep -q "1 bad"'

new_world; set_refs "cmd/main.go:6"; run
assert "line past the end is bad" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -q "^bad: cmd/main.go:6: "'

new_world; set_refs "cmd/main.go:3-9"; run
assert "N-M with M past the end is bad" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -q "^bad: cmd/main.go:3-9: "'

new_world; set_refs "cmd/main.go:1, 2-3,5"; run
assert "comma list with spaces holds" '[ $rc = 0 ]'
new_world; set_refs "cmd/main.go:1, 2, 99"; run
assert "comma list checks every number" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -q "^bad: cmd/main.go:1, 2, 99: "'

new_world; set_refs "cmd/main.go" "cmd/main.go:x"; run
assert "bad form" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -q "^bad: cmd/main.go: bad form" && printf "%s\n" "$out" | grep -q "^bad: cmd/main.go:x: bad form"'

new_world; set_refs "acme-org/nowhere@abc1234:x.txt:1"; run
assert "cross-repo ref with no local clone is unchecked and exits 0" '[ $rc = 0 ] && printf "%s\n" "$out" | grep -q "^unchecked: acme-org/nowhere@abc1234:x.txt:1: " && printf "%s\n" "$out" | grep -q "0 checked, 0 bad, 1 unchecked"'

new_world; add_other_clone; set_refs "acme-org/other@deadbeef:x.txt:1"; run
assert "cross-repo ref with an unknown commit is unchecked" '[ $rc = 0 ] && printf "%s\n" "$out" | grep -q "^unchecked: acme-org/other@deadbeef:x.txt:1: "'

new_world; add_other_clone; set_refs "acme-org/other@$other_commit:x.txt:1-3"; run
assert "cross-repo ref that holds is counted as checked" '[ $rc = 0 ] && [ "$out" = "refs: 1 checked, 0 bad, 0 unchecked" ]'
new_world; add_other_clone; set_refs "acme-org/other@$other_commit:x.txt:4"; run
assert "cross-repo ref past the end is bad" '[ $rc = 1 ]'

new_world; yq -i '.planned = [{"text": "Later.", "refs": ["cmd/gone.go:1"]}]' "$CONTRACT"; run
assert "planned refs are checked" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -q "^bad: cmd/gone.go:1: "'

new_world; yq -i '.verified_commit = ""' "$CONTRACT"; run
assert "empty verified_commit exits 2" '[ $rc = 2 ] && [ -n "$err" ]'

new_world; add_other_clone
sed -i.bak "s|^workspace_root: .*|workspace_root: \$HOME/ws|" "$ORG_DIR/handover_handler__initiation.md"
set_refs "acme-org/other@$other_commit:x.txt:1"
set +e; out="$(HOME="$(dirname "$REPO")/.." bash "$script" "$REPO" "$CONTRACT" 2>&1)"; rc=$?; set -e
assert "workspace_root with \$HOME is expanded" '[ $rc = 0 ] && [ "$out" = "refs: 1 checked, 0 bad, 0 unchecked" ]'

new_world; add_other_clone
mv "$other" "$(dirname "$REPO")/renamed-folder"
echo "| other | $(dirname "$REPO")/renamed-folder | Services/other |" >> "$ORG_DIR/handover_handler__initiation.md"
set_refs "acme-org/other@$other_commit:x.txt:1"; run
assert "Service Mapping remote match finds a clone with another folder name" '[ $rc = 0 ] && [ "$out" = "refs: 1 checked, 0 bad, 0 unchecked" ]'

new_world; add_other_clone
git -C "$other" remote set-url origin git@github.com:xacme-org/other.git
mv "$other" "$(dirname "$REPO")/longer-name"
echo "| other | $(dirname "$REPO")/longer-name | Services/other |" >> "$ORG_DIR/handover_handler__initiation.md"
set_refs "acme-org/other@$other_commit:x.txt:1"; run
assert "a remote of xacme-org/other is not a clone of acme-org/other ($out)" '[ $rc = 0 ] && printf "%s\n" "$out" | grep -q "^unchecked: acme-org/other@" && printf "%s\n" "$out" | grep -q "0 checked, 0 bad, 1 unchecked"'

new_world; yq -i '. *= load("'"$repo_root/tests/fixtures/contract/diagrams-block.yaml"'")' "$CONTRACT"
yq -i '.diagrams.flow.edges[0].refs = ["nofile.go:1"]' "$CONTRACT"; run
assert "diagram refs are checked" '[ $rc = 1 ] && printf "%s\n" "$out" | grep -qx "bad: nofile.go:1: no file nofile.go at $FIRST_COMMIT" && printf "%s\n" "$out" | grep -q "^refs: 16 checked, 1 bad"'

finish
