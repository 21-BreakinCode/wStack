#!/usr/bin/env bash
# Usage: contract-render.sh <contract.yaml>
# Writes <folder>/<app_name>.md and $HOME/.wstack/pages/contracts/<app_name>.html. Prints both paths.
# Exit 0 written, 2 bad input or a write failure.
set -euo pipefail

contract="${1:-}"
[ -f "$contract" ] || { echo "contract-render: no such file: $contract" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "contract-render: yq not found" >&2; exit 2; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
contract_dir="$(cd "$(dirname "$contract")" && pwd)"
app_name="$(yq -r '.app_name // ""' "$contract" 2>/dev/null)" || { echo "contract-render: cannot parse $contract" >&2; exit 2; }
[[ "$app_name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "contract-render: bad or missing app_name in $contract" >&2; exit 2; }

note_path="$contract_dir/$app_name.md"
pages_dir="$HOME/.wstack/pages/contracts"
html_path="$pages_dir/$app_name.html"
mkdir -p "$pages_dir" || { echo "contract-render: cannot create $pages_dir" >&2; exit 2; }

yq -o=json '.' "$contract" | python3 "$script_dir/contract_render.py" "$note_path" "$html_path" "$(basename "$contract")" \
  || { echo "contract-render: render failed for $contract" >&2; exit 2; }
echo "$note_path"
echo "$html_path"
