#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/_assert.sh"
source "$here/../scripts/lib/frontmatter.sh"
edit="$here/../scripts/contract-edit.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

contract="$work/app.md"
write_contract() {
  cat >"$contract" <<'DOC'
---
base_branch: main
verified_commit: abc123
pending: []
tags: ["type/contract"]
---
# App

## Abilities

Old abilities.

## Interfaces

Old interfaces.

### Detail

Old detail.

## Team docs

- @docs/a.md
DOC
}

echo "lock"
write_contract
bash "$edit" lock "$contract"; assert "first lock creates folder" "[ -d '$contract.lock' ]"
start=$SECONDS; rc=0
bash "$edit" lock "$contract" 2>"$work/err" || rc=$?
assert "second lock exits 4" "[ $rc -eq 4 ]"
assert "busy within 15s" "[ $((SECONDS - start)) -lt 15 ]"
assert "stderr holds lock path" "grep -qF '$contract.lock' '$work/err'"
bash "$edit" unlock "$contract"
rc=0; bash "$edit" lock "$contract" || rc=$?
assert "lock after unlock exits 0" "[ $rc -eq 0 ]"
bash "$edit" unlock "$contract"

echo "apply"
write_contract; cp "$contract" "$work/before.md"
printf '## Interfaces\n\nNew interfaces.\n\n### Detail\n\nNew detail.\n' >"$work/patch.md"
names="$(bash "$edit" apply "$contract" "$work/patch.md")"
assert "prints applied name" "[ '$names' = 'Interfaces' ]"
expected="$(awk '/^## Interfaces/{skip=1; print; print ""; print "New interfaces."; print ""; print "### Detail"; print ""; print "New detail."; print ""; next} /^## /{skip=0} !skip' "$work/before.md")"
assert "only Interfaces changed, rest byte for byte" "[ \"\$(cat '$contract')\" = \"\$expected\" ]"
assert "subheading kept" "grep -qx '### Detail' '$contract'"
assert "old text gone" "! grep -q 'Old interfaces' '$contract'"

write_contract
printf '## Consumers\n\nApp B.\n' >"$work/patch.md"
bash "$edit" apply "$contract" "$work/patch.md" >/dev/null
assert "new section appended" "[ \"\$(tail -n 1 '$contract')\" = 'App B.' ] && grep -qx '## Consumers' '$contract'"
assert "existing section kept" "grep -q 'Old interfaces' '$contract'"

write_contract
printf '## Abilities\n\nNew abilities.\n\n## Interfaces\n\nNew interfaces.\n' >"$work/patch.md"
names="$(bash "$edit" apply "$contract" "$work/patch.md" --sections "Abilities")"
assert "--sections applies only Abilities" "[ '$names' = 'Abilities' ] && grep -q 'New abilities' '$contract' && grep -q 'Old interfaces' '$contract'"

write_contract
bash "$edit" apply "$contract" "$work/patch.md" --sections "Abilities, Interfaces" >/dev/null
assert "--sections trims the space after a comma" "grep -q 'New abilities' '$contract' && grep -q 'New interfaces' '$contract'"

write_contract
printf '## Abilities\n\nNew abilities.\n\n## Remove from plan\n\n- P2\n' >"$work/patch.md"
bash "$edit" apply "$contract" "$work/patch.md" >/dev/null
assert "Remove from plan not applied" "! grep -q 'Remove from plan' '$contract'"

printf 'no sections here\n' >"$work/patch.md"
rc=0; bash "$edit" apply "$contract" "$work/patch.md" >/dev/null || rc=$?
assert "empty patch exits 2" "[ $rc -eq 2 ]"

echo "delete-section"
plan="$work/plan.md"
printf '# Plan\n\n## P1 Base\n\nx\n\n## P2 Redis cache\n\ny\n\n## P3 Docs\n\nz\n' >"$plan"
bash "$edit" delete-section "$plan" "P2 Redis cache"
assert "P2 removed" "! grep -q 'P2 Redis cache' '$plan' && ! grep -qx y '$plan'"
assert "P1 and P3 kept" "grep -q '## P1 Base' '$plan' && grep -q '## P3 Docs' '$plan'"
rc=0; bash "$edit" delete-section "$plan" "P9 none" || rc=$?
assert "missing section exits 1" "[ $rc -eq 1 ]"

echo "pending and verified"
write_contract
bash "$edit" pending-add "$contract" 15 t2
bash "$edit" pending-add "$contract" 16 t3
bash "$edit" pending-remove "$contract" 16
assert "pending is one item" "[ \"\$(fm_get '$contract' pending)\" = '[{\"pr\":15,\"task\":\"t2\"}]' ]"
bash "$edit" set-verified "$contract" def456
assert "verified_commit set" "[ \"\$(fm_get '$contract' verified_commit)\" = def456 ]"
assert "verified_at set" "fm_get '$contract' verified_at | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'"

echo "closed PR drops its pending item and keeps the body"
write_contract
bash "$edit" pending-add "$contract" 21 t9
cp "$contract" "$work/closed-before.md"
body_of() { awk 'n>=2{print} /^---$/{n++}' "$1"; }
bash "$edit" pending-remove "$contract" 21
assert "closed PR: pending is empty" "[ \"\$(fm_get '$contract' pending)\" = '[]' ]"
assert "closed PR: body is unchanged" "[ \"\$(body_of '$contract')\" = \"\$(body_of '$work/closed-before.md')\" ]"

echo "next-decision-id"
assert "missing folder gives 0001" "[ \"\$(bash '$edit' next-decision-id '$work/none')\" = 0001 ]"
mkdir "$work/dec"; touch "$work/dec/0001-a.md" "$work/dec/0003-b.md"
assert "after 0003 gives 0004" "[ \"\$(bash '$edit' next-decision-id '$work/dec')\" = 0004 ]"

echo "bad input"
rc=0; bash "$edit" unlock "$work/never-locked.md" 2>/dev/null || rc=$?
assert "unlock of a missing lock exits 0" "[ $rc -eq 0 ]"
write_contract; cp "$contract" "$work/before.md"
rc=0; bash "$edit" pending-remove "$contract" abc 2>/dev/null || rc=$?
assert "pending-remove non-integer pr fails" "[ $rc -ne 0 ]"
assert "pending-remove non-integer pr leaves file" "cmp -s '$contract' '$work/before.md'"
rc=0; bash "$edit" pending-add "$contract" abc t1 2>/dev/null || rc=$?
assert "pending-add non-integer pr fails" "[ $rc -ne 0 ]"
assert "pending-add non-integer pr leaves file" "cmp -s '$contract' '$work/before.md'"
sed 's/^pending: .*/pending: [{broken/' "$work/before.md" >"$contract"; cp "$contract" "$work/malformed.md"
rc=0; bash "$edit" pending-remove "$contract" 15 2>/dev/null || rc=$?
assert "pending-remove malformed pending fails" "[ $rc -ne 0 ]"
assert "pending-remove malformed pending leaves file" "cmp -s '$contract' '$work/malformed.md'"
write_contract; : >"$work/empty.md"
rc=0; bash "$edit" apply "$contract" "$work/empty.md" >/dev/null 2>&1 || rc=$?
assert "0-byte patch exits 2" "[ $rc -eq 2 ]"
assert "0-byte patch leaves target" "cmp -s '$contract' '$work/before.md'"

finish
