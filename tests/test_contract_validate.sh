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

fixture="$repo_root/tests/fixtures/contract/diagrams-block.yaml"
with_diagrams="$work_dir/with-diagrams.yaml"
cp "$valid" "$with_diagrams"; yq -i '. *= load("'"$fixture"'")' "$with_diagrams"
mutate_diagrams() {  # <name> <yq expression>; mutates a copy of the full fixture block
  yq "$2" "$with_diagrams" > "$work_dir/$1.yaml"; run_case "$work_dir/$1.yaml"
}
expect_error() {  # <label> <stderr text>
  expected_text="$2"
  assert "$1" '[ "$rc" = "1" ] && printf "%s\n" "$err" | grep -qF -- "$expected_text"'
}

run_case "$with_diagrams"
assert "the full fixture block is valid" '[ "$rc" = "0" ] && [ -z "$err" ]'
mutate_diagrams nodiagrams 'del(.diagrams)'
assert "no diagrams key is valid" '[ "$rc" = "0" ]'
mutate_diagrams emptydiagrams '.diagrams = {}'
assert "diagrams: {} is valid" '[ "$rc" = "0" ]'
mutate_diagrams nulldiagrams '.diagrams = null'
assert "diagrams: null is valid" '[ "$rc" = "0" ]'

mutate_diagrams listdiagrams '.diagrams = []'
expect_error "diagrams that is a list fails" "diagrams must be a map: diagrams"
mutate_diagrams badid '.diagrams.flow.parts[0].id = "Bad_Id"'
expect_error "a bad id fails" "bad diagram id: diagrams.flow.parts[0]: Bad_Id"
mutate_diagrams dupid '.diagrams.flow.callers[0].id = "api"'
expect_error "a duplicate id fails" "duplicate diagram id: diagrams.flow.callers[0]: api"
mutate_diagrams unknownedge '.diagrams.flow.edges[0].from = "nobody"'
expect_error "an edge to an unknown id fails" "edge names an unknown id: diagrams.flow.edges[0]: nobody"
mutate_diagrams noparttouch '.diagrams.flow.edges[0].to = "postgres"'
expect_error "an edge that touches no part fails" "edge touches no part: diagrams.flow.edges[0]"

mutate_diagrams partnorefs 'del(.diagrams.flow.parts[0].refs)'
expect_error "a part without refs fails" "diagram entry without refs: diagrams.flow.parts[0]"
mutate_diagrams edgenorefs 'del(.diagrams.flow.edges[0].refs)'
expect_error "an edge without refs fails" "diagram entry without refs: diagrams.flow.edges[0]"
mutate_diagrams stepnorefs 'del(.diagrams.sequences[0].steps[0].refs)'
expect_error "a step without refs fails" "diagram entry without refs: diagrams.sequences[0].steps[0]"
mutate_diagrams transitionnorefs 'del(.diagrams.states[0].transitions[0].refs)'
expect_error "a transition without refs fails" "diagram entry without refs: diagrams.states[0].transitions[0]"
mutate_diagrams wrongtypeflow '.diagrams.flow = ["x"]'
expect_error "wrong type flow fails" "diagrams.flow must be a map: diagrams.flow"
mutate_diagrams wrongtypearchitecture '.diagrams.architecture = "clean"'
expect_error "wrong type architecture fails" "diagrams.architecture must be a map: diagrams.architecture"
mutate_diagrams wrongtypeparts '.diagrams.flow.parts = "x"'
expect_error "wrong type parts fails" "diagrams.flow.parts must be a list: diagrams.flow.parts"
mutate_diagrams wrongtypecallers '.diagrams.flow.callers = "x"'
expect_error "wrong type callers fails" "diagrams.flow.callers must be a list: diagrams.flow.callers"
mutate_diagrams wrongtypedependencies '.diagrams.flow.dependencies = "x"'
expect_error "wrong type dependencies fails" "diagrams.flow.dependencies must be a list: diagrams.flow.dependencies"
mutate_diagrams wrongtypeedges '.diagrams.flow.edges = "x"'
expect_error "wrong type edges fails" "diagrams.flow.edges must be a list: diagrams.flow.edges"
mutate_diagrams wrongtypesequences '.diagrams.sequences = {"a": 1}'
expect_error "wrong type sequences fails" "diagrams.sequences must be a list: diagrams.sequences"
mutate_diagrams wrongtypestates '.diagrams.states = "x"'
expect_error "wrong type states fails" "diagrams.states must be a list: diagrams.states"
mutate_diagrams wrongtypelayers '.diagrams.architecture.layers = "x"'
expect_error "wrong type layers fails" "diagrams.architecture.layers must be a list: diagrams.architecture.layers"
mutate_diagrams wrongtypecomponents '.diagrams.architecture.layers[0].components = "x"'
expect_error "wrong type components fails" "diagrams.architecture.layers[0].components must be a list: diagrams.architecture.layers[0].components"
mutate_diagrams wrongtypeimplements '.diagrams.architecture.implements = "x"'
expect_error "wrong type implements fails" "diagrams.architecture.implements must be a list: diagrams.architecture.implements"
mutate_diagrams wrongtypesteps '.diagrams.sequences[0].steps = "x"'
expect_error "wrong type steps fails" "diagrams.sequences[0].steps must be a list: diagrams.sequences[0].steps"
mutate_diagrams wrongtypetransitions '.diagrams.states[0].transitions = "x"'
expect_error "wrong type transitions fails" "diagrams.states[0].transitions must be a list: diagrams.states[0].transitions"
mutate_diagrams wrongtypepartrefs '.diagrams.flow.parts[0].refs = "x"'
expect_error "wrong type partrefs fails" "diagrams.flow.parts[0].refs must be a list: diagrams.flow.parts[0].refs"
mutate_diagrams wrongtypecallerrefs '.diagrams.flow.callers[0].refs = "x"'
expect_error "wrong type callerrefs fails" "diagrams.flow.callers[0].refs must be a list: diagrams.flow.callers[0].refs"
mutate_diagrams wrongtypedependencyrefs '.diagrams.flow.dependencies[0].refs = "x"'
expect_error "wrong type dependencyrefs fails" "diagrams.flow.dependencies[0].refs must be a list: diagrams.flow.dependencies[0].refs"
mutate_diagrams componentnorefs 'del(.diagrams.architecture.layers[0].components[0].refs)'
expect_error "an architecture component without refs fails" "diagram entry without refs: diagrams.architecture.layers[0].components[0]"
mutate_diagrams callernorefs 'del(.diagrams.flow.callers[0].refs)'
assert "a caller without refs is valid" '[ "$rc" = "0" ]'

mutate_diagrams partnolabel 'del(.diagrams.flow.parts[0].label)'
expect_error "a part without a label fails" "diagram entry without label: diagrams.flow.parts[0]"
mutate_diagrams callernolabel 'del(.diagrams.flow.callers[0].label)'
expect_error "a caller without a label fails" "diagram entry without label: diagrams.flow.callers[0]"
mutate_diagrams depnolabel 'del(.diagrams.flow.dependencies[0].label)'
expect_error "a dependency without a label fails" "diagram entry without label: diagrams.flow.dependencies[0]"
mutate_diagrams stepnolabel 'del(.diagrams.sequences[0].steps[0].label)'
expect_error "a step without a label fails" "diagram entry without label: diagrams.sequences[0].steps[0]"
mutate_diagrams componentnolabel 'del(.diagrams.architecture.layers[0].components[0].label)'
expect_error "a component without a label fails" "diagram entry without label: diagrams.architecture.layers[0].components[0]"
mutate_diagrams edgenolabel 'del(.diagrams.flow.edges[0].label) | del(.diagrams.states[0].transitions[0].label)'
assert "edges and transitions need no label" '[ "$rc" = "0" ]'

mutate_diagrams nosteps '.diagrams.sequences[0].steps = []'
expect_error "a sequence without steps fails" "sequence without steps: diagrams.sequences[0]"
mutate_diagrams notransitions '.diagrams.states[0].transitions = []'
expect_error "a state lifecycle without transitions fails" "state lifecycle without transitions: diagrams.states[0]"
mutate_diagrams badinitial '.diagrams.states[0].initial = "gone"'
expect_error "initial that names no state fails" "initial names no state: diagrams.states[0]: gone"
mutate_diagrams badstyle '.diagrams.architecture.style = "onion"'
expect_error "a bad style fails" "bad architecture style: diagrams.architecture.style: onion"
mutate_diagrams badkind '.diagrams.architecture.layers[0].components[0].kind = "thing"'
expect_error "a bad component kind fails" "bad component kind: diagrams.architecture.layers[0].components[0]: thing"
mutate_diagrams badsibling '.diagrams.architecture.layers[0].sibling = "yes"'
expect_error "a string sibling flag fails" "bad sibling flag: diagrams.architecture.layers[0]: yes"
mutate_diagrams siblingtrue '.diagrams.architecture.layers[0].sibling = true | .diagrams.architecture.layers[1].sibling = false'
assert "boolean sibling flags pass" '[ "$rc" = "0" ]'
mutate_diagrams badimplements '.diagrams.architecture.implements[0].port = "sql-store"'
expect_error "an implements pair with a wrong kind fails" "implements needs an adapter and a port: diagrams.architecture.implements[0]"
mutate_diagrams badrefform '.diagrams.flow.edges[0].refs = ["nofile"]'
expect_error "a bad ref form in a diagram fails" "bad ref form: diagrams.flow.edges[0]: nofile"

extra_parts="$(for n in $(seq 1 25); do printf '{"id": "extra-%s", "label": "x", "refs": ["a.go:1"]}, ' "$n"; done)"
mutate_diagrams manynodes ".diagrams.flow.parts += [${extra_parts%, }]"
assert "31 flow nodes only warn" '[ "$rc" = "0" ] && printf "%s\n" "$err" | grep -qF "diagrams.flow has 31 nodes"'
mutate_diagrams longlabel '.diagrams.flow.parts[0].label = "01234567890123456789012345678901234567890"'
assert "a 41-character label only warns" '[ "$rc" = "0" ] && printf "%s\n" "$err" | grep -qF "label has 41 characters"'

finish
