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
locked="$work/locked"; mkdir "$locked"; cp "$plan" "$locked/plan.md"; chmod 555 "$locked"
rc=0; bash "$edit" delete-section "$locked/plan.md" "P1 Base" 2>/dev/null || rc=$?
chmod 755 "$locked"
assert "write failure exits 2, not the no-section 1" "[ $rc -eq 2 ] && grep -q 'P1 Base' '$locked/plan.md'"

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

mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }

echo "A1-7 file mode is kept"
write_contract; chmod 644 "$contract"
bash "$edit" set-verified "$contract" def456
assert "set-verified keeps 644" "[ \"\$(mode_of '$contract')\" = 644 ]"
bash "$edit" pending-add "$contract" 31 t1
assert "pending-add keeps 644" "[ \"\$(mode_of '$contract')\" = 644 ]"
printf '## Interfaces\n\nNew.\n' >"$work/patch.md"
bash "$edit" apply "$contract" "$work/patch.md" >/dev/null
assert "apply keeps 644" "[ \"\$(mode_of '$contract')\" = 644 ]"
bash "$edit" delete-section "$contract" Interfaces
assert "delete-section keeps 644" "[ \"\$(mode_of '$contract')\" = 644 ]"

echo "read-only target"
write_contract; chmod 444 "$contract"
rc=0; bash "$edit" set-verified "$contract" def456 2>/dev/null || rc=$?
assert "set-verified on a 444 file works and keeps 444" "[ $rc -eq 0 ] && [ \"\$(mode_of '$contract')\" = 444 ] && [ \"\$(fm_get '$contract' verified_commit)\" = def456 ]"
assert "no stray temp file after a 444 write" "[ -z \"\$(ls -A '$work' | grep '^app.md\\.')\" ]"
chmod 644 "$contract"

echo "CRLF contract with an LF patch"
write_contract; sed 's/$/\r/' "$contract" >"$work/crlf.md"
printf '## Interfaces\n\nCRLF new.\n' >"$work/patch.md"
bash "$edit" apply "$work/crlf.md" "$work/patch.md" >/dev/null 2>"$work/err"
assert "apply replaces the section, no duplicate, no warning" "[ \"\$(grep -c '^## Interfaces' '$work/crlf.md')\" = 1 ] && grep -q 'CRLF new' '$work/crlf.md' && ! grep -q 'Old interfaces' '$work/crlf.md' && [ ! -s '$work/err' ]"
assert "apply writes LF" "! grep -q \$'\\r' '$work/crlf.md'"
write_contract; sed 's/$/\r/' "$contract" >"$work/crlf.md"
bash "$edit" delete-section "$work/crlf.md" Interfaces
assert "delete-section finds a CRLF heading" "! grep -q 'Old interfaces' '$work/crlf.md' && grep -q 'Team docs' '$work/crlf.md'"

echo "A1-9 a failure on the second key changes nothing"
write_contract; cp "$contract" "$work/before-sv.md"
fake_bin="$work/fakebin"; mkdir -p "$fake_bin"; real_awk="$(command -v awk)"
printf '#!/usr/bin/env bash\nn=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n+1)); echo $n >"%s/count"\n[ "$n" -ne 2 ] || exit 1\nexec "%s" "$@"\n' "$work" "$work" "$real_awk" >"$fake_bin/awk"
chmod +x "$fake_bin/awk"; rm -f "$work/count"
rc=0; PATH="$fake_bin:$PATH" bash "$edit" set-verified "$contract" def456 2>/dev/null || rc=$?
assert "second write fails: set-verified fails" "[ $rc -ne 0 ]"
assert "second write fails: verified_commit unchanged" "cmp -s '$contract' '$work/before-sv.md'"
assert "second write fails: no stray temp file" "[ -z \"\$(ls -A '$work' | grep '^app.md\\.')\" ]"

echo "A1-8 lock in a missing folder"
start=$SECONDS; rc=0
bash "$edit" lock "$work/no-such-folder/app.md" 2>"$work/err" || rc=$?
assert "lock without a folder fails at once" "[ $rc -eq 2 ] && [ $((SECONDS - start)) -lt 3 ] && grep -q 'folder missing' '$work/err'"

echo "A1-9 set-verified is one write"
write_contract
bash "$edit" set-verified "$contract" def456
assert "both keys set together" "[ \"\$(fm_get '$contract' verified_commit)\" = def456 ] && fm_get '$contract' verified_at | grep -q T"
assert "no temp file left" "[ -z \"\$(ls '$work' | grep 'app.md\\.')\" ]"

echo "A1-10 blank lines and odd inputs"
printf -- '---\nk: v\n---\n## A\n\ntext A\n\n\n## B\n\ntext B' >"$work/nonl.md"
printf '## Z\n\nnew Z\n' >"$work/patch.md"
bash "$edit" apply "$work/nonl.md" "$work/patch.md" 2>/dev/null >/dev/null
assert "no trailing newline: one blank line before the appended section" "[ \"\$(tail -n 5 '$work/nonl.md')\" = \"\$(printf 'text B\n\n## Z\n\nnew Z')\" ]"
printf -- '---\nk: v\n---\n## A\n\ntext A\n\n\n\n' >"$work/blanks.md"
bash "$edit" apply "$work/blanks.md" "$work/patch.md" 2>/dev/null >/dev/null
assert "trailing blank lines collapse to one before an appended section" "[ \"\$(tail -n 5 '$work/blanks.md')\" = \"\$(printf 'text A\n\n## Z\n\nnew Z')\" ]"
printf -- '---\nk: v\n---\n## A.* (v+1)\n\nold\n\n## B\n\nkeep\n' >"$work/regex.md"
printf '## A.* (v+1)\n\nreplaced\n' >"$work/patch.md"
bash "$edit" apply "$work/regex.md" "$work/patch.md" >/dev/null
assert "regex-special heading is replaced" "grep -q replaced '$work/regex.md' && ! grep -q '^old' '$work/regex.md' && grep -q keep '$work/regex.md'"
bash "$edit" delete-section "$work/regex.md" 'A.* (v+1)'
assert "regex-special heading is deleted" "! grep -q replaced '$work/regex.md' && grep -q keep '$work/regex.md'"
write_contract
bash "$edit" set-verified "$contract" 'a&b\n|c'
assert "odd value is stored verbatim" "[ \"\$(fm_get '$contract' verified_commit)\" = 'a&b\\n|c' ]"
rc=0; bash "$edit" pending-add "$contract" 1x t1 2>/dev/null || rc=$?
assert "non-numeric pr fails with 2" "[ $rc -eq 2 ]"

echo "A1-11 unlock and a non-array pending"
write_contract
mkdir "$contract.lock"; touch "$contract.lock/held"
rc=0; bash "$edit" unlock "$contract" 2>"$work/err" || rc=$?
assert "unlock of a non-empty lock folder fails" "[ $rc -eq 1 ] && grep -q 'cannot remove' '$work/err'"
rm -rf "$contract.lock"
sed 's/^pending: .*/pending: {"pr":15}/' "$work/before.md" >"$contract"; cp "$contract" "$work/object.md"
rc=0; bash "$edit" pending-remove "$contract" 15 2>/dev/null || rc=$?
assert "pending-remove on an object fails" "[ $rc -eq 2 ] && cmp -s '$contract' '$work/object.md'"
rc=0; bash "$edit" pending-add "$contract" 15 t1 2>/dev/null || rc=$?
assert "pending-add on an object fails" "[ $rc -eq 2 ] && cmp -s '$contract' '$work/object.md'"

echo "A1-15 pending-add skips an existing pr"
write_contract
bash "$edit" pending-add "$contract" 15 t2
bash "$edit" pending-add "$contract" 15 t2
assert "retried pending-add adds one item" "[ \"\$(fm_get '$contract' pending)\" = '[{\"pr\":15,\"task\":\"t2\"}]' ]"

echo "A1-16 apply warns about a new section"
write_contract
printf '## Intefaces\n\nTypo.\n' >"$work/patch.md"
bash "$edit" apply "$contract" "$work/patch.md" >/dev/null 2>"$work/err"
assert "warning names the new section" "grep -q 'warning.*Intefaces' '$work/err'"
printf '## Interfaces\n\nFine.\n' >"$work/patch.md"
bash "$edit" apply "$contract" "$work/patch.md" >/dev/null 2>"$work/err"
assert "no warning for an existing section" "[ ! -s '$work/err' ]"

echo "A1-17 backslash and comma headings"
printf -- '---\nk: v\n---\n## Back\\slash\n\nold\n\n## Plan, step 2\n\nold2\n\n## Other\n\nkeep\n' >"$work/odd.md"
cp "$work/odd.md" "$work/odd-before.md"
bash "$edit" delete-section "$work/odd.md" 'Back\slash'
assert "backslash heading is deleted" "! grep -q 'Back' '$work/odd.md' && grep -q 'Plan, step 2' '$work/odd.md'"
printf '## Plan, step 2\n\nnew2\n\n## Other\n\nchanged\n' >"$work/patch.md"
bash "$edit" apply "$work/odd.md" "$work/patch.md" --section 'Plan, step 2' >/dev/null
assert "--section applies one comma name only" "grep -q new2 '$work/odd.md' && grep -q keep '$work/odd.md' && ! grep -q changed '$work/odd.md'"
bash "$edit" apply "$work/odd-before.md" "$work/patch.md" --section 'Plan, step 2' --section Other >/dev/null
assert "--section repeats" "grep -q new2 '$work/odd-before.md' && grep -q changed '$work/odd-before.md'"

echo "block-style pending"
printf -- '---\nbase_branch: main\npending:\n  - pr: 12\n---\n# App\n' >"$work/block.md"
set +e; bash "$edit" pending-add "$work/block.md" 13 t1 >/dev/null 2>"$work/err"; add_rc=$?
bash "$edit" pending-remove "$work/block.md" 12 >/dev/null 2>>"$work/err"; remove_rc=$?; set -e
assert "block-style pending: add and remove exit 2" "[ $add_rc = 2 ] && [ $remove_rc = 2 ] && grep -q 'pending must be a one-line JSON list' '$work/err'"

finish
