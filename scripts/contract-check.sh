#!/usr/bin/env bash
# contract-check.sh <repo_dir> <contract_file>
# Compare a contract's verified_commit with the local ref origin/<base_branch>. No network call.
# Exit: 0 fresh, 1 stale, 2 error (stderr names the cause), 3 contract file missing.
set -euo pipefail

[ "$#" -ge 2 ] || { echo "usage: contract-check.sh <repo_dir> <contract_file>" >&2; exit 2; }
repo_dir="$1"
contract_file="$2"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/frontmatter.sh"
max_listed_files=10

fail() { echo "contract-check.sh: $1" >&2; exit 2; }
json_list() { jq -Rn '[inputs | select(length > 0)]' -c; }  # newline-separated stdin to one-line JSON
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"
[ -f "$contract_file" ] || { echo "contract-check.sh: no contract file: $contract_file" >&2; exit 3; }
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: $repo_dir"

base_branch="$(fm_get "$contract_file" base_branch)"
verified_commit="$(fm_get "$contract_file" verified_commit)"
[ -n "$base_branch" ] || fail "contract has no base_branch: $contract_file"
[ -n "$verified_commit" ] || fail "contract has no verified_commit: $contract_file"
[[ "$verified_commit" =~ ^[0-9a-fA-F]{4,64}$ ]] || fail "verified_commit is not a hex SHA: $verified_commit"
for list_key in pending ignore; do
  ! fm_has_block_list "$contract_file" "$list_key" || fail "$list_key must be a one-line JSON list, like $list_key: [\"tests/**\"]"
done
pending_json="$(fm_get "$contract_file" pending)"
pending_json="$(jq -c . <<<"${pending_json:-[]}" 2>/dev/null)" || fail "pending is not JSON: $contract_file"
ignore_json="$(fm_get "$contract_file" ignore)"
ignore_globs="$(jq -r 'if type == "array" and all(type == "string") then .[] else error("not a string array") end' <<<"${ignore_json:-[]}" 2>/dev/null)" || fail "ignore is not a JSON array of strings: $contract_file"

base_ref="origin/$base_branch"
git -C "$repo_dir" rev-parse --verify -q "$base_ref^{commit}" >/dev/null || fail "ref $base_ref does not exist; fetch it first"

# Contract body: "S<TAB>name<TAB>globs" per section, "A<TAB>path" per team-doc @ path, "D<TAB>line" per Depends on line.
sections="$(awk '
  { sub(/\r$/, "") }
  /^## / { name = substr($0, 4); sub(/[ \t]+$/, "", name); print "S\t" name "\t"; next }
  /^<!-- *sources:/ && name != "" {
    g = $0; sub(/^<!-- *sources: */, "", g); sub(/ *-->.*$/, "", g); gsub(/, */, ",", g)
    print "G\t" g; next }
  name == "Team docs" && /^- @/ { p = substr($0, 3); sub(/[ \t].*$/, "", p); print "A\t" p; next }
  name == "Depends on" && /^- / { print "D\t" substr($0, 3) }
' "$contract_file")"

# Parse once into arrays. The per-file loop below uses only shell builtins.
section_names=(); section_has_globs=(); section_is_stale=()
pair_section=(); pair_glob=()   # one entry per (section index, glob)
team_doc_paths=()
depends_lines=""
section_count=0
while IFS=$'\t' read -r kind first second; do
  case "$kind" in
    S) section_names[section_count]="$first"; section_has_globs[section_count]=0; section_is_stale[section_count]=0
       section_count=$((section_count + 1)) ;;
    G) [ -n "${first//[ ,]/}" ] || continue   # an empty sources comment claims nothing
       section_has_globs[section_count - 1]=1
       oldifs="$IFS"; IFS=","; set -f
       for glob in $first; do pair_section[${#pair_section[@]}]=$((section_count - 1)); pair_glob[${#pair_glob[@]}]="${glob//\*\*/*}"; done
       IFS="$oldifs"; set +f ;;
    A) team_doc_paths[${#team_doc_paths[@]}]="${first#@}" ;;
    D) depends_lines="$depends_lines$first"$'\n' ;;
  esac
done <<<"$sections"
ignore_list=()
while IFS= read -r glob; do
  [ -n "$glob" ] && ignore_list[${#ignore_list[@]}]="${glob//\*\*/*}"
done <<<"$ignore_globs"
pair_count=${#pair_glob[@]}

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

if ! git -C "$repo_dir" merge-base --is-ancestor "$verified_commit" "$base_ref" 2>/dev/null; then
  behind="$(git -C "$repo_dir" rev-list --count "$base_ref")"
  is_stale=1
  for ((section_index = 0; section_index < section_count; section_index++)); do
    if [ "${section_names[section_index]}" = "Team docs" ] || [ "${section_has_globs[section_index]}" = 1 ]; then
      mark_section_index_stale "$section_index"
    fi
  done
else
  behind="$(git -C "$repo_dir" rev-list --count "$verified_commit..$base_ref")"
  while IFS= read -r -d '' changed_file; do
    ignored=0
    for glob in ${ignore_list[@]+"${ignore_list[@]}"}; do
      # shellcheck disable=SC2254
      case "$changed_file" in $glob) ignored=1; break ;; esac
    done
    [ "$ignored" = 0 ] || continue
    claimed=0
    for team_doc_path in ${team_doc_paths[@]+"${team_doc_paths[@]}"}; do
      if [ "$team_doc_path" = "$changed_file" ]; then
        claimed=1
        for ((section_index = 0; section_index < section_count; section_index++)); do
          [ "${section_names[section_index]}" != "Team docs" ] || mark_section_index_stale "$section_index"
        done
      fi
    done
    for ((pair_index = 0; pair_index < pair_count; pair_index++)); do
      glob="${pair_glob[pair_index]}"
      # shellcheck disable=SC2254
      case "$changed_file" in $glob) claimed=1; mark_section_index_stale "${pair_section[pair_index]}" ;; esac
    done
    if [ "$claimed" = 0 ]; then
      unclaimed_count=$((unclaimed_count + 1))
      [ "$unclaimed_count" -gt "$max_listed_files" ] || unclaimed="$unclaimed$changed_file"$'\n'
    fi
  done < <(git -C "$repo_dir" diff --name-only -z "$verified_commit" "$base_ref")
fi

# Depends on: "<app> (mapped): ... commit <sha>"
org_dir="$(cd "$(dirname "$contract_file")" && pwd -P)"
initiation_file=""
while [ "$org_dir" != "/" ]; do
  if [ -f "$org_dir/handover_handler__initiation.md" ]; then initiation_file="$org_dir/handover_handler__initiation.md"; break; fi
  org_dir="$(dirname "$org_dir")"
done
dependency_pattern='^(.+) \(mapped\):.*commit ([0-9a-f]+)'
while IFS= read -r depends_line; do
  [ -n "$depends_line" ] || continue
  [[ "$depends_line" =~ $dependency_pattern ]] || continue
  app_name="${BASH_REMATCH[1]}"; recorded_commit="${BASH_REMATCH[2]}"
  current_commit=""
  if [ -n "$initiation_file" ]; then
    mapping_rows="$(bash "$plugin_root/scripts/handover/parse-mapping.sh" "$initiation_file")" || fail "cannot read the service mapping in $initiation_file"
    subpath="$(awk -F'|' -v app="$app_name" '$1 == app { print $3; exit }' <<<"$mapping_rows")"
    dependency_contract="$org_dir/$subpath/$app_name.md"
    if [ -n "$subpath" ] && [ -f "$dependency_contract" ]; then current_commit="$(fm_get "$dependency_contract" verified_commit)"; fi
  fi
  case "$current_commit" in
    ?*) case "$current_commit" in "$recorded_commit"*) continue ;; esac ;;
  esac
  stale_dependencies="$stale_dependencies$app_name"$'\n'
  mark_section_stale "Depends on"
done <<<"$depends_lines"

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
