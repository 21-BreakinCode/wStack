#!/usr/bin/env bash
# contract-edit.sh <subcommand> ...  The only script that edits a service contract (<app>.contract.yaml) and its lock.
# Deliver "Contract files" also writes whole files with cp, under the lock from this script.
#   lock|unlock <contract_file>
#   apply <contract_file> <patch_file> [--sections "a,b"] [--section "a"]... [--planned "id,id"] [--diagrams]
#     A patch may hold a top-level diagrams: map. No flag applies it with the sections. --diagrams applies it alone:
#     it sets .diagrams to the patch block, or removes .diagrams if the patch has none. With any flag, only flagged parts apply.
#     --planned with no --sections or --section applies no section: it restores the named plan items only.
#   remove-planned <contract_file> <id>
#   pending-add <contract_file> <pr> <task_id> | pending-remove <contract_file> <pr>
#   set-verified <contract_file> <commit>
#   next-decision-id <decisions_dir>
# Every write stages a copy in the same folder, edits it with yq, runs contract-validate.sh on it,
# moves it into place, then runs contract-render.sh. A refused write leaves the contract unchanged.
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$plugin_root/scripts/lib/frontmatter.sh"
lock_tries=10
staged_file=""
trap '[ -z "$staged_file" ] || rm -f "$staged_file"' EXIT

usage() { echo "usage: contract-edit.sh <lock|unlock|apply|remove-planned|pending-add|pending-remove|set-verified|next-decision-id> ..." >&2; exit 2; }
fail() { echo "contract-edit.sh: $1" >&2; exit 2; }
require_pr() { [[ "$1" =~ ^[0-9]+$ ]] || fail "pr is not an integer: $1"; }
require_file() { [ -f "$1" ] || fail "no such file: $1"; }
yaml_query() { yq -p yaml -o yaml "$@"; }  # yq reads the temp name's extension otherwise
edit_staged() { yq -p yaml -o yaml -i "$1" "$staged_file" || fail "yq could not edit the staged copy of the contract"; }
plan_item_count() { PLAN_ID="$2" yaml_query '[.planned[]? | select(.id == strenv(PLAN_ID))] | length' "$1"; }  # <file> <id>
require_pending_list() {
  local pending_tag
  pending_tag="$(yaml_query '.pending | tag' "$1")" || fail "cannot read YAML: $1"
  [ "$pending_tag" = '!!seq' ] || [ "$pending_tag" = '!!null' ] || fail "pending must be a YAML list: $1"
}
stage() {  # <contract_file>: copy it to $staged_file in the same folder, so the final mv is atomic
  staged_file="$(mktemp "$1.XXXXXX")" || fail "cannot stage a copy of $1"
  { cp "$1" "$staged_file" && chmod 600 "$staged_file"; } || fail "cannot stage a copy of $1"
}
commit_staged() {  # <contract_file>
  local render_error
  bash "$plugin_root/scripts/contract-validate.sh" "$staged_file" || fail "the result fails contract-validate.sh, so $1 is unchanged"
  fm_replace "$staged_file" "$1" || fail "could not write: $1"
  staged_file=""
  # The YAML is the truth and is written; a failed view is only a warning.
  render_error="$(bash "$plugin_root/scripts/contract-render.sh" "$1" 2>&1 >/dev/null)" \
    || echo "contract-edit.sh: warning: render failed: $render_error" >&2
}
split_names() { tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true; }

subcommand="${1:-}"; [ -n "$subcommand" ] || usage
shift

case "$subcommand" in
  lock)
    lock_dir="${1:?usage: contract-edit.sh lock <contract_file>}.lock"
    [ -d "$(dirname "$lock_dir")" ] || fail "folder missing: $(dirname "$lock_dir")"
    for ((try = 1; try <= lock_tries; try++)); do
      mkdir "$lock_dir" 2>/dev/null && exit 0
      [ "$try" -eq "$lock_tries" ] || sleep 1
    done
    echo "contract-edit.sh: lock is busy: $lock_dir. If no task runs, remove the lock folder." >&2
    exit 4 ;;

  unlock)
    lock_dir="${1:?usage: contract-edit.sh unlock <contract_file>}.lock"
    [ -e "$lock_dir" ] || exit 0
    rmdir "$lock_dir" || { echo "contract-edit.sh: cannot remove the lock folder: $lock_dir" >&2; exit 1; } ;;

  apply)
    apply_usage='usage: contract-edit.sh apply <contract_file> <patch_file> [--sections "a,b"] [--section "a"]... [--planned "id,id"] [--diagrams]'
    target_file="${1:?$apply_usage}"
    patch_file="${2:?$apply_usage}"
    shift 2
    wanted_sections=""   # one key per line
    restore_ids=""       # one plan id per line
    diagrams_flag=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --diagrams) diagrams_flag=1; shift; continue ;;
        --sections) wanted_sections="$wanted_sections$(printf '%s' "${2:?--sections needs a value}" | split_names)"$'\n' ;;
        --section) wanted_sections="$wanted_sections$(printf '%s' "${2:?--section needs a value}" | split_names)"$'\n' ;;
        --planned) restore_ids="$restore_ids$(printf '%s' "${2:?--planned needs a value}" | split_names)"$'\n' ;;
        *) usage ;;
      esac
      shift 2
    done
    require_file "$target_file"
    [ -s "$patch_file" ] || fail "patch is empty or missing: $patch_file"
    patch_json="$(yq -p yaml -o json '.' "$patch_file" 2>/dev/null)" || fail "cannot read the patch YAML: $patch_file"
    jq -e 'type == "object" and ((.sections // {}) | type == "object")
      and ((.remove_planned // []) | type == "array" and all(type == "string"))' >/dev/null <<<"$patch_json" \
      || fail "a patch holds a sections: map and/or a diagrams: map, plus an optional remove_planned: list of ids: $patch_file"
    jq -e '(has("diagrams") | not) or (.diagrams | type == "object" or type == "null")' >/dev/null <<<"$patch_json" \
      || fail "diagrams in the patch must be a map: $patch_file"
    contract_keys="$(yq -p yaml -o json '.sections | keys' "$target_file" 2>/dev/null)" || fail "cannot read the sections of $target_file"
    unknown_keys="$(jq -r --argjson contract_keys "$contract_keys" \
      '(.sections // {}) | keys_unsorted[] | select(. as $key | $contract_keys | index($key) | not)' <<<"$patch_json")"
    [ -z "$unknown_keys" ] || fail "the contract has no section named: $(printf '%s' "$unknown_keys" | paste -sd, -)"
    patch_keys="$(jq -r '(.sections // {}) | keys_unsorted[]' <<<"$patch_json")"
    if [ -n "$wanted_sections" ]; then
      apply_keys="$(printf '%s' "$wanted_sections" | grep -v '^$' || true)"
      while IFS= read -r section_key; do
        printf '%s\n' "$patch_keys" | grep -qxF "$section_key" || fail "the patch has no section named: $section_key"
      done <<<"$apply_keys"
    elif [ -n "$restore_ids" ] || [ "$diagrams_flag" = 1 ]; then
      apply_keys=""  # --planned or --diagrams alone applies no section, so a full snapshot undoes no section
    else
      apply_keys="$patch_keys"
    fi
    patch_has_diagrams="$(jq -r 'has("diagrams")' <<<"$patch_json")"
    if [ "$diagrams_flag" = 1 ]; then apply_diagrams=1
    elif [ -n "$wanted_sections$restore_ids" ]; then apply_diagrams=0
    elif [ "$patch_has_diagrams" = true ]; then apply_diagrams=1
    else apply_diagrams=0; fi
    restore_ids="$(printf '%s' "$restore_ids" | grep -v '^$' || true)"
    while IFS= read -r plan_id; do
      [ -z "$plan_id" ] || [ "$(plan_item_count "$patch_file" "$plan_id")" -gt 0 ] || fail "the patch has no plan item: $plan_id"
    done <<<"$restore_ids"
    remove_ids="$(jq -r '(.remove_planned // [])[]' <<<"$patch_json")"
    [ -n "$apply_keys$restore_ids$remove_ids" ] || [ "$apply_diagrams" = 1 ] || fail "patch holds nothing to apply: $patch_file"

    stage "$target_file"
    export PATCH_FILE="$patch_file"
    while IFS= read -r section_key; do
      [ -z "$section_key" ] || SECTION_KEY="$section_key" edit_staged '.sections[strenv(SECTION_KEY)] = load(strenv(PATCH_FILE)).sections[strenv(SECTION_KEY)]'
    done <<<"$apply_keys"
    if [ "$apply_diagrams" = 1 ]; then
      if [ "$patch_has_diagrams" = true ]; then edit_staged '.diagrams = load(strenv(PATCH_FILE)).diagrams'
      else edit_staged 'del(.diagrams)'; fi
    fi
    while IFS= read -r plan_id; do
      [ -n "$plan_id" ] || continue
      export PLAN_ID="$plan_id"
      if [ "$(plan_item_count "$staged_file" "$plan_id")" -gt 0 ]; then
        edit_staged '(.planned[] | select(.id == strenv(PLAN_ID))) = (load(strenv(PATCH_FILE)).planned[] | select(.id == strenv(PLAN_ID)))'
      else
        edit_staged '.planned += [load(strenv(PATCH_FILE)).planned[] | select(.id == strenv(PLAN_ID))]'
      fi
    done <<<"$restore_ids"
    removed_ids=""
    while IFS= read -r plan_id; do
      [ -n "$plan_id" ] || continue
      if [ "$(plan_item_count "$staged_file" "$plan_id")" -eq 0 ]; then
        echo "contract-edit.sh: warning: no plan item to remove: $plan_id" >&2; continue
      fi
      PLAN_ID="$plan_id" edit_staged 'del(.planned[] | select(.id == strenv(PLAN_ID)))'
      removed_ids="$removed_ids$plan_id"$'\n'
    done <<<"$remove_ids"
    commit_staged "$target_file"
    [ -z "$apply_keys" ] || printf '%s\n' "$apply_keys"
    [ "$apply_diagrams" = 0 ] || echo diagrams
    [ -z "$restore_ids" ] || printf '%s\n' "$restore_ids" | sed 's/^/planned restored: /'
    [ -z "$removed_ids" ] || printf '%s' "$removed_ids" | sed 's/^/planned removed: /' ;;

  remove-planned)
    contract_file="${1:?usage: contract-edit.sh remove-planned <contract_file> <id>}"
    plan_id="${2:?usage: contract-edit.sh remove-planned <contract_file> <id>}"
    require_file "$contract_file"
    plan_count="$(plan_item_count "$contract_file" "$plan_id")" || fail "cannot read YAML: $contract_file"
    [ "$plan_count" -gt 0 ] || { echo "contract-edit.sh: no plan item: $plan_id" >&2; exit 1; }
    stage "$contract_file"
    PLAN_ID="$plan_id" edit_staged 'del(.planned[] | select(.id == strenv(PLAN_ID)))'
    commit_staged "$contract_file" ;;

  pending-add)
    contract_file="${1:?usage: contract-edit.sh pending-add <contract_file> <pr> <task_id>}"
    export PENDING_PR="${2:?pr}" PENDING_TASK="${3:?task_id}"
    require_pr "$PENDING_PR"
    require_file "$contract_file"
    require_pending_list "$contract_file"
    [ "$(yaml_query '[.pending[]? | select(.pr == env(PENDING_PR))] | length' "$contract_file")" -eq 0 ] || exit 0
    stage "$contract_file"
    edit_staged '.pending += [{"pr": env(PENDING_PR), "task": strenv(PENDING_TASK)}]'
    commit_staged "$contract_file" ;;

  pending-remove)
    contract_file="${1:?usage: contract-edit.sh pending-remove <contract_file> <pr>}"
    export PENDING_PR="${2:?pr}"
    require_pr "$PENDING_PR"
    require_file "$contract_file"
    require_pending_list "$contract_file"
    stage "$contract_file"
    edit_staged 'del(.pending[] | select(.pr == env(PENDING_PR)))'
    commit_staged "$contract_file" ;;

  set-verified)
    contract_file="${1:?usage: contract-edit.sh set-verified <contract_file> <commit>}"
    export VERIFIED_COMMIT="${2:?commit}" VERIFIED_AT
    VERIFIED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    require_file "$contract_file"
    stage "$contract_file"
    edit_staged '.verified_commit = strenv(VERIFIED_COMMIT) | .verified_at = strenv(VERIFIED_AT)'
    commit_staged "$contract_file" ;;

  next-decision-id)
    decisions_dir="${1:?usage: contract-edit.sh next-decision-id <decisions_dir>}"
    highest=0
    for decision_file in "$decisions_dir"/[0-9][0-9][0-9][0-9]-*.md; do
      [ -e "$decision_file" ] || continue
      decision_id="$(basename "$decision_file")"; decision_id=$((10#${decision_id:0:4}))
      [ "$decision_id" -le "$highest" ] || highest="$decision_id"
    done
    printf '%04d\n' $((highest + 1)) ;;

  *) usage ;;
esac
