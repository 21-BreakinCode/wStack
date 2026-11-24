#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/contract-validate.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

write_valid() {  # <path>
  cat > "$1" <<'YAML'
app_name: example-service
repo: example-org/example-service
base_branch: staging
verified_commit: "e2117a9"
verified_at: 2026-11-23T11:16:45Z
pending: []
ignore: []
tags: [type/contract]
summary: Stores uploaded media folders.
sections:
  team_docs:
    sources: [README.md]
  abilities:
    sources: [app/core/**]
    items:
      - text: A folder with storage_bucket set is read-only.
        refs: [app/config.py:147-152, "app/core/a.py:1,3-4"]
  interfaces:
    sources: [app/ports/**]
    items: []
  depends_on:
    sources: [pyproject.toml]
    items:
      - text: Calls video-center-2 with no timeout.
        refs: [app/ports/clients/video_center.py:10-14]
        app: video-center-2
        mapped_commit: "4f3c2a1"
  consumers:
    items: []
  gotchas:
    items:
      - text: Video workers ack before they commit.
        refs: [app/workers/video_worker.py:40-42]
        planned: video-ack-after-commit
  open_questions:
    items: []
planned:
  - id: video-ack-after-commit
    title: Video workers ack after the commit
    why: A failed commit loses the message today.
    refs: [app/workers/video_worker.py:52-56]
YAML
}

run_case() {  # <label-free> <file>; sets rc and err
  rc=0; err="$(bash "$script" "$1" 2>&1 >/dev/null)" || rc=$?
}

valid="$work_dir/valid.yaml"; write_valid "$valid"
run_case "$valid"
assert "valid file exits 0" '[ "$rc" = "0" ] && [ -z "$err" ]'

mutate() {  # <name> <yq expression>; writes $work_dir/<name>.yaml
  yq "$2" "$valid" > "$work_dir/$1.yaml"
}

mutate nosummary 'del(.summary)'; run_case "$work_dir/nosummary.yaml"
assert "missing summary exits 1" '[ "$rc" = "1" ]'
assert "missing summary names summary" 'echo "$err" | grep -q "summary"'

mutate noopen 'del(.sections.open_questions)'; run_case "$work_dir/noopen.yaml"
assert "missing open_questions key exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q open_questions'

mutate extras '.sections.extras = {"items": []}'; run_case "$work_dir/extras.yaml"
assert "unknown section key exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q extras'

mutate nosources 'del(.sections.abilities.sources)'; run_case "$work_dir/nosources.yaml"
assert "abilities without sources exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q abilities'

mutate norefs 'del(.sections.abilities.items[0].refs)'; run_case "$work_dir/norefs.yaml"
assert "item without refs exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q abilities'

mutate badid '.planned[0].id = "Video_Ack"'; run_case "$work_dir/badid.yaml"
assert "planned id not kebab case exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q "Video_Ack"'

mutate badlink '.sections.gotchas.items[0].planned = "no-such-id"'; run_case "$work_dir/badlink.yaml"
assert "gotcha planned link to a missing id exits 0 with a warning" '[ "$rc" = "0" ] && echo "$err" | grep -qx "warning: gotchas\[0\] links missing plan item no-such-id"'

mutate badlinkcase '.sections.gotchas.items[0].planned = "No_Such"'; run_case "$work_dir/badlinkcase.yaml"
assert "gotcha planned link not kebab case exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q "No_Such"'

mutate badlinktype '.sections.gotchas.items[0].planned = 5'; run_case "$work_dir/badlinktype.yaml"
assert "gotcha planned link not a string exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q "gotchas\[0\]"'

sed 's/^verified_commit: .*/verified_commit: 1234567/' "$valid" > "$work_dir/numeric.yaml"; run_case "$work_dir/numeric.yaml"
assert "numeric verified_commit exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q verified_commit'

mutate badref '.sections.abilities.items[0].refs = ["app/x.py"]'; run_case "$work_dir/badref.yaml"
assert "bad ref form exits 1" '[ "$rc" = "1" ] && echo "$err" | grep -q "app/x.py"'

mutate crossrepo '.sections.consumers.items = [{"text": "web sends the tag.", "refs": ["acme-org/web@ca3a273:src/a.ts:22"]}]'; run_case "$work_dir/crossrepo.yaml"
assert "cross-repo ref form is accepted" '[ "$rc" = "0" ]'

words="$(printf 'w%s ' $(seq 1 26))"
mutate long ".sections.abilities.items[0].text = \"$words\""
rc=0; err="$(bash "$script" "$work_dir/long.yaml" 2>&1)" || rc=$?
assert "26-word item warns and exits 0" '[ "$rc" = "0" ] && echo "$err" | grep -q "warning: abilities\[0\] has 26 words"'

rc=0; bash "$script" "$work_dir/missing.yaml" >/dev/null 2>&1 || rc=$?
assert "missing file exits 2" '[ "$rc" = "2" ]'

filled="$work_dir/filled.yaml"
sed -e 's/{{app_name}}/example-service/g' -e 's/{{repo}}/example-org\/example-service/' \
  -e 's/{{base_branch}}/staging/' -e 's/{{org_kebab}}/example-org/' \
  -e 's/^summary: ""/summary: Does one thing./' "$repo_root/templates/contract.yaml" > "$filled"
run_case "$filled"
assert "template with placeholders filled is valid except empty verified_commit" '[ "$rc" = "0" ]'

finish
