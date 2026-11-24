#!/usr/bin/env bash
# contract-refs.sh <repo_dir> <contract.yaml> [--mapping-from <path>]
# Prove that every ref in the contract (all sections and planned) exists at its commit.
# Local ref `path:lines` is read at verified_commit in repo_dir.
# Cross-repo ref `<owner>/<repo>@<commit>:path:lines` is read in the local clone of that repo.
# Output: `bad: <ref>: <reason>` and `unchecked: <ref>: <reason>` lines, then a `refs:` count line.
# --mapping-from <path> finds the initiation file up from the nearest existing folder of <path>,
# not from the contract's folder. A draft in a task folder needs it to find the other clones.
# Exit: 0 no bad ref, 1 a bad ref, 2 error.
set -euo pipefail

usage_line="usage: contract-refs.sh <repo_dir> <contract.yaml> [--mapping-from <path>]"
{ [ $# -eq 2 ] || { [ $# -eq 4 ] && [ "$3" = --mapping-from ] && [ -n "$4" ]; }; } && [ -n "$1" ] && [ -n "$2" ] \
  || { echo "$usage_line" >&2; exit 2; }
repo_dir="$1"
contract_file="$2"
mapping_from="${4:-$contract_file}"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/frontmatter.sh"

fail() { echo "contract-refs.sh: $1" >&2; exit 2; }
expand_home() { local path="${1//\$HOME/$HOME}"; echo "${path/#\~/$HOME}"; }
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"
command -v yq >/dev/null 2>&1 || fail "yq is required but not installed"
[ -f "$contract_file" ] || fail "no contract file: $contract_file"
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: $repo_dir"

contract_json="$(yq -o=json '.' "$contract_file")" || fail "contract is not valid YAML: $contract_file"
verified_commit="$(jq -r '.verified_commit // "" | tostring' <<<"$contract_json")"
[ -n "$verified_commit" ] || fail "contract has no verified_commit: $contract_file"

# Find the initiation file up the folder tree; it holds workspace_root and the Service Mapping.
org_dir="$(dirname "$mapping_from")"
while [ ! -d "$org_dir" ]; do org_dir="$(dirname "$org_dir")"; done  # a new service's folder may not exist yet
org_dir="$(cd "$org_dir" && pwd -P)"
initiation_file=""
while [ "$org_dir" != "/" ]; do
  if [ -f "$org_dir/handover_handler__initiation.md" ]; then initiation_file="$org_dir/handover_handler__initiation.md"; break; fi
  org_dir="$(dirname "$org_dir")"
done
mapping_rows=""; workspace_root=""
if [ -n "$initiation_file" ]; then
  mapping_rows="$(bash "$plugin_root/scripts/handover/parse-mapping.sh" "$initiation_file")" || fail "cannot read the service mapping in $initiation_file"
  workspace_root="$(expand_home "$(fm_get "$initiation_file" workspace_root)")"
fi

clone_for() {  # <owner/repo>: print the local clone path, or nothing
  local slug="$1" mapped_repo_path remote_url
  while IFS='|' read -r _ mapped_repo_path _; do
    [ -n "$mapped_repo_path" ] || continue
    mapped_repo_path="$(expand_home "$mapped_repo_path")"
    remote_url="$(git -C "$mapped_repo_path" remote get-url origin 2>/dev/null)" || continue
    case "$remote_url" in *[/:]"$slug" | *[/:]"$slug.git") echo "$mapped_repo_path"; return ;; esac
  done <<<"$mapping_rows"
  if [ -n "$workspace_root" ] && [ -d "$workspace_root/${slug#*/}/.git" ]; then echo "$workspace_root/${slug#*/}"; fi
}

lines_form='^[0-9]+(-[0-9]+)?(, *[0-9]+(-[0-9]+)?)*$'
cross_form='^[^/@:]+/[^/@:]+@[0-9a-f]+:'
checked=0; bad=0; unchecked=0

while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  clone="$repo_dir"; commit="$verified_commit"; rest="$ref"; slug=""
  if [[ "$ref" =~ $cross_form ]]; then
    slug="${ref%%@*}"; rest="${ref#*@}"; commit="${rest%%:*}"; rest="${rest#*:}"
  fi
  path="${rest%:*}"; lines="${rest##*:}"
  if [ "$path" = "$rest" ] || [ -z "$path" ] || ! [[ "$lines" =~ $lines_form ]]; then
    echo "bad: $ref: bad form"; bad=$((bad + 1)); continue
  fi
  if [ -n "$slug" ]; then
    clone="$(clone_for "$slug")"
    if [ -z "$clone" ]; then echo "unchecked: $ref: no local clone of $slug"; unchecked=$((unchecked + 1)); continue; fi
  fi
  if ! git -C "$clone" cat-file -e "$commit^{commit}" 2>/dev/null; then
    if [ -n "$slug" ]; then echo "unchecked: $ref: commit $commit is not in $clone"; unchecked=$((unchecked + 1))
    else echo "bad: $ref: commit $commit is not in $clone"; bad=$((bad + 1)); fi
    continue
  fi
  if ! git -C "$clone" cat-file -e "$commit:$path" 2>/dev/null; then
    echo "bad: $ref: no file $path at $commit"; bad=$((bad + 1)); continue
  fi
  line_count="$(git -C "$clone" show "$commit:$path" 2>/dev/null | awk 'END { print NR }')"
  past_end=""
  for part in ${lines//,/ }; do
    first="${part%-*}"; last="${part#*-}"
    if [ "$first" -lt 1 ] || [ "$first" -gt "$last" ] || [ "$last" -gt "$line_count" ]; then past_end="$part"; break; fi
  done
  if [ -n "$past_end" ]; then
    echo "bad: $ref: lines $past_end are outside $path ($line_count lines at $commit)"; bad=$((bad + 1)); continue
  fi
  checked=$((checked + 1))
done < <(jq -r '[(.sections // {} | .[] | objects | .items // [] | .[] | objects | .refs // [] | .[]),
                 (.planned // [] | .[] | objects | .refs // [] | .[])] | .[] | strings' <<<"$contract_json")

echo "refs: $checked checked, $bad bad, $unchecked unchecked"
[ "$bad" = 0 ]
