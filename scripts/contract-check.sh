#!/usr/bin/env bash
# contract-check.sh <repo_dir> <contract.yaml> [--coverage]
# Compare a contract's verified_commit with the local ref origin/<base_branch>. No network call.
# --coverage diffs the empty tree against origin/<base_branch>, so every tracked file counts as changed.
# It proves the sources globs claim every file. In this mode no section and no dependency is marked stale,
# and the exit is 0 when every file is claimed or ignored. The behind count stays.
# Exit: 0 fresh, 1 stale, 2 error (stderr names the cause), 3 contract file missing.
set -euo pipefail

usage_line="usage: contract-check.sh <repo_dir> <contract.yaml> [--coverage]"
[ "${1:-}" ] && [ "${2:-}" ] || { echo "$usage_line" >&2; exit 2; }
[ $# -le 2 ] || { [ $# -eq 3 ] && [ "$3" = --coverage ]; } || { echo "$usage_line" >&2; exit 2; }
repo_dir="$1"
contract_file="$2"
coverage_mode=0; [ "${3:-}" != --coverage ] || coverage_mode=1
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/frontmatter.sh"
max_listed_files=10

fail() { echo "contract-check.sh: $1" >&2; exit 2; }
json_list() { jq -Rn '[inputs | select(length > 0)]' -c; }  # newline-separated stdin to one-line JSON
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"
command -v yq >/dev/null 2>&1 || fail "yq is required but not installed"
[ -f "$contract_file" ] || { echo "contract-check.sh: no contract file: $contract_file" >&2; exit 3; }
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: $repo_dir"

contract_json="$(yq -o=json '.' "$contract_file")" || fail "contract is not valid YAML: $contract_file"
# One line per fact: "E<TAB>error", "B<TAB>base_branch", "V<TAB>verified_commit", "P<TAB>pending JSON",
# "I<TAB>ignore glob", "S<TAB>section key", "G<TAB>glob" for the section above, "D<TAB>app<TAB>mapped_commit".
contract_lines="$(jq -r '
  def is_string_list: type == "array" and all(.[]; type == "string");
  if type != "object" then "E\tcontract is not a YAML map"
  elif (.base_branch // "") == "" then "E\tcontract has no base_branch"
  elif (.verified_commit // "") == "" then "E\tcontract has no verified_commit"
  elif (.verified_commit | type) != "string" then "E\tverified_commit must be a quoted string"
  elif (.ignore // [] | is_string_list | not) then "E\tignore is not a list of strings"
  elif (.pending // [] | type) != "array" then "E\tpending is not a list"
  elif (.sections | type) != "object" then "E\tcontract has no sections map"
  elif any(.sections[]; (objects | .sources // []) | is_string_list | not) then "E\tsources is not a list of strings"
  else
    "B\t\(.base_branch)", "V\t\(.verified_commit)", "P\t\(.pending // [] | tojson)",
    (.ignore // [] | .[] | select(length > 0) | "I\t\(.)"),
    (.sections | to_entries[] | "S\t\(.key)", (.value | objects | .sources // [] | .[] | select(length > 0) | "G\t\(.)")),
    (.sections.depends_on | objects | .items // [] | .[] | objects | select((.app // "") != "" and (.mapped_commit // "") != "")
      | "D\t\(.app)\t\(.mapped_commit | tostring)")
  end' <<<"$contract_json")" || fail "cannot read the contract: $contract_file"
case "$contract_lines" in E$'\t'*) fail "${contract_lines#E$'\t'}: $contract_file" ;; esac

# Parse once into arrays. The per-file loop below uses only shell builtins.
section_names=(); section_has_globs=(); section_is_stale=()
pair_section=(); pair_glob=()   # one entry per (section index, glob)
ignore_list=()
dependency_lines=""
section_count=0
while IFS=$'\t' read -r kind first second; do
  case "$kind" in
    B) base_branch="$first" ;;
    V) verified_commit="$first" ;;
    P) pending_json="$first" ;;
    I) ignore_list[${#ignore_list[@]}]="${first//\*\*/*}" ;;
    S) section_names[section_count]="$first"; section_has_globs[section_count]=0; section_is_stale[section_count]=0
       section_count=$((section_count + 1)) ;;
    G) section_has_globs[section_count - 1]=1
       pair_section[${#pair_section[@]}]=$((section_count - 1)); pair_glob[${#pair_glob[@]}]="${first//\*\*/*}" ;;
    D) dependency_lines="$dependency_lines$first"$'\t'"$second"$'\n' ;;
  esac
done <<<"$contract_lines"
pair_count=${#pair_glob[@]}

[[ "$verified_commit" =~ ^[0-9a-fA-F]{4,64}$ ]] || fail "verified_commit is not a hex SHA: $verified_commit"

base_ref="origin/$base_branch"
git -C "$repo_dir" rev-parse --verify -q "$base_ref^{commit}" >/dev/null || fail "ref $base_ref does not exist; fetch it first"

stale_sections=""
stale_dependencies=""
unclaimed=""
unclaimed_count=0
behind=0
is_stale=0

mark_section_stale() {  # <name>
  case $'\n'"$stale_sections" in *$'\n'"$1"$'\n'*) return ;; esac
  stale_sections="$stale_sections$1"$'\n'
}
mark_section_index_stale() {  # <index>
  [ "${section_is_stale[$1]}" = 0 ] || return 0
  section_is_stale[$1]=1
  mark_section_stale "${section_names[$1]}"
}

diff_from="$verified_commit"
if ! git -C "$repo_dir" merge-base --is-ancestor "$verified_commit" "$base_ref" 2>/dev/null; then
  behind="$(git -C "$repo_dir" rev-list --count "$base_ref")"
  if [ "$coverage_mode" = 0 ]; then
    is_stale=1
    for ((section_index = 0; section_index < section_count; section_index++)); do
      [ "${section_has_globs[section_index]}" = 0 ] || mark_section_index_stale "$section_index"
    done
  fi
  diff_from=""
else
  behind="$(git -C "$repo_dir" rev-list --count "$verified_commit..$base_ref")"
fi
[ "$coverage_mode" = 0 ] || diff_from="$(git -C "$repo_dir" hash-object -t tree /dev/null)"
if [ -n "$diff_from" ]; then
  while IFS= read -r -d '' changed_file; do
    ignored=0
    for glob in ${ignore_list[@]+"${ignore_list[@]}"}; do
      # shellcheck disable=SC2254
      case "$changed_file" in $glob) ignored=1; break ;; esac
    done
    [ "$ignored" = 0 ] || continue
    claimed=0
    for ((pair_index = 0; pair_index < pair_count; pair_index++)); do
      glob="${pair_glob[pair_index]}"
      # shellcheck disable=SC2254
      case "$changed_file" in $glob)
        claimed=1
        [ "$coverage_mode" = 1 ] || mark_section_index_stale "${pair_section[pair_index]}" ;;
      esac
    done
    if [ "$claimed" = 0 ]; then
      unclaimed_count=$((unclaimed_count + 1))
      [ "$unclaimed_count" -gt "$max_listed_files" ] || unclaimed="$unclaimed$changed_file"$'\n'
    fi
  done < <(git -C "$repo_dir" diff --name-only -z "$diff_from" "$base_ref")
fi

# A depends_on item with app and mapped_commit compares with the verified_commit of that app's contract.
# The contract is <app>.contract.yaml, or <app>.md from before the YAML format. No contract means unknown, not stale.
# --coverage reports only unclaimed files, so it skips the dependencies.
[ "$coverage_mode" = 0 ] || dependency_lines=""
org_dir="$(cd "$(dirname "$contract_file")" && pwd -P)"
initiation_file=""
while [ "$org_dir" != "/" ]; do
  if [ -f "$org_dir/handover_handler__initiation.md" ]; then initiation_file="$org_dir/handover_handler__initiation.md"; break; fi
  org_dir="$(dirname "$org_dir")"
done
while IFS=$'\t' read -r app_name mapped_commit; do
  [ -n "$app_name" ] && [ -n "$initiation_file" ] || continue
  mapping_rows="$(bash "$plugin_root/scripts/handover/parse-mapping.sh" "$initiation_file")" || fail "cannot read the service mapping in $initiation_file"
  subpath="$(awk -F'|' -v app="$app_name" '$1 == app { print $3; exit }' <<<"$mapping_rows")"
  [ -n "$subpath" ] || continue
  dependency_stem="$org_dir/$subpath/$app_name"
  if [ -f "$dependency_stem.contract.yaml" ]; then
    # An unreadable dependency contract leaves current_commit empty, so the dependency reads stale.
    current_commit="$(yq '.verified_commit // ""' "$dependency_stem.contract.yaml" 2>/dev/null)" || current_commit=""
  elif [ -f "$dependency_stem.md" ]; then
    current_commit="$(fm_get "$dependency_stem.md" verified_commit)"
  else
    continue
  fi
  case "$current_commit" in "$mapped_commit"*) continue ;; esac
  stale_dependencies="$stale_dependencies$app_name"$'\n'
  mark_section_stale depends_on
done <<<"$dependency_lines"

if [ -n "$stale_sections" ] || [ -n "$stale_dependencies" ] || [ "$unclaimed_count" -gt 0 ]; then is_stale=1; fi
status=fresh; [ "$is_stale" = 0 ] || status=stale

echo "status: $status"
echo "base: $base_ref"
echo "behind: $behind"
echo "stale_sections: $(printf '%s' "$stale_sections" | json_list)"
echo "stale_dependencies: $(printf '%s' "$stale_dependencies" | json_list)"
echo "unclaimed_files: $(printf '%s' "$unclaimed" | json_list)"
echo "unclaimed_count: $unclaimed_count"
echo "pending: $pending_json"
[ "$is_stale" = 0 ]
