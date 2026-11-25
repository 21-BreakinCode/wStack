#!/usr/bin/env bash
# Usage: contract-open.sh --vault <vault> [--note] [--print] [<service>]
# Finds a contract (by <service> name, or by the current folder), renders its views when they are
# missing or older than the .contract.yaml, and opens the HTML page (or, with --note, the vault note
# in Obsidian). --print prints the path and does not open it.
# Exit 0 opened, 1 no contract found (lists the rendered pages on stderr), 2 bad call or render failure.
set -euo pipefail

usage() { echo "usage: contract-open.sh --vault <vault> [--note] [--print] [<service>]" >&2; exit 2; }
vault="" want_note=0 print_only=0 service=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) [ -n "${2:-}" ] || usage; vault="$2"; shift 2 ;;
    --note) want_note=1; shift ;;
    --print) print_only=1; shift ;;
    -*) usage ;;
    *) [ -z "$service" ] || usage; service="$1"; shift ;;
  esac
done
[ -n "$vault" ] || usage
[ -d "$vault" ] || { echo "contract-open: no vault folder $vault" >&2; exit 2; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pages_dir="$HOME/.wstack/pages/contracts"

no_contract() {
  echo "contract-open: $1" >&2
  found_any=0
  for page in "$pages_dir"/*.html; do
    [ -e "$page" ] || continue
    [ "$found_any" = 1 ] || echo "rendered contracts:" >&2
    found_any=1
    echo "  $(basename "$page" .html)" >&2
  done
  [ "$found_any" = 1 ] || echo "no rendered contract in $pages_dir" >&2
  exit 1
}

if [ -z "$service" ]; then
  contract="$(bash "$script_dir/contract-path.sh" --vault "$vault" "$PWD" 2>/dev/null)" \
    || no_contract "the current folder is not a mapped repository"
else
  [[ "$service" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "contract-open: bad service name $service" >&2; exit 2; }
  contract="$(find "$vault/01Project" -name "$service.contract.yaml" -not -path '*/_archive/*' 2>/dev/null | head -n 1)"
fi
[ -n "$contract" ] && [ -f "$contract" ] || no_contract "no contract for ${service:-the current repository}"

app_name="$(basename "$contract" .contract.yaml)"
note="$(dirname "$contract")/$app_name.md"
page="$pages_dir/$app_name.html"
if [ "$want_note" = 1 ]; then target="$note"; else target="$page"; fi
if [ ! -f "$target" ] || [ "$contract" -nt "$target" ]; then
  bash "$script_dir/contract-render.sh" "$contract" >/dev/null || exit 2
fi

if [ "$print_only" = 1 ]; then echo "$target"; exit 0; fi
if [ "$want_note" = 1 ]; then
  open "obsidian://open?path=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$note")"
else
  open "$target"
fi
echo "$target"
