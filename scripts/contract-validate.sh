#!/usr/bin/env bash
# Usage: contract-validate.sh <contract.yaml>
# Exit 0 valid, 1 broken rule (one line per break on stderr), 2 unusable input or yq.
set -euo pipefail

contract_file="${1:-}"
[ -n "$contract_file" ] || { echo "usage: contract-validate.sh <contract.yaml>" >&2; exit 2; }
[ -f "$contract_file" ] || { echo "contract-validate.sh: no such file: $contract_file" >&2; exit 2; }

yq_version="$(yq --version 2>&1 || true)"
case "$yq_version" in
  *mikefarah*" v4."*) ;;
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
           (if ($item | has("planned")) and (($item.planned | type) != "string" or ($planned_ids | index($item.planned) | not))
            then "E planned link to a missing id: \($where): \($item.planned)" else empty end),
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
     else "E planned must be a list: planned" end)
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
