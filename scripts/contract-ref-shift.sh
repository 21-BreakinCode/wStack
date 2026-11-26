#!/usr/bin/env bash
# contract-ref-shift.sh <repo_dir> <contract.yaml> <old_commit> <new_commit>
# List the refs of the contract whose file changed between two commits.
# Reads the same refs as contract-refs.sh: all sections, planned, and diagrams.
# Output: `changed: <ref>` per local ref, `unchecked: <ref>: cross-repo` per cross-repo ref, then a `refs:` count line.
# Exit: 0 done, 2 error.
set -euo pipefail

fail() { echo "contract-ref-shift: $1" >&2; exit 2; }
[ $# -eq 4 ] && [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] \
  || fail "usage: contract-ref-shift.sh <repo_dir> <contract.yaml> <old_commit> <new_commit>"
repo_dir="$1"; contract_file="$2"; old_commit="$3"; new_commit="$4"
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"
command -v yq >/dev/null 2>&1 || fail "yq is required but not installed"
[ -f "$contract_file" ] || fail "no contract file: $contract_file"
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: $repo_dir"
for commit in "$old_commit" "$new_commit"; do
  git -C "$repo_dir" cat-file -e "$commit^{commit}" 2>/dev/null || fail "unknown commit: $commit"
done
contract_json="$(yq -o=json '.' "$contract_file")" || fail "contract is not valid YAML: $contract_file"
changed_files="$(git -C "$repo_dir" diff --name-only --no-renames "$old_commit" "$new_commit")"

cross_form='^[^/@:]+/[^/@:]+@[0-9a-f]+:'
changed=0; unchanged=0; unchecked=0
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if [[ "$ref" =~ $cross_form ]]; then
    echo "unchecked: $ref: cross-repo"; unchecked=$((unchecked + 1)); continue
  fi
  if printf '%s\n' "$changed_files" | grep -qxF -- "${ref%:*}"; then
    echo "changed: $ref"; changed=$((changed + 1))
  else
    unchanged=$((unchanged + 1))
  fi
done < <(jq -r '[(.sections // {} | .[] | objects | .items // [] | .[] | objects | .refs // [] | .[]),
                 (.planned // [] | .[] | objects | .refs // [] | .[]),
                 (.diagrams // {} | .. | objects | select(has("refs")) | .refs | arrays | .[])] | .[] | strings' <<<"$contract_json")

echo "refs: $changed changed, $unchanged unchanged, $unchecked unchecked"
