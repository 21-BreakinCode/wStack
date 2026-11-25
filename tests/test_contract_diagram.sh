#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-diagram.sh"
py=python3; [ ! -x /usr/bin/python3 ] || py=/usr/bin/python3
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
source "$(bash "$repo_root/tests/fixtures/contract/setup.sh" "$work_dir/world")"
cd "$repo_root"
yq -i '. *= load("tests/fixtures/contract/diagrams-block.yaml")' "$CONTRACT"
folder="$(dirname "$CONTRACT")"
flow_html="$folder/diagrams/flow.html"
drawn="$work_dir/drawn.html"
printf '<!doctype html>\n<html><head><title>x</title></head><body>FIRST</body></html>\n' >"$drawn"
flow_hash="$(yq -o=json . "$CONTRACT" | "$py" scripts/contract_diagrams.py hash flow)"
backups="$work_dir/backups"; record="$work_dir/record.list"

out="$(bash "$script" subject "$CONTRACT" flow)"
assert "subject prints the hash first" '[ "$(printf "%s\n" "$out" | head -n 1)" = "hash: $flow_hash" ]'
assert "subject prints the JSON" 'printf "%s\n" "$out" | tail -n +2 | "$py" -c "import json,sys; json.load(sys.stdin)"'

set +e; err="$(bash "$script" subject "$CONTRACT" nosuch 2>&1 >/dev/null)"; rc=$?; set -e
assert "an unknown subject exits 1 and lists the subjects" '[ $rc = 1 ] && printf "%s\n" "$err" | grep -qx "subjects: flow, sequence:create, states:item-status, architecture"'

out="$(bash "$script" install "$CONTRACT" flow "$drawn")"
assert "install prints the path" '[ "$out" = "installed: $flow_html" ]'
assert "install puts three meta tags right after head" 'grep -q "<head><meta name=\"wstack-subject\" content=\"flow\"><meta name=\"wstack-subject-hash\" content=\"$flow_hash\"><meta name=\"wstack-drawn-at\" content=\"$FIRST_COMMIT\"><title>" "$flow_html"'

printf '<html><head lang="en"><meta name="wstack-subject" content="old"><meta name="wstack-drawn-at" content="old"><meta charset="utf-8"></head></html>\n' >"$work_dir/tagged.html"
bash "$script" install "$CONTRACT" flow "$work_dir/tagged.html" >/dev/null
assert "install replaces old wstack tags, keeps other tags" '[ "$(grep -o "wstack-subject\"" "$flow_html" | wc -l)" -eq 1 ] && ! grep -q "content=\"old\"" "$flow_html" && grep -q "charset" "$flow_html"'

printf 'no markup\n' >"$work_dir/nohead.html"
set +e; bash "$script" install "$CONTRACT" flow "$work_dir/nohead.html" >/dev/null 2>&1; rc=$?; set -e
assert "install refuses a file with no head" '[ $rc = 2 ]'

set +e; bash "$script" install "$CONTRACT" flow "$drawn" --backup-dir "$backups" >/dev/null 2>&1; rc=$?; set -e
assert "--backup-dir without --record exits 2" '[ $rc = 2 ]'

bash "$script" install "$CONTRACT" flow "$work_dir/tagged.html" --backup-dir "$backups" --record "$record" >/dev/null
sed 's/FIRST/SECOND/' "$drawn" >"$work_dir/second.html"
out="$(bash "$script" install "$CONTRACT" flow "$work_dir/second.html" --backup-dir "$backups" --record "$record")"
assert "a second install prints no new backup" '! printf "%s\n" "$out" | grep -q "^backup:"'
assert "a second install keeps the first backup" 'grep -q "charset" "$backups/flow.html"'
assert "the record has one line for the path" '[ "$(wc -l <"$record" | tr -d " ")" = 1 ]'

assert "stale is empty when fresh" '[ -z "$(bash "$script" stale "$CONTRACT")" ]'
yq -i '.diagrams.flow.parts[0].refs = ["cmd/main.go:2"]' "$CONTRACT"
assert "stale ignores a refs-only change" '[ -z "$(bash "$script" stale "$CONTRACT")" ]'
yq -i '.diagrams.flow.parts[0].label = "API v2"' "$CONTRACT"
assert "stale lists a changed label" '[ "$(bash "$script" stale "$CONTRACT")" = "stale: flow $flow_html" ]'

bash "$script" install "$CONTRACT" architecture "$drawn" --backup-dir "$backups" --record "$record" >/dev/null
set +e; bash "$script" restore "$work_dir/nosuch.list"; rc=$?; set -e
assert "a missing list file exits 0" '[ $rc = 0 ]'
mv "$backups/flow.html" "$work_dir/flow.backup"
set +e; bash "$script" restore "$record" >/dev/null 2>&1; rc=$?; set -e
assert "restore with a missing backup exits 1 and changes nothing" '[ $rc = 1 ] && grep -q SECOND "$flow_html" && [ -f "$folder/diagrams/architecture.html" ] && [ -f "$record" ]'
mv "$work_dir/flow.backup" "$backups/flow.html"
out="$(bash "$script" restore "$record")"
assert "restore puts back the backup" '! grep -q SECOND "$flow_html" && grep -q charset "$flow_html" && printf "%s\n" "$out" | grep -qx "restored: $flow_html"'
assert "restore removes a new deep dive" '[ ! -e "$folder/diagrams/architecture.html" ] && printf "%s\n" "$out" | grep -qx "removed: $folder/diagrams/architecture.html"'
assert "restore moves the backup, so it is gone" '[ ! -e "$backups/flow.html" ]'
assert "restore removes the used list" '[ ! -e "$record" ]'

rm "$flow_html"
bash "$script" install "$CONTRACT" flow "$drawn" --record "$record" >/dev/null
bash "$script" restore "$record" >/dev/null
assert "restore removes the empty diagrams folder" '[ ! -d "$folder/diagrams" ]'

mkdir "$CONTRACT.lock"
set +e; bash "$script" install "$CONTRACT" flow "$drawn" >/dev/null 2>&1; rc=$?; set -e
rmdir "$CONTRACT.lock"
assert "a busy lock exits 4" '[ $rc = 4 ]'
finish
