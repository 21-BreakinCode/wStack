#!/usr/bin/env bash
# Usage: contract-validate.sh <contract.yaml>
# Exit 0 valid, 1 broken rule (one line per break on stderr), 2 unusable input or yq.
set -euo pipefail

contract_file="${1:-}"
[ -n "$contract_file" ] || { echo "usage: contract-validate.sh <contract.yaml>" >&2; exit 2; }
[ -f "$contract_file" ] || { echo "contract-validate.sh: no such file: $contract_file" >&2; exit 2; }

yq_version="$(yq --version 2>&1 || true)"
case "$yq_version" in
  *mikefarah*" version v4."* | *mikefarah*" version 4."*) ;;
  *) echo "contract-validate.sh: needs mikefarah yq v4: brew install yq" >&2; exit 2 ;;
esac

contract_json="$(yq -o=json '.' "$contract_file" 2>/dev/null)" || {
  echo "contract-validate.sh: cannot read YAML: $contract_file" >&2; exit 2; }

# one line per finding: "E <rule>: <where>" or "W <warning>"
findings="$(printf '%s' "$contract_json" | jq -r '
  def lines: "[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*";
  def valid_ref: test("^([^/@:]+/[^/@:]+@[0-9a-f]+:)?[^:]+:" + lines + "$");
  def hex_or_empty: type == "string" and (. == "" or test("^[0-9a-f]{4,64}$"));
  def section_keys: ["team_docs","abilities","interfaces","depends_on","consumers","gotchas","open_questions"];
  def with_sources: ["team_docs","abilities","interfaces","depends_on"];
  def word_count: [scan("\\S+")] | length;
  def kebab: type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$");
  def as_obj: if type == "object" then . else {} end;
  def items($where): (if type == "array" then . else [] end) | to_entries
    | map({where: "\($where)[\(.key)]", e: (.value | as_obj)});
  def must_be_list($where): select(. != null and type != "array") | "E \($where) must be a list: \($where)";
  def must_be_map($where): select(. != null and type != "object") | "E \($where) must be a map: \($where)";
  def id_findings: .[] | select(.e.id | kebab | not) | "E bad diagram id: \(.where): \(.e.id)";
  def dup_findings: . as $l | to_entries[]
    | select(.key as $k | .value.e.id as $id | ($id | type) == "string" and ($l[:$k] | map(.e.id) | index($id)))
    | "E duplicate diagram id: \(.value.where): \(.value.e.id)";
  def entry_findings($refs_required; $label_required): .where as $w | .e as $e
    | (if $refs_required and (($e.refs | type) != "array" or ($e.refs | length) == 0)
       then "E diagram entry without refs: \($w)" else empty end),
      ($e.refs | must_be_list("\($w).refs")),
      ($e.refs | arrays | .[] | select((type == "string" and valid_ref) | not) | "E bad ref form: \($w): \(.)"),
      (if $label_required and (($e.label | type) != "string" or ($e.label | length) == 0)
       then "E diagram entry without label: \($w)" else empty end),
      ($e.label | strings | select(length > 40) | "W warning: label has \(length) characters: \($w)");
  def node_count_warning($where; $count): if $count > 30 then "W warning: \($where) has \($count) nodes" else empty end;
  def diagram_findings:
    (.flow | as_obj) as $flow
    | (.flow | must_be_map("diagrams.flow")),
      (.architecture | must_be_map("diagrams.architecture")),
      ($flow.parts | must_be_list("diagrams.flow.parts")),
      ($flow.callers | must_be_list("diagrams.flow.callers")),
      ($flow.dependencies | must_be_list("diagrams.flow.dependencies")),
      ($flow.edges | must_be_list("diagrams.flow.edges")),
      (.sequences | must_be_list("diagrams.sequences")),
      (.states | must_be_list("diagrams.states")),
      ((.architecture | as_obj) as $arch_shape
       | ($arch_shape.layers | must_be_list("diagrams.architecture.layers")),
         ($arch_shape.implements | must_be_list("diagrams.architecture.implements")),
         ($arch_shape.layers | items("diagrams.architecture.layers")[]
          | .where as $w | .e.components | must_be_list("\($w).components"))),
      ((.sequences | items("diagrams.sequences")[]) | .where as $w | .e.steps | must_be_list("\($w).steps")),
      ((.states | items("diagrams.states")[]) | .where as $w | .e.transitions | must_be_list("\($w).transitions")),
      ($flow.parts | items("diagrams.flow.parts")) as $parts
    | ($flow.callers | items("diagrams.flow.callers")) as $callers
    | ($flow.dependencies | items("diagrams.flow.dependencies")) as $dependencies
    | ($parts + $callers + $dependencies) as $nodes
    | ($nodes | map(.e.id)) as $node_ids
    | ($parts | map(.e.id)) as $part_ids
    | ($nodes | id_findings), ($nodes | dup_findings),
      ($parts[] | entry_findings(true; true)),
      (($callers + $dependencies)[] | entry_findings(false; true)),
      ($flow.edges | items("diagrams.flow.edges")[] | . as $edge | .e as $e
        | ([$e.from, $e.to][] | select(. as $n | $node_ids | index($n) | not)
            | "E edge names an unknown id: \($edge.where): \(.)"),
          (if ([$e.from, $e.to] | all(. as $n | $node_ids | index($n) != null))
              and ([$e.from, $e.to] | any(. as $n | $part_ids | index($n) != null) | not)
           then "E edge touches no part: \($edge.where)" else empty end),
          ($edge | entry_findings(true; false))),
      node_count_warning("diagrams.flow"; $nodes | length),
      ((.sequences | items("diagrams.sequences")) as $sequences
       | ($sequences | id_findings), ($sequences | dup_findings),
         ($sequences[] | . as $seq | ($seq.e.steps | items("\($seq.where).steps")) as $steps
          | (if ($steps | length) == 0 then "E sequence without steps: \($seq.where)" else empty end),
            ($steps[] | entry_findings(true; true)),
            node_count_warning($seq.where; [$steps[].e | .from, .to | strings] | unique | length))),
      ((.states | items("diagrams.states")) as $states
       | ($states | id_findings), ($states | dup_findings),
         ($states[] | . as $life | ($life.e.transitions | items("\($life.where).transitions")) as $transitions
          | ([$transitions[].e | .from, .to | strings] | unique) as $state_names
          | (if ($transitions | length) == 0 then "E state lifecycle without transitions: \($life.where)" else empty end),
            (if ($life.e | has("initial")) and ($state_names | index($life.e.initial) | not)
             then "E initial names no state: \($life.where): \($life.e.initial)" else empty end),
            ($transitions[] | entry_findings(true; false)),
            node_count_warning($life.where; $state_names | length))),
      ((.architecture | as_obj) as $arch
       | ($arch.layers | items("diagrams.architecture.layers")) as $layers
       | ([$layers[] | . as $layer | $layer.e.components | items("\($layer.where).components")[]]) as $components
       | (if ($arch | has("style")) and (["clean","hexagonal","layered"] | index($arch.style) | not)
          then "E bad architecture style: diagrams.architecture.style: \($arch.style)" else empty end),
         ($components | id_findings), ($components | dup_findings),
         ($components[] | entry_findings(true; true)),
         ($components[] | select(.e.kind as $kind | ["entity","use_case","port","adapter","controller","other"] | index($kind) | not)
           | "E bad component kind: \(.where): \(.e.kind)"),
         ($arch.implements | items("diagrams.architecture.implements")[] | . as $pair
           | (if ([$components[] | select(.e.kind == "adapter") | .e.id] | index($pair.e.adapter))
                and ([$components[] | select(.e.kind == "port") | .e.id] | index($pair.e.port))
              then empty else "E implements needs an adapter and a port: \($pair.where)" end)),
         node_count_warning("diagrams.architecture"; $components | length));
  . as $c
  | ($c.planned // [] | if type == "array" then map(.id // empty) else [] end) as $planned_ids
  | (
    (if ($c.summary | type) == "string" and ($c.summary | length) > 0 then empty
     else "E missing or empty summary: summary" end),
    (if ($c.verified_commit | hex_or_empty) then empty
     else "E verified_commit must be a quoted hex string or empty: verified_commit" end),
    (if ($c.sections | type) != "object" then "E sections must be a map: sections"
     else
       (section_keys[] | select(. as $k | $c.sections | has($k) | not) | "E missing section: sections.\(.)"),
       ($c.sections | keys[] | select(. as $k | section_keys | index($k) | not) | "E unknown section: sections.\(.)"),
       (with_sources[] as $k | select($c.sections | has($k))
         | select(($c.sections[$k].sources | type) != "array")
         | "E missing sources: sections.\($k).sources"),
       (section_keys[] as $k | select($c.sections | has($k)) | select($k != "team_docs")
         | ($c.sections[$k].items // []) | to_entries[]
         | . as $e | $e.value as $item
         | "\($k)[\($e.key)]" as $where
         | (if ($item.text | type) == "string" and ($item.text | length) > 0 then empty
            else "E item without text: \($where)" end),
           (if ($item.refs | type) == "array" and ($item.refs | length) > 0 then empty
            else "E item without refs: \($where)" end),
           (($item.refs // []) | if type == "array" then .[] else empty end
             | select((type == "string" and valid_ref) | not) | "E bad ref form: \($where): \(.)"),
           (if ($item | has("mapped_commit")) and (($item.mapped_commit | type) != "string" or ($item.mapped_commit | test("^[0-9a-f]{4,64}$") | not))
            then "E mapped_commit must be a quoted hex string: \($where)" else empty end),
           (if ($item | has("planned")) | not then empty
            elif ($item.planned | type) != "string" or ($item.planned | test("^[a-z0-9]+(-[a-z0-9]+)*$") | not)
            then "E planned link must be a kebab-case id: \($where): \($item.planned)"
            elif ($planned_ids | index($item.planned) | not)
            then "W warning: \($where) links missing plan item \($item.planned)" else empty end),
           (if ($item.text | type) == "string" and ($item.text | word_count) > 25
            then "W warning: \($where) has \($item.text | word_count) words" else empty end))
     end),
    (if ($c.planned // []) | type == "array" then
       ($c.planned // []) | to_entries[] | . as $e | "planned[\($e.key)]" as $where
       | (if ($e.value.id | type) == "string" and ($e.value.id | test("^[a-z0-9]+(-[a-z0-9]+)*$")) then empty
          else "E plan id not kebab case: \($where): \($e.value.id)" end),
         (if ($e.value.title | type) == "string" then empty else "E plan item without title: \($where)" end),
         (if ($e.value.why | type) == "string" then empty else "E plan item without why: \($where)" end),
         (($e.value.refs // []) | .[]? | select((type == "string" and valid_ref) | not) | "E bad ref form: \($where): \(.)")
     else "E planned must be a list: planned" end),
    (if ($c.diagrams // {} | type) == "object" then ($c.diagrams // {} | diagram_findings)
     else "E diagrams must be a map: diagrams" end)
  )' 2>&1)" || { echo "contract-validate.sh: cannot check $contract_file: $findings" >&2; exit 2; }

broken=0
while IFS= read -r finding; do
  [ -n "$finding" ] || continue
  case "$finding" in
    "W "*) echo "${finding#W }" >&2 ;;
    "E "*) echo "contract-validate.sh: ${finding#E }" >&2; broken=1 ;;
  esac
done <<< "$findings"
exit "$broken"
