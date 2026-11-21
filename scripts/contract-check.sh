#!/usr/bin/env bash
# contract-check.sh <repo_dir> <contract_file>
# Compare a contract's verified_commit with the local ref origin/<base_branch>. No network call.
# Exit: 0 fresh, 1 stale, 2 error (stderr names the cause), 3 contract file missing.
set -euo pipefail

repo_dir="${1:?usage: contract-check.sh <repo_dir> <contract_file>}"
contract_file="${2:?usage: contract-check.sh <repo_dir> <contract_file>}"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/frontmatter.sh"
max_listed_files=10

fail() { echo "contract-check.sh: $1" >&2; exit 2; }
json_list() { jq -Rn '[inputs | select(length > 0)]' -c; }  # newline-separated stdin to one-line JSON
matches_any_glob() {  # <file> <newline-separated globs>
  local file="$1" glob
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    glob="${glob//\*\*/*}"
    # shellcheck disable=SC2254
    case "$file" in $glob) return 0 ;; esac
  done <<<"$2"
  return 1
}

[ -f "$contract_file" ] || { echo "contract-check.sh: no contract file: $contract_file" >&2; exit 3; }
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: $repo_dir"

base_branch="$(fm_get "$contract_file" base_branch)"
verified_commit="$(fm_get "$contract_file" verified_commit)"
[ -n "$base_branch" ] || fail "contract has no base_branch: $contract_file"
[ -n "$verified_commit" ] || fail "contract has no verified_commit: $contract_file"
pending_json="$(fm_get "$contract_file" pending)"
pending_json="$(jq -c . <<<"${pending_json:-[]}" 2>/dev/null)" || fail "pending is not JSON: $contract_file"
ignore_globs="$(jq -r '.[]' <<<"$(fm_get "$contract_file" ignore)" 2>/dev/null || true)"

base_ref="origin/$base_branch"
git -C "$repo_dir" rev-parse --verify -q "$base_ref^{commit}" >/dev/null || fail "ref $base_ref does not exist; fetch it first"

# Contract body: "S<TAB>name<TAB>globs" per section, "A<TAB>path" per team-doc @ path, "D<TAB>line" per Depends on line.
sections="$(awk '
  /^## / { name = substr($0, 4); sub(/[ \t]+$/, "", name); print "S\t" name "\t"; next }
  /^<!-- *sources:/ && name != "" {
    g = $0; sub(/^<!-- *sources: */, "", g); sub(/ *-->.*$/, "", g); gsub(/, */, ",", g)
    print "G\t" g; next }
  name == "Team docs" && /^- @/ { p = substr($0, 3); sub(/[ \t].*$/, "", p); print "A\t" p; next }
  name == "Depends on" && /^- / { print "D\t" substr($0, 3) }
' "$contract_file")"

section_names=""   # newline-separated, in file order
section_globs=""   # one line per section, globs comma-separated, parallel to section_names
team_doc_paths=""
depends_lines=""
while IFS=$'\t' read -r kind first second; do
  case "$kind" in
    S) section_names="$section_names$first"$'\n'; section_globs="$section_globs"$'\n' ;;
    G) section_globs="${section_globs%$'\n'}$first"$'\n' ;;
    A) team_doc_paths="$team_doc_paths$first"$'\n' ;;
    D) depends_lines="$depends_lines$first"$'\n' ;;
  esac
done <<<"$sections"

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

if ! git -C "$repo_dir" merge-base --is-ancestor "$verified_commit" "$base_ref" 2>/dev/null; then
  behind="$(git -C "$repo_dir" rev-list --count "$base_ref")"
  is_stale=1
  line_no=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    line_no=$((line_no + 1))
    globs="$(printf '%s' "$section_globs" | sed -n "${line_no}p")"
    if [ "$name" = "Team docs" ] || [ -n "$globs" ]; then mark_section_stale "$name"; fi
  done <<<"$section_names"
else
  behind="$(git -C "$repo_dir" rev-list --count "$verified_commit..$base_ref")"
  while IFS= read -r -d '' changed_file; do
    if matches_any_glob "$changed_file" "$ignore_globs"; then continue; fi
    claimed=0
    if printf '%s' "$team_doc_paths" | grep -Fxq -- "@$changed_file"; then
      claimed=1; mark_section_stale "Team docs"
    fi
    line_no=0
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      line_no=$((line_no + 1))
      globs="$(printf '%s' "$section_globs" | sed -n "${line_no}p" | tr ',' '\n')"
      if matches_any_glob "$changed_file" "$globs"; then claimed=1; mark_section_stale "$name"; fi
    done <<<"$section_names"
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
    subpath="$(bash "$plugin_root/scripts/handover/parse-mapping.sh" "$initiation_file" | awk -F'|' -v app="$app_name" '$1 == app { print $3; exit }')"
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
