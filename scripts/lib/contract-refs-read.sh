# Shared by contract-refs.sh and contract-ref-shift.sh, so both read the same set of refs.
# cross_form matches a cross-repo ref `<owner>/<repo>@<commit>:`.
cross_form='^[^/@:]+/[^/@:]+@[0-9a-f]+:'
# contract_ref_lines <contract_json>: print every ref of all sections, planned, and diagrams, one per line.
contract_ref_lines() {
  jq -r '[(.sections // {} | .[] | objects | .items // [] | .[] | objects | .refs // [] | .[]),
          (.planned // [] | .[] | objects | .refs // [] | .[]),
          (.diagrams // {} | .. | objects | select(has("refs")) | .refs | arrays | .[])] | .[] | strings' <<<"$1"
}
