#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-check.sh"
setup="$repo_root/tests/fixtures/contract/setup.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
case_count=0
new_world() {
  case_count=$((case_count + 1))
  source "$(bash "$setup" "$work_dir/case $case_count")"
}
push_file() {  # <relative path>
  mkdir -p "$(dirname "$REPO/$1")"
  echo "change $RANDOM" > "$REPO/$1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "change $1"
  git -C "$REPO" push -q origin main 2>/dev/null
}
run() { set +e; out="$(bash "$script" "$REPO" "$CONTRACT" "$@" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"; }
field() { printf '%s\n' "$out" | sed -n "s/^$1: //p"; }
set_key() {  # <file> <key> <value>
  sed -i.bak "s|^$2: .*|$2: $3|" "$1"
}
add_dependency() {  # <mapped_commit>
  yq -i ".sections.depends_on.items = [{\"text\": \"Calls dep.\", \"refs\": [\"cmd/main.go:1\"], \"app\": \"dep\", \"mapped_commit\": \"$1\"}]" "$CONTRACT"
}
map_dependency() {
  dep_dir="$ORG_DIR/Services/dep"; mkdir -p "$dep_dir"
  echo "| dep | $(dirname "$REPO")/dep | Services/dep |" >> "$ORG_DIR/handover_handler__initiation.md"
}

new_world; run
assert "fresh" '[ $rc = 0 ] && [ "$(field status)" = fresh ] && [ "$(field behind)" = 0 ] && [ "$(field base)" = origin/main ]'
assert "line order" '[ "$(printf "%s\n" "$out" | cut -d: -f1 | paste -sd, -)" = "status,base,behind,stale_sections,stale_dependencies,unclaimed_files,unclaimed_count,pending" ]'

new_world; push_file api/new.go; run
assert "section stale" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"interfaces\"]" ] && [ "$(field behind)" = 1 ] && [ "$(field status)" = stale ]'

new_world; push_file docs/PRD.md; run
assert "team doc stale" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"team_docs\"]" ] && [ "$(field unclaimed_count)" = 0 ]'

new_world; push_file README.md; run
assert "unclaimed" '[ $rc = 1 ] && [ "$(field unclaimed_files)" = "[\"README.md\"]" ] && [ "$(field unclaimed_count)" = 1 ] && [ "$(field stale_sections)" = "[]" ]'

new_world; push_file tests/b_test.go; run
assert "ignored" '[ $rc = 0 ] && [ "$(field unclaimed_count)" = 0 ]'

new_world; push_file "api/my file.go"; run
assert "space in a name" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"interfaces\"]" ]'

new_world
git -C "$REPO" checkout -q -b feature
echo x > "$REPO/api/x.go"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m x
run
assert "feature branch" '[ $rc = 0 ]'

new_world; set_key "$CONTRACT" verified_commit 0123456789abcdef0123456789abcdef01234567; run
assert "unknown commit" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"team_docs\",\"abilities\",\"interfaces\"]" ]'

new_world; set_key "$CONTRACT" pending '[{"pr":12,"task":"t1"}]'; run
assert "pending listed" '[ $rc = 0 ] && [ "$(field pending)" = "[{\"pr\":12,\"task\":\"t1\"}]" ]'

new_world; map_dependency
printf 'app_name: dep\nverified_commit: "aaa1111"\n' > "$dep_dir/dep.contract.yaml"
add_dependency aaa1111
run
assert "dependency equal" '[ $rc = 0 ] && [ "$(field stale_dependencies)" = "[]" ]'
set_key "$dep_dir/dep.contract.yaml" verified_commit '"bbb2222"'; run
assert "dependency changed" '[ $rc = 1 ] && [ "$(field stale_dependencies)" = "[\"dep\"]" ] && [ "$(field stale_sections)" = "[\"depends_on\"]" ]'

new_world; map_dependency
printf -- '---\napp_name: dep\nverified_commit: aaa1111\n---\n' > "$dep_dir/dep.md"
add_dependency aaa1111; run
assert "dependency on an old .md contract reads its frontmatter" '[ $rc = 0 ] && [ "$(field stale_dependencies)" = "[]" ]'
set_key "$dep_dir/dep.md" verified_commit bbb2222; run
assert "dependency on an old .md contract that changed is stale" '[ $rc = 1 ] && [ "$(field stale_dependencies)" = "[\"dep\"]" ]'

new_world; map_dependency; add_dependency aaa1111; run
assert "dependency with no contract is not stale" '[ $rc = 0 ] && [ "$(field stale_dependencies)" = "[]" ] && [ "$(field stale_sections)" = "[]" ]'

new_world; add_dependency aaa1111; run
assert "dependency that is not in the mapping is not stale" '[ $rc = 0 ] && [ "$(field stale_dependencies)" = "[]" ]'

new_world; rm "$CONTRACT"; run
assert "missing contract" '[ $rc = 3 ]'

new_world; sed -i.bak '/^verified_commit:/d' "$CONTRACT"; run
assert "missing verified_commit" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "contract has no verified_commit"'

new_world; set_key "$CONTRACT" verified_commit 1234567; run
assert "unquoted number verified_commit is an error" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "verified_commit must be a quoted string"'

new_world; set_key "$CONTRACT" base_branch release; run
assert "missing base ref" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "origin/release"'

new_world
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "$i" > "$REPO/n$i.txt"; done
git -C "$REPO" add -A; git -C "$REPO" commit -q -m many; git -C "$REPO" push -q origin main 2>/dev/null; run
assert "unclaimed capped at 10" '[ "$(field unclaimed_count)" = 12 ] && [ "$(field unclaimed_files | jq length)" = 10 ]'

new_world
mkdir -p "$REPO/api/v1" "$REPO/cmd/tool" "$REPO/tests/many" "$REPO/misc"
for i in $(seq 1 125); do
  echo "$i" > "$REPO/api/v1/f$i.go"; echo "$i" > "$REPO/cmd/tool/f$i.go"
  echo "$i" > "$REPO/tests/many/f$i.go"; echo "$i" > "$REPO/misc/f$i.txt"
done
git -C "$REPO" add -A; git -C "$REPO" commit -q -m bulk; git -C "$REPO" push -q origin main 2>/dev/null
started=$SECONDS; run; elapsed=$((SECONDS - started))
echo "  (500 files took ${elapsed}s)"
assert "500 changed files" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"interfaces\",\"abilities\"]" ] && [ "$(field unclaimed_count)" = 125 ] && [ "$elapsed" -lt 10 ]'

# A1-1: two globs in one section both claim files
new_world
yq -i '.sections.interfaces.sources = ["api/**", "lib/**"]' "$CONTRACT"
push_file lib/a.go; run
assert "two globs in one section: second glob claims" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"interfaces\"]" ] && [ "$(field unclaimed_count)" = 0 ]'

# A1-2: CRLF contract
new_world
sed -i.bak 's/$/\r/' "$CONTRACT"; push_file api/new.go; run
assert "CRLF contract reads" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"interfaces\"]" ]'

# A1-3: broken YAML, missing jq, and missing yq each have their own error
new_world; set_key "$CONTRACT" ignore '[broken'; run
assert "broken YAML exits 2" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "contract is not valid YAML"'
new_world; no_jq="$work_dir/nojq"; mkdir -p "$no_jq"; ln -sf "$(command -v git)" "$no_jq/git"; ln -sf "$(command -v bash)" "$no_jq/bash"; ln -sf "$(command -v dirname)" "$no_jq/dirname"
set +e; out="$(PATH="$no_jq" "$(command -v bash)" "$script" "$REPO" "$CONTRACT" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"
assert "missing jq is named" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "jq is required"'
ln -sf "$(command -v jq)" "$no_jq/jq"
set +e; out="$(PATH="$no_jq" "$(command -v bash)" "$script" "$REPO" "$CONTRACT" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"
assert "missing yq is named" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "yq is required"'

new_world; set_key "$CONTRACT" ignore '{"a":1}'; run
assert "ignore object is an error" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "ignore is not a list of strings"'
new_world; set_key "$CONTRACT" ignore '[1,2]'; run
assert "ignore numbers are an error" '[ $rc = 2 ]'
new_world; set_key "$CONTRACT" pending '{"pr":12}'; run
assert "pending that is not a list is an error" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "pending is not a list"'
new_world; yq -i '.sections.interfaces.sources = "api/**"' "$CONTRACT"; run
assert "sources that is not a list is an error" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "sources is not a list of strings"'

# A1-4: verified_commit must be a hex SHA
new_world; set_key "$CONTRACT" verified_commit '--all'; run
assert "option-like verified_commit rejected" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "not a hex SHA"'

# A1-5: a parse-mapping failure names its cause
new_world; add_dependency aaa1111
printf '#!/usr/bin/env bash\necho "boom" >&2; exit 7\n' > "$work_dir/fake-parse.sh"
broken_plugin="$work_dir/broken-plugin"; mkdir -p "$broken_plugin/scripts/handover"
cp -R "$repo_root/scripts/lib" "$broken_plugin/scripts/lib"; cp "$script" "$broken_plugin/scripts/contract-check.sh"
cp "$work_dir/fake-parse.sh" "$broken_plugin/scripts/handover/parse-mapping.sh"
set +e; out="$(bash "$broken_plugin/scripts/contract-check.sh" "$REPO" "$CONTRACT" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"
assert "parse-mapping failure is reported" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "cannot read the service mapping"'

# A1-6: an empty sources list claims nothing
new_world; yq -i '.sections.abilities.sources = []' "$CONTRACT"
set_key "$CONTRACT" verified_commit 0123456789abcdef0123456789abcdef01234567; run
assert "empty sources list: section not stale" '[ $rc = 1 ] && [ "$(field stale_sections)" = "[\"team_docs\",\"interfaces\"]" ]'

# Block-style YAML lists are read like flow lists
new_world; sed -i.bak 's|^ignore: .*|ignore:\n  - tests/**\n  - evals/**|' "$CONTRACT"; push_file tests/b_test.go; run
assert "block-style ignore is read" '[ $rc = 0 ] && [ "$(field unclaimed_count)" = 0 ]'

new_world; sed -i.bak 's|^pending: .*|pending:\n  - pr: 12|' "$CONTRACT"; run
assert "block-style pending is read" '[ $rc = 0 ] && [ "$(field pending)" = "[{\"pr\":12}]" ]'

new_world; set_key "$CONTRACT" ignore '["tests/**", "evals/**"]'; run
assert "one-line ignore still works" '[ $rc = 0 ]'

new_world; sed -i.bak '/^ignore: /d' "$CONTRACT"; run
assert "missing ignore still works" '[ $rc = 0 ]'

set +e; bash "$script" >/dev/null 2>"$work_dir/err"; no_arg_rc=$?; bash "$script" "$REPO" >/dev/null 2>>"$work_dir/err"; one_arg_rc=$?; set -e
assert "missing arguments exit 2 with a usage line" '[ $no_arg_rc = 2 ] && [ $one_arg_rc = 2 ] && grep -q "usage: contract-check.sh" "$work_dir/err"'

new_world; sed -i.bak 's|^ignore: .*|ignore:\n- tests/**|' "$CONTRACT"; push_file tests/b_test.go; run
assert "block-style ignore with no indent is read" '[ $rc = 0 ] && [ "$(field unclaimed_count)" = 0 ]'

new_world; sed -i.bak 's|^pending: .*|pending:   \n  - pr: 12|' "$CONTRACT"; run
assert "block-style pending after trailing spaces is read" '[ $rc = 0 ] && [ "$(field pending)" = "[{\"pr\":12}]" ]'

new_world; sed -i.bak 's|^pending: .*|pending:\n\n  - x|' "$CONTRACT"; run
assert "block-style pending after a blank line is read" '[ $rc = 0 ] && [ "$(field pending)" = "[\"x\"]" ]'

new_world; sed -i.bak 's|^pending: .*|pending:\n  # note\n  - x|' "$CONTRACT"; run
assert "block-style pending after a comment line is read" '[ $rc = 0 ] && [ "$(field pending)" = "[\"x\"]" ]'

set +e; bash "$script" "" "$CONTRACT" >/dev/null 2>&1; empty_repo_rc=$?; bash "$script" "$REPO" "" >/dev/null 2>&1; empty_contract_rc=$?; set -e
assert "an empty argument exits 2" '[ $empty_repo_rc = 2 ] && [ $empty_contract_rc = 2 ]'

# --coverage: every tracked file counts as changed; claimed files do not mark sections stale
new_world; set_key "$CONTRACT" ignore '[]'; push_file README.md; run --coverage
assert "--coverage counts every tracked file" '[ $rc = 1 ] && [ "$(field unclaimed_count)" = 2 ] && [ "$(field unclaimed_files)" = "[\"README.md\",\"tests/a_test.go\"]" ] && [ "$(field stale_sections)" = "[]" ]'
new_world; run --coverage
assert "--coverage with every file claimed or ignored exits 0" '[ $rc = 0 ] && [ "$(field status)" = fresh ] && [ "$(field unclaimed_count)" = 0 ]'
new_world; run --other
assert "a third argument other than --coverage exits 2" '[ $rc = 2 ] && grep -q "usage: contract-check.sh" "$work_dir/err"'

finish
