#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/_assert.sh"
edit="$here/../scripts/contract-edit.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home"
mkdir -p "$HOME"
source "$(bash "$here/fixtures/contract/setup.sh" "$work/world")"
contract_dir="$(dirname "$CONTRACT")"
note="$contract_dir/svc.md"

base="$work/base.contract.yaml"
cp "$CONTRACT" "$base"
yq -i '
  .sections.abilities.items = [{"text": "Old ability.", "refs": ["cmd/main.go:1"]}] |
  .sections.interfaces.items = [{"text": "Old interface.", "refs": ["api/routes.go:1"]}] |
  .sections.gotchas.items = [{"text": "Old gotcha.", "refs": ["cmd/main.go:1"], "planned": "video-ack-after-commit"}] |
  .planned = [
    {"id": "video-ack-after-commit", "title": "Ack after commit", "why": "A failed commit loses the message."},
    {"id": "docs-refresh", "title": "Refresh the docs", "why": "The docs are old."}
  ]' "$base"
reset_contract() { cp "$base" "$CONTRACT"; rm -f "$note"; }
json_of() { yq -o=json '.' "$1" | jq -S .; }
query() { yq -o=json "$2" "$1" | jq -r '.'; }
run_edit() { set +e; out="$(bash "$edit" "$@" 2>"$work/err")"; rc=$?; set -e; err="$(cat "$work/err")"; }
mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
no_stray_temp() { [ -z "$(ls -A "$contract_dir" | grep '^svc\.contract\.yaml\.' | grep -v '\.lock$')" ]; }

echo "lock"
reset_contract
bash "$edit" lock "$CONTRACT"; assert "first lock creates folder" "[ -d '$CONTRACT.lock' ]"
start=$SECONDS; rc=0
bash "$edit" lock "$CONTRACT" 2>"$work/err" || rc=$?
assert "second lock exits 4" "[ $rc -eq 4 ]"
assert "busy within 15s" "[ $((SECONDS - start)) -lt 15 ]"
assert "stderr holds lock path" "grep -qF '$CONTRACT.lock' '$work/err'"
bash "$edit" unlock "$CONTRACT"
rc=0; bash "$edit" lock "$CONTRACT" || rc=$?
assert "lock after unlock exits 0" "[ $rc -eq 0 ]"
bash "$edit" unlock "$CONTRACT"
rc=0; bash "$edit" unlock "$work/never-locked.contract.yaml" 2>/dev/null || rc=$?
assert "unlock of a missing lock exits 0" "[ $rc -eq 0 ]"
mkdir "$CONTRACT.lock"; touch "$CONTRACT.lock/held"
run_edit unlock "$CONTRACT"
assert "unlock of a non-empty lock folder fails" "[ $rc -eq 1 ] && echo \"\$err\" | grep -q 'cannot remove'"
rm -rf "$CONTRACT.lock"
start=$SECONDS
run_edit lock "$work/no-such-folder/svc.contract.yaml"
assert "lock without a folder fails at once" "[ $rc -eq 2 ] && [ $((SECONDS - start)) -lt 3 ] && echo \"\$err\" | grep -q 'folder missing'"

echo "apply"
cat >"$work/patch.yaml" <<'YAML'
sections:
  abilities:
    sources: ["cmd/**", "lib/**"]
    items:
      - text: 'New ability: says {"errors": [...]} # not a comment'
        refs: [cmd/main.go:1]
  interfaces:
    sources: ["api/**"]
    items:
      - text: New interface.
        refs: [api/routes.go:1]
YAML
reset_contract
run_edit apply "$CONTRACT" "$work/patch.yaml"
assert "apply replaces whole sections" "[ $rc -eq 0 ] && [ \"\$(query '$CONTRACT' '.sections.abilities')\" = \"\$(query '$work/patch.yaml' '.sections.abilities')\" ] && [ \"\$(query '$CONTRACT' '.sections.interfaces.items[0].text')\" = 'New interface.' ]"
assert "apply prints only the applied keys" "[ \"\$out\" = \"\$(printf 'abilities\ninterfaces')\" ]"
assert "apply keeps the other sections" "[ \"\$(query '$CONTRACT' '.sections.gotchas')\" = \"\$(query '$base' '.sections.gotchas')\" ]"

reset_contract
run_edit apply "$CONTRACT" "$work/patch.yaml" --sections "abilities"
assert "apply --sections limits the keys" "[ \"\$out\" = abilities ] && [ \"\$(query '$CONTRACT' '.sections.abilities.items[0].text')\" != 'Old ability.' ] && [ \"\$(query '$CONTRACT' '.sections.interfaces.items[0].text')\" = 'Old interface.' ]"
reset_contract
run_edit apply "$CONTRACT" "$work/patch.yaml" --sections "abilities, interfaces"
assert "--sections trims the space after a comma" "[ \"\$out\" = \"\$(printf 'abilities\ninterfaces')\" ]"
reset_contract
run_edit apply "$CONTRACT" "$work/patch.yaml" --section interfaces
assert "--section applies one key" "[ \"\$out\" = interfaces ] && [ \"\$(query '$CONTRACT' '.sections.abilities.items[0].text')\" = 'Old ability.' ]"

reset_contract; before="$(cksum <"$CONTRACT")"
printf 'sections:\n  intefaces:\n    sources: []\n    items: []\n' >"$work/unknown.yaml"
run_edit apply "$CONTRACT" "$work/unknown.yaml"
assert "apply unknown key exits 2 and leaves the file unchanged" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ] && echo \"\$err\" | grep -q intefaces"

printf 'sections:\n  abilities:\n    items:\n      - text: No sources.\n        refs: [cmd/main.go:1]\n' >"$work/nosources.yaml"
run_edit apply "$CONTRACT" "$work/nosources.yaml"
assert "apply of a section without sources exits 2 and leaves the file unchanged" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"
assert "a refused apply leaves no temp file" "no_stray_temp"

printf 'nothing: here\n' >"$work/empty-patch.yaml"
run_edit apply "$CONTRACT" "$work/empty-patch.yaml"
assert "a patch with nothing to apply exits 2" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"
run_edit apply "$CONTRACT" "$work/patch.yaml" --sections "consumers"
assert "--sections naming a key the patch lacks exits 2" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"

printf 'remove_planned: [docs-refresh]\n' >"$work/remove.yaml"
run_edit apply "$CONTRACT" "$work/remove.yaml"
assert "apply remove_planned removes items and prints them" "[ $rc -eq 0 ] && [ \"\$out\" = 'planned removed: docs-refresh' ] && [ \"\$(query '$CONTRACT' '[.planned[].id] | join(\",\")')\" = video-ack-after-commit ]"

echo "undo"
reset_contract; cp "$CONTRACT" "$work/snapshot.yaml"
printf 'sections:\n  abilities:\n    sources: ["cmd/**"]\n    items: []\nremove_planned: [docs-refresh]\n' >"$work/change.yaml"
bash "$edit" apply "$CONTRACT" "$work/change.yaml" >/dev/null
run_edit apply "$CONTRACT" "$work/snapshot.yaml" --sections abilities --planned docs-refresh
assert "undo: apply a snapshot with --sections and --planned restores the old state" "[ $rc -eq 0 ] && [ \"\$(json_of '$CONTRACT')\" = \"\$(json_of '$work/snapshot.yaml')\" ]"
assert "undo prints keys, then restored items" "[ \"\$out\" = \"\$(printf 'abilities\nplanned restored: docs-refresh')\" ]"
yq -i '.planned[0].title = "Changed title"' "$CONTRACT"
yq '{"planned": .planned}' "$work/snapshot.yaml" >"$work/planned-only.yaml"
run_edit apply "$CONTRACT" "$work/planned-only.yaml" --planned video-ack-after-commit
assert "--planned replaces an item with the same id in place" "[ \"\$out\" = 'planned restored: video-ack-after-commit' ] && [ \"\$(json_of '$CONTRACT')\" = \"\$(json_of '$work/snapshot.yaml')\" ]"
reset_contract; cp "$CONTRACT" "$work/snapshot.yaml"
bash "$edit" apply "$CONTRACT" "$work/change.yaml" >/dev/null
cp "$CONTRACT" "$work/changed.yaml"
run_edit apply "$CONTRACT" "$work/snapshot.yaml" --planned docs-refresh
assert "a full snapshot with only --planned leaves every section unchanged and restores the item" "[ $rc -eq 0 ] && [ \"\$out\" = 'planned restored: docs-refresh' ] && [ \"\$(yq -o=json '.sections' '$CONTRACT' | jq -S .)\" = \"\$(yq -o=json '.sections' '$work/changed.yaml' | jq -S .)\" ] && [ \"\$(query '$CONTRACT' '[.planned[].id] | sort | join(\",\")')\" = docs-refresh,video-ack-after-commit ]"
run_edit apply "$CONTRACT" "$work/snapshot.yaml" --planned no-such-id
assert "--planned with an id the patch lacks exits 2" "[ $rc -eq 2 ]"

echo "remove-planned"
reset_contract; before="$(cksum <"$CONTRACT")"
run_edit remove-planned "$CONTRACT" no-such-id
assert "remove-planned missing id exits 1" "[ $rc -eq 1 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"
run_edit remove-planned "$CONTRACT" docs-refresh
assert "remove-planned removes the item" "[ $rc -eq 0 ] && [ \"\$(query '$CONTRACT' '.planned | length')\" = 1 ]"
run_edit remove-planned "$CONTRACT" video-ack-after-commit
assert "remove-planned on an item a gotcha links exits 0 and keeps the link" "[ $rc -eq 0 ] && [ \"\$(query '$CONTRACT' '.planned | length')\" = 0 ] && [ \"\$(query '$CONTRACT' '.sections.gotchas.items[0].planned')\" = video-ack-after-commit ]"
run_edit delete-section "$CONTRACT" abilities
assert "delete-section is gone" "[ $rc -eq 2 ]"

echo "set-verified"
reset_contract
bash "$edit" set-verified "$CONTRACT" 1234567
assert "set-verified keeps 1234567 and 12e4567 as strings (1234567)" "[ \"\$(yq -o=json '.verified_commit' '$CONTRACT' | jq -r type)\" = string ] && [ \"\$(query '$CONTRACT' '.verified_commit')\" = 1234567 ]"
bash "$edit" set-verified "$CONTRACT" 12e4567
assert "set-verified keeps 1234567 and 12e4567 as strings (12e4567)" "[ \"\$(yq -o=json '.verified_commit' '$CONTRACT' | jq -r type)\" = string ] && [ \"\$(query '$CONTRACT' '.verified_commit')\" = 12e4567 ]"
assert "verified_at set" "query '$CONTRACT' '.verified_at' | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'"
cat >"$work/sha-patch.yaml" <<'YAML'
sections:
  depends_on:
    sources: []
    items:
      - text: Calls dep.
        refs: [cmd/main.go:1]
        app: dep
        mapped_commit: "12e4567"
YAML
bash "$edit" apply "$CONTRACT" "$work/sha-patch.yaml" >/dev/null
assert "apply keeps mapped_commit 12e4567 a string" "[ \"\$(yq -o=json '.sections.depends_on.items[0].mapped_commit' '$CONTRACT' | jq -r type)\" = string ]"
before="$(cksum <"$CONTRACT")"
run_edit set-verified "$CONTRACT" 'not a sha'
assert "set-verified refuses a value that fails the check" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"

echo "pending"
reset_contract
bash "$edit" pending-add "$CONTRACT" 15 t2
bash "$edit" pending-add "$CONTRACT" 15 t2
assert "pending-add twice adds one item" "[ \"\$(yq -o=json -I=0 '.pending' '$CONTRACT')\" = '[{\"pr\":15,\"task\":\"t2\"}]' ]"
bash "$edit" pending-add "$CONTRACT" 16 123
assert "pending task stays a string" "[ \"\$(yq -o=json '.pending[1].task' '$CONTRACT' | jq -r type)\" = string ]"
bash "$edit" pending-remove "$CONTRACT" 16
assert "pending-remove drops the pr" "[ \"\$(yq -o=json -I=0 '.pending' '$CONTRACT')\" = '[{\"pr\":15,\"task\":\"t2\"}]' ]"
before="$(cksum <"$CONTRACT")"
run_edit pending-add "$CONTRACT" 1x t1
assert "pending-add non-integer pr exits 2 and leaves the file" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"
run_edit pending-remove "$CONTRACT" abc
assert "pending-remove non-integer pr exits 2 and leaves the file" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"
yq -i '.pending = {"pr": 15}' "$CONTRACT"; before="$(cksum <"$CONTRACT")"
run_edit pending-add "$CONTRACT" 17 t1
assert "pending-add on a map exits 2 and leaves the file" "[ $rc -eq 2 ] && [ \"\$(cksum <'$CONTRACT')\" = '$before' ]"

echo "render"
reset_contract
run_edit set-verified "$CONTRACT" abcdef1
assert "a write renders the note" "[ $rc -eq 0 ] && [ -f '$note' ] && [ -f '$HOME/.wstack/pages/contracts/svc.html' ]"
assert "a write prints no render paths" "[ -z \"\$out\" ]"
rm -rf "$HOME/.wstack/pages/contracts"; mkdir -p "$HOME/.wstack/pages"; : >"$HOME/.wstack/pages/contracts"
run_edit apply "$CONTRACT" "$work/patch.yaml" --sections abilities
assert "render failure warns and exits 0" "[ $rc -eq 0 ] && [ \"\$out\" = abilities ] && echo \"\$err\" | grep -q '^contract-edit.sh: warning: render failed: ' && [ \"\$(query '$CONTRACT' '.sections.abilities.sources[1]')\" = 'lib/**' ]"
rm -f "$HOME/.wstack/pages/contracts"

echo "file mode"
reset_contract; chmod 644 "$CONTRACT"
bash "$edit" set-verified "$CONTRACT" def4567
assert "set-verified keeps 644" "[ \"\$(mode_of '$CONTRACT')\" = 644 ]"
bash "$edit" apply "$CONTRACT" "$work/patch.yaml" >/dev/null
assert "apply keeps 644" "[ \"\$(mode_of '$CONTRACT')\" = 644 ]"
chmod 444 "$CONTRACT"
run_edit set-verified "$CONTRACT" def4568
assert "set-verified on a 444 file works and keeps 444" "[ $rc -eq 0 ] && [ \"\$(mode_of '$CONTRACT')\" = 444 ] && [ \"\$(query '$CONTRACT' '.verified_commit')\" = def4568 ]"
chmod 644 "$CONTRACT"
assert "no temp file left after writes" "no_stray_temp"

echo "diagrams"
block="$here/fixtures/contract/diagrams-block.yaml"
reset_contract; cp "$CONTRACT" "$work/no-diagrams-snapshot.yaml"
cp "$block" "$work/diagrams-patch.yaml"
yq -i '.sections.abilities = load("'"$CONTRACT"'").sections.abilities | .sections.abilities.items = [{"text": "New ability.", "refs": ["cmd/main.go:1"]}]' "$work/diagrams-patch.yaml"
run_edit apply "$CONTRACT" "$work/diagrams-patch.yaml"
assert "apply with no flag applies diagrams" "[ $rc -eq 0 ] && printf '%s\n' \"\$out\" | grep -qx diagrams && [ \"\$(query '$CONTRACT' '.diagrams' | jq -S .)\" = \"\$(query '$block' '.diagrams' | jq -S .)\" ]"
reset_contract
run_edit apply "$CONTRACT" "$work/diagrams-patch.yaml" --sections abilities
assert "--sections alone leaves diagrams" "[ $rc -eq 0 ] && [ \"\$(query '$CONTRACT' '.diagrams')\" = null ] && ! printf '%s\n' \"\$out\" | grep -qx diagrams"
reset_contract; yq -i '. *= load("'"$block"'")' "$CONTRACT"
run_edit apply "$CONTRACT" "$work/no-diagrams-snapshot.yaml" --diagrams
assert "--diagrams from a snapshot without diagrams removes the block" "[ $rc -eq 0 ] && [ \"\$(query '$CONTRACT' '.diagrams')\" = null ] && printf '%s\n' \"\$out\" | grep -qx diagrams"
reset_contract; yq '{"diagrams": .diagrams}' "$block" > "$work/only-diagrams.yaml"
run_edit apply "$CONTRACT" "$work/only-diagrams.yaml"
assert "a patch with only diagrams is accepted" "[ $rc -eq 0 ] && [ \"\$out\" = diagrams ] && [ \"\$(query '$CONTRACT' '.diagrams.flow.parts[0].id')\" = api ]"
reset_contract; printf 'diagrams:\n  - a\n' > "$work/list-diagrams.yaml"
run_edit apply "$CONTRACT" "$work/list-diagrams.yaml"
assert "a patch with diagrams as a list is refused" "[ $rc -ne 0 ] && [ \"\$(json_of '$CONTRACT')\" = \"\$(json_of '$base')\" ]"

echo "next-decision-id"
assert "missing folder gives 0001" "[ \"\$(bash '$edit' next-decision-id '$work/none')\" = 0001 ]"
mkdir "$work/dec"; touch "$work/dec/0001-a.md" "$work/dec/0003-b.md"
assert "after 0003 gives 0004" "[ \"\$(bash '$edit' next-decision-id '$work/dec')\" = 0004 ]"

finish
