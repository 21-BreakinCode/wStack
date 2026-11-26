#!/usr/bin/env bash
# contract-ref-shift.sh <repo_dir> <contract.yaml> <old_commit> <new_commit> [--mapping-from <path>]
# List the refs of the contract whose file changed.
# Reads the same refs as contract-refs.sh: all sections, planned, and diagrams.
# A local ref is compared between <old_commit> and <new_commit> in repo_dir.
# A cross-repo ref `<owner>/<repo>@<commit>:path:lines` is compared between its commit and HEAD of the local clone,
# which is found as contract-refs.sh finds it, with the same --mapping-from. This script does not fetch.
# Output: `changed: <ref>` when the file changed, `shift: <ref> -> <owner>/<repo>@<HEAD>:path:lines` when a
# cross-repo file did not change, `unchecked: <ref>: <reason>`, then a `refs:` count line.
# Exit: 0 done, 2 error.
set -euo pipefail
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/contract-refs-read.sh"

fail() { echo "contract-ref-shift: $1" >&2; exit 2; }
{ [ $# -eq 4 ] || { [ $# -eq 6 ] && [ "$5" = --mapping-from ] && [ -n "$6" ]; }; } \
  && [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] \
  || fail "usage: contract-ref-shift.sh <repo_dir> <contract.yaml> <old_commit> <new_commit> [--mapping-from <path>]"
repo_dir="$1"; contract_file="$2"; old_commit="$3"; new_commit="$4"; mapping_from="${6:-$2}"
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"
command -v yq >/dev/null 2>&1 || fail "yq is required but not installed"
[ -f "$contract_file" ] || fail "no contract file: $contract_file"
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: $repo_dir"
for commit in "$old_commit" "$new_commit"; do
  git -C "$repo_dir" cat-file -e "$commit^{commit}" 2>/dev/null || fail "unknown commit: $commit"
done
contract_json="$(yq -o=json '.' "$contract_file")" || fail "contract is not valid YAML: $contract_file"
changed_files="$(git -C "$repo_dir" -c core.quotepath=off diff --name-only --no-renames "$old_commit" "$new_commit")"
load_clone_mapping "$mapping_from"

changed=0; shifted=0; unchanged=0; unchecked=0
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if [[ "$ref" =~ $cross_form ]]; then
    slug="${ref%%@*}"; rest="${ref#*@}"; ref_commit="${rest%%:*}"; rest="${rest#*:}"
    clone="$(clone_for "$slug")"
    if [ -z "$clone" ]; then echo "unchecked: $ref: no local clone of $slug"; unchecked=$((unchecked + 1)); continue; fi
    if ! full_commit="$(git -C "$clone" rev-parse --verify -q "$ref_commit^{commit}")"; then
      echo "unchecked: $ref: unknown commit"; unchecked=$((unchecked + 1)); continue
    fi
    clone_head="$(git -C "$clone" rev-parse HEAD)"
    if [ "$full_commit" = "$clone_head" ]; then
      unchanged=$((unchanged + 1))
    elif git -C "$clone" --literal-pathspecs diff --quiet "$full_commit" "$clone_head" -- "${rest%:*}"; then
      echo "shift: $ref -> $slug@$clone_head:$rest"; shifted=$((shifted + 1))
    else
      echo "changed: $ref"; changed=$((changed + 1))
    fi
  elif grep -qxF -- "${ref%:*}" <<<"$changed_files"; then
    echo "changed: $ref"; changed=$((changed + 1))
  else
    unchanged=$((unchanged + 1))
  fi
done < <(contract_ref_lines "$contract_json")

echo "refs: $changed changed, $shifted shifted, $unchanged unchanged, $unchecked unchecked"
