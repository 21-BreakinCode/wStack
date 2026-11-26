# Shared by contract-refs.sh and contract-ref-shift.sh, so both read the same set of refs and find the same clones.
# The caller defines fail <message>.
refs_lib_dir="$(dirname "${BASH_SOURCE[0]}")"
source "$refs_lib_dir/frontmatter.sh"
# cross_form matches a cross-repo ref `<owner>/<repo>@<commit>:`.
cross_form='^[^/@:]+/[^/@:]+@[0-9a-f]+:'
# contract_ref_lines <contract_json>: print each distinct ref of all sections, planned, and diagrams once, one per line.
contract_ref_lines() {
  jq -r '[(.sections // {} | .[] | objects | .items // [] | .[] | objects | .refs // [] | .[]),
          (.planned // [] | .[] | objects | .refs // [] | .[]),
          (.diagrams // {} | .. | objects | select(has("refs")) | .refs | arrays | .[])] | .[] | strings' <<<"$1" | awk '!seen[$0]++'
}

expand_home() { local path="${1//\$HOME/$HOME}"; echo "${path/#\~/$HOME}"; }

# load_clone_mapping <path>: find the initiation file up from the nearest existing folder of <path>.
# It holds workspace_root and the Service Mapping; this sets mapping_rows and workspace_root for clone_for.
load_clone_mapping() {
  local org_dir initiation_file=""
  org_dir="$(dirname "$1")"
  while [ ! -d "$org_dir" ]; do org_dir="$(dirname "$org_dir")"; done  # a new service's folder may not exist yet
  org_dir="$(cd "$org_dir" && pwd -P)"
  while [ "$org_dir" != "/" ]; do
    if [ -f "$org_dir/handover_handler__initiation.md" ]; then initiation_file="$org_dir/handover_handler__initiation.md"; break; fi
    org_dir="$(dirname "$org_dir")"
  done
  mapping_rows=""; workspace_root=""
  [ -n "$initiation_file" ] || return 0
  mapping_rows="$(bash "$refs_lib_dir/../handover/parse-mapping.sh" "$initiation_file")" || fail "cannot read the service mapping in $initiation_file"
  workspace_root="$(expand_home "$(fm_get "$initiation_file" workspace_root)")"
}

clone_for() {  # <owner/repo>: print the local clone path, or nothing
  local slug="$1" mapped_repo_path remote_url
  while IFS='|' read -r _ mapped_repo_path _; do
    [ -n "$mapped_repo_path" ] || continue
    mapped_repo_path="$(expand_home "$mapped_repo_path")"
    remote_url="$(git -C "$mapped_repo_path" remote get-url origin 2>/dev/null)" || continue
    case "$remote_url" in *[/:]"$slug" | *[/:]"$slug.git") echo "$mapped_repo_path"; return ;; esac
  done <<<"$mapping_rows"
  [ -n "$workspace_root" ] || return 0
  local candidate
  for candidate in "$workspace_root/$slug" "$workspace_root/${slug#*/}"; do  # <owner>/<repo> or <repo>
    if [ -d "$candidate/.git" ]; then echo "$candidate"; return; fi
  done
}
