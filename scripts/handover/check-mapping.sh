#!/usr/bin/env bash
# check-mapping.sh — read-only check of every row in an org's Service Mapping table.
#
# Usage: check-mapping.sh <vault> <org>
# Prints a header line, then one tab-separated line per row:
#   status app_name repo_path repo link ignore vault contract notes
# status: ok, fix (init-service can fix the row), or broken (the repo path is
# missing or is not a git work tree). The contract column does not count
# toward status.
# Exit codes: 0 every row ok, 1 a row is fix or broken, 2 error.

set -euo pipefail

vault="${1:?usage: check-mapping.sh <vault> <org>}"
org="${2:?usage: check-mapping.sh <vault> <org>}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
init="$vault/01Project/$org/handover_handler__initiation.md"
[ -f "$init" ] || { echo "check-mapping.sh: initiation file missing: $init" >&2; exit 2; }
records="$(bash "$script_dir/parse-mapping.sh" "$init")"

same_folder() { [ -d "$1" ] && [ -d "$2" ] && [ "$(cd "$1" && pwd -P)" = "$(cd "$2" && pwd -P)" ]; }

link_state() {  # <link_path> <expected_target>
    if [ -L "$1" ]; then
        if same_folder "$1" "$2" || [ "$(readlink "$1")" = "$2" ]; then echo ok; else echo "wrong: -> $(readlink "$1")"; fi
    elif [ -e "$1" ]; then
        echo "not a link"
    else
        echo missing
    fi
}

contract_state() {  # <repo_root> <contract_file>
    [ -f "$2" ] || { echo missing; return; }
    local rc=0 errors
    errors="$(bash "$script_dir/../contract-check.sh" "$1" "$2" 2>&1 >/dev/null)" || rc=$?
    case "$rc" in
        0) echo fresh ;;
        1) echo stale ;;
        *) echo "error: ${errors%%$'\n'*}" ;;
    esac
}

printf 'status\tapp_name\trepo_path\trepo\tlink\tignore\tvault\tcontract\tnotes\n'
any_failed=0
# fd 3 keeps the git and contract-check calls off the row list.
while IFS='|' read -r app_name repo_path lifeos_subpath <&3; do
    [ -n "$app_name" ] || continue
    repo="${repo_path//\$HOME/$HOME}"
    repo="${repo//\$LifeOS/$vault}"
    if [ -z "$lifeos_subpath" ]; then
        any_failed=1
        printf 'broken\t%s\t%s\t-\t-\t-\t-\t-\trow has no lifeos_subpath\n' "$app_name" "$repo"
        continue
    fi
    handover_folder="$vault/01Project/$org/$lifeos_subpath/handover"
    contract_file="$vault/01Project/$org/$lifeos_subpath/$app_name.contract.yaml"
    vault_state=missing
    [ -d "$handover_folder" ] && vault_state=ok
    notes=""
    [[ "$app_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || notes="app_name is not kebab-case"

    if [ ! -d "$repo" ]; then
        repo_state=missing
    elif ! repo_root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"; then
        repo_state="not git"
    else
        repo_state=ok
    fi

    if [ "$repo_state" = ok ]; then
        link="$(link_state "$repo_root/handover" "$handover_folder")"
        ignore=missing
        git -C "$repo_root" check-ignore -q --no-index handover && ignore=ok
        contract="$(contract_state "$repo_root" "$contract_file")"
        status=fix
        [ "$link" = ok ] && [ "$ignore" = ok ] && [ "$vault_state" = ok ] && status=ok
    else
        link=-
        ignore=-
        contract=missing
        [ -f "$contract_file" ] && contract=present
        status=broken
    fi
    [ "$status" = ok ] || any_failed=1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$status" "$app_name" "$repo" "$repo_state" "$link" "$ignore" "$vault_state" "$contract" "$notes"
done 3<<< "$records"
exit "$any_failed"
