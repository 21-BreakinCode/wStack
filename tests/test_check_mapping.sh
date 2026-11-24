#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/handover/check-mapping.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
source "$(bash "$repo_root/tests/fixtures/contract/setup.sh" "$work_dir/world")"
export HOME="$work_dir/world"
init="$ORG_DIR/handover_handler__initiation.md"
ws="$work_dir/world/ws"

run() { set +e; out="$(bash "$script" "$@" 2>"$work_dir/err")"; rc=$?; set -e; err="$(cat "$work_dir/err")"; }
col() {  # <app_name> <column number>: 1 status, 2 app_name, 3 repo_path, 4 repo, 5 link, 6 ignore, 7 vault, 8 contract, 9 notes
  printf '%s\n' "$out" | awk -F'\t' -v app="$1" -v n="$2" '$2 == app { print $n }'
}
make_repo() { mkdir -p "$1"; git -C "$1" init -q; git -C "$1" commit -q --allow-empty -m init; }
snapshot() {  # every path, every file checksum, and every link target, outside git objects
  find "$work_dir/world" -path '*/.git/objects' -prune -o -print | LC_ALL=C sort
  find "$work_dir/world" -path '*/.git/objects' -prune -o -type f -exec cksum {} \; | LC_ALL=C sort
  find "$work_dir/world" -type l -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \; | LC_ALL=C sort
}

run "$VAULT" Acme
assert "a mapped repo with no link, no ignore rule, and no vault folder needs init" '[ $rc = 1 ] && [ "$(col svc 1)" = fix ] && [ "$(col svc 4)" = ok ] && [ "$(col svc 5)" = missing ] && [ "$(col svc 6)" = missing ] && [ "$(col svc 7)" = missing ]'
assert "the header names the columns" '[ "$(printf "%s\n" "$out" | head -1)" = "$(printf "status\tapp_name\trepo_path\trepo\tlink\tignore\tvault\tcontract\tnotes")" ]'
assert "a contract at the expected path is checked" '[ "$(col svc 8)" = fresh ]'

mkdir -p "$ORG_DIR/Services/svc/handover"
ln -s "$ORG_DIR/Services/svc/handover" "$REPO/handover"
echo /handover >> "$REPO/.git/info/exclude"
run "$VAULT" Acme
assert "a linked and ignored repo is ok, and every row ok exits 0" '[ $rc = 0 ] && [ "$(col svc 1)" = ok ] && [ "$(col svc 5)" = ok ] && [ "$(col svc 6)" = ok ] && [ "$(col svc 7)" = ok ] && [ -z "$(col svc 9)" ]'

echo "change" > "$REPO/api/new.go"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m change; git -C "$REPO" push -q origin main 2>/dev/null
run "$VAULT" Acme
assert "a stale contract reads stale and is not a failure" '[ $rc = 0 ] && [ "$(col svc 8)" = stale ]'

make_repo "$ws/sp repo"; echo handover > "$ws/sp repo/.gitignore"
mkdir -p "$ORG_DIR/Services/spaced/handover"
ln -s "$ORG_DIR/Services/spaced/handover/" "$ws/sp repo/handover"
make_repo "$ws/other repo"; echo /handover > "$ws/other repo/.gitignore"
mkdir -p "$ORG_DIR/Services/other/handover" "$ws/elsewhere"
ln -s "$ws/elsewhere" "$ws/other repo/handover"
make_repo "$ws/real dir"; mkdir -p "$ws/real dir/handover/notes"
mkdir -p "$ws/plain"
mkdir -p "$ORG_DIR/Services/realdir"
printf 'base_branch: main\n' > "$ORG_DIR/Services/realdir/realdir.contract.yaml"
make_repo "$ws/no vault"; echo /handover > "$ws/no vault/.gitignore"
ln -s "$ORG_DIR/Services/novault/handover" "$ws/no vault/handover"
mkdir -p "$ORG_DIR/Services/example-service"; touch "$ORG_DIR/Services/example-service/ExampleService.contract.yaml"
cat >> "$init" <<ROWS
| spaced | \$HOME/ws/sp repo | Services/spaced |
| other | $ws/other repo | Services/other |
| realdir | $ws/real dir | Services/realdir |
| gone | $ws/gone | Services/gone |
| ExampleService | $ws/plain | Services/example-service |
| novault | $ws/no vault | Services/novault |
| nosubpath | $ws/sp repo | |
ROWS
before="$(snapshot)"
run "$VAULT" Acme
assert "a \$HOME path, a link spelled with a trailing slash, and a gitignore rule are ok" '[ "$(col spaced 1)" = ok ] && [ "$(col spaced 3)" = "$ws/sp repo" ] && [ "$(col spaced 5)" = ok ] && [ "$(col spaced 6)" = ok ] && [ "$(col spaced 8)" = missing ]'
assert "a link to another folder needs init and names its target" '[ "$(col other 1)" = fix ] && [ "$(col other 5)" = "wrong: -> $ws/elsewhere" ]'
assert "a real handover folder is not a link" '[ "$(col realdir 1)" = fix ] && [ "$(col realdir 5)" = "not a link" ]'
assert "a contract that contract-check rejects reads error with its message" '[ "$(col realdir 8)" = "error: contract-check.sh: contract has no verified_commit: $ORG_DIR/Services/realdir/realdir.contract.yaml" ]'
assert "a correct link to a missing vault folder needs init for the vault folder only" '[ "$(col novault 1)" = fix ] && [ "$(col novault 5)" = ok ] && [ "$(col novault 6)" = ok ] && [ "$(col novault 7)" = missing ]'
assert "a row with no lifeos_subpath is broken" '[ "$(col nosubpath 1)" = broken ] && [ "$(col nosubpath 9)" = "row has no lifeos_subpath" ]'
assert "a missing repo path is broken and its checks are skipped" '[ "$(col gone 1)" = broken ] && [ "$(col gone 4)" = missing ] && [ "$(col gone 5)" = - ] && [ "$(col gone 6)" = - ]'
assert "a folder that is not a git work tree is broken, and its contract shows only present or missing" '[ "$(col ExampleService 1)" = broken ] && [ "$(col ExampleService 4)" = "not git" ] && [ "$(col ExampleService 8)" = present ] && [ "$(col gone 8)" = missing ]'
assert "an app_name that is not kebab-case gets a note" '[ "$(col ExampleService 9)" = "app_name is not kebab-case" ] && [ -z "$(col other 9)" ]'
assert "any row that is not ok exits 1, one line per row" '[ $rc = 1 ] && [ "$(printf "%s\n" "$out" | wc -l | tr -d " ")" = 9 ]'
assert "the check changes nothing" '[ "$(snapshot)" = "$before" ]'

run "$VAULT" NoSuchOrg
assert "a missing initiation file exits 2 and names the file" '[ $rc = 2 ] && printf "%s" "$err" | grep -qF "NoSuchOrg/handover_handler__initiation.md"'

finish
