#!/usr/bin/env bash
# Usage: contract-path.sh --vault <vault> <cwd>
# Prints <vault>/01Project/<org>/<lifeos_subpath>/<app_name>.contract.yaml. Exit 0 found, 1 not mapped, 2 error.
set -euo pipefail

if [ "${1:-}" != "--vault" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
  echo "usage: contract-path.sh --vault <vault> <cwd>" >&2
  exit 2
fi
vault="$2"
cwd="$3"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -d "$cwd" ] || { echo "contract-path.sh: no folder $cwd" >&2; exit 2; }

export LIFEOS_ROOT="$vault"
# Ruling 6: resolver exits 2 and 3 map to 1 on purpose. A vault without 01Project reads as "not mapped", not as an error.
org="$(cd "$cwd" && bash "$script_dir/handover/resolve-org.sh" 2>/dev/null)" || exit 1
mapping="$(bash "$script_dir/handover/resolve-service.sh" "$cwd" "$org" 2>/dev/null)" || exit 1
app_name="${mapping%%|*}"
lifeos_subpath="${mapping#*|}"
echo "$vault/01Project/$org/$lifeos_subpath/$app_name.contract.yaml"
