#!/usr/bin/env bash
# contract-verify-draft.sh <repo_dir> <task_dir> <contract_file> <task_id> <evidence_dir>
# Run the four scripted checks on <task_dir>/contract.draft.yaml. Each check writes check-<name>.txt in
# <evidence_dir> with each command, its output, and its exit code. Prints PASS <name> or FAIL <name>.
#   contract-check     contract-check.sh, then --coverage: both exit 0 with unclaimed_count: 0
#   contract-validate  contract-validate.sh: exit 0
#   contract-refs      contract-refs.sh: exit 0
#   undo-rehearsal     contract-deliver.sh rehearse: exit 0
# Exit 0 all pass, 1 a check failed, 2 bad input.
set -euo pipefail

usage_line="usage: contract-verify-draft.sh <repo_dir> <task_dir> <contract_file> <task_id> <evidence_dir>"
[ $# -eq 5 ] && [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] || { echo "$usage_line" >&2; exit 2; }
repo_dir="$1"; task_dir="$2"; contract_file="$3"; task_id="$4"; evidence_dir="$5"
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
draft_file="$task_dir/contract.draft.yaml"
[ -d "$repo_dir" ] || { echo "contract-verify-draft.sh: no repo folder: $repo_dir" >&2; exit 2; }
[ -f "$draft_file" ] || { echo "contract-verify-draft.sh: no draft: $draft_file" >&2; exit 2; }
mkdir -p "$evidence_dir" || { echo "contract-verify-draft.sh: cannot create $evidence_dir" >&2; exit 2; }

run_logged() {  # <evidence file> <command>...: append the command, its output, and its exit code; return the exit code
  local evidence_file="$1" command_rc=0
  shift
  { echo "\$ $*"; "$@" 2>&1 || command_rc=$?; echo "exit: $command_rc"; echo; } >>"$evidence_file"
  return "$command_rc"
}
report() {  # <name> <passed 0|1>
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; failed=1; fi
}

failed=0
check_file="$evidence_dir/check-contract-check.txt"; : >"$check_file"
check_rc=0
run_logged "$check_file" bash "$scripts/contract-check.sh" "$repo_dir" "$draft_file" --mapping-from "$contract_file" || check_rc=1
run_logged "$check_file" bash "$scripts/contract-check.sh" "$repo_dir" "$draft_file" --coverage --mapping-from "$contract_file" || check_rc=1
[ "$(grep -c '^unclaimed_count: 0$' "$check_file")" = 2 ] || check_rc=1
report contract-check "$check_rc"

single_check() {  # <name> <command>...: pass on exit 0
  local name="$1" check_rc=0
  shift
  : >"$evidence_dir/check-$name.txt"
  run_logged "$evidence_dir/check-$name.txt" "$@" || check_rc=1
  report "$name" "$check_rc"
}
single_check contract-validate bash "$scripts/contract-validate.sh" "$draft_file"
single_check contract-refs bash "$scripts/contract-refs.sh" "$repo_dir" "$draft_file" --mapping-from "$contract_file"
single_check undo-rehearsal bash "$scripts/contract-deliver.sh" rehearse "$task_dir" "$contract_file" "$task_id"
exit "$failed"
