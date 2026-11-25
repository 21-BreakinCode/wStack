#!/usr/bin/env bash
# contract-diagram.sh <subcommand> ...  Stamps, installs, lists stale, and restores deep dives.
#   subject <contract.yaml> <subject>            prints "hash: <hex>", then the subject JSON
#   install <contract.yaml> <subject> <drawn.html> [--backup-dir <dir> --record <list file>]
#   stale <contract.yaml>                        prints "stale: <subject> <path>" per stale deep dive
#   restore <list file>                          list line: <installed path><TAB><backup path or empty>
# Exit 0 done, 1 no such subject or a missing backup, 2 bad call or input, 4 lock busy.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
py=python3; [ ! -x /usr/bin/python3 ] || py=/usr/bin/python3
tab="$(printf '\t')"

usage() { echo "usage: contract-diagram.sh <subject|install|stale|restore> ..." >&2; exit 2; }
fail() { echo "contract-diagram: $1" >&2; exit 2; }

subject_hash() {  # <contract> <subject>; passes the exit 1 of an unknown subject through
  yq -o=json '.' "$1" | "$py" "$script_dir/contract_diagrams.py" hash "$2"
}

[ $# -ge 1 ] || usage
command="$1"; shift
case "$command" in
  subject)
    [ $# -eq 2 ] && [ -f "$1" ] || usage
    subject_hash "$1" "$2" | sed 's/^/hash: /'
    yq -o=json '.' "$1" | "$py" "$script_dir/contract_diagrams.py" subject "$2" ;;

  install)
    [ $# -ge 3 ] || usage
    contract="$1" subject="$2" drawn="$3"; shift 3
    backup_dir="" record=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --backup-dir) [ -n "${2:-}" ] || usage; backup_dir="$2"; shift 2 ;;
        --record) [ -n "${2:-}" ] || usage; record="$2"; shift 2 ;;
        *) usage ;;
      esac
    done
    [ -z "$backup_dir" ] || [ -n "$record" ] || fail "--backup-dir needs --record"
    [ -f "$contract" ] || fail "no such file: $contract"
    [ -f "$drawn" ] || fail "no such file: $drawn"
    grep -qi '<head[[:space:]>]' "$drawn" || fail "no <head> tag in $drawn"

    bash "$script_dir/contract-edit.sh" lock "$contract" || exit $?
    trap 'bash "$script_dir/contract-edit.sh" unlock "$contract"' EXIT
    rc=0; hash="$(subject_hash "$contract" "$subject")" || rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    verified_commit="$(yq -r '.verified_commit // ""' "$contract")"
    target="$(cd "$(dirname "$contract")" && pwd)/diagrams/${subject//:/-}.html"
    mkdir -p "$(dirname "$target")"

    if [ -f "$target" ] && [ -n "$backup_dir" ] && [ ! -e "$backup_dir/$(basename "$target")" ]; then
      mkdir -p "$backup_dir"
      cp "$target" "$backup_dir/$(basename "$target")"
      backup="$backup_dir/$(basename "$target")"
    else
      backup=""
    fi
    if [ -n "$record" ] && ! grep -qF "$target$tab" "$record" 2>/dev/null; then
      printf '%s\t%s\n' "$target" "$backup" >>"$record"
    fi

    "$py" - "$script_dir" "$drawn" "$target" "$subject" "$hash" "$verified_commit" <<'PY'
import html, re, sys
sys.path.insert(0, sys.argv[1])
from contract_diagrams import META_TAG, META_NAME
drawn, target, subject, stamped_hash, drawn_at = sys.argv[2:]
text = open(drawn, encoding="utf-8", errors="replace").read()
text = META_TAG.sub(lambda tag: "" if META_NAME.search(tag.group(0)) else tag.group(0), text)
stamp = "".join('<meta name="%s" content="%s">' % (name, html.escape(value, quote=True)) for name, value in
                [("wstack-subject", subject), ("wstack-subject-hash", stamped_hash), ("wstack-drawn-at", drawn_at)])
head = re.search(r"<head(?=[\s>])[^>]*>", text, re.I)
open(target, "w", encoding="utf-8").write(text[:head.end()] + stamp + text[head.end():])
PY
    echo "installed: $target"
    [ -z "$backup" ] || echo "backup: $backup" ;;

  stale)
    [ $# -eq 1 ] && [ -f "$1" ] || usage
    yq -o=json '.' "$1" | "$py" -c '
import json, sys
sys.path.insert(0, sys.argv[1])
from contract_diagrams import read_deep_dives
for dive in read_deep_dives(sys.argv[2], (json.load(sys.stdin) or {}).get("diagrams") or {}):
    if dive["state"] == "stale":
        print("stale: %s %s" % (dive["subject"], dive["path"]))
' "$script_dir" "$(dirname "$1")" ;;

  restore)
    [ $# -eq 1 ] || usage
    list="$1"
    [ -f "$list" ] || exit 0
    while IFS="$tab" read -r installed backup; do
      [ -z "$backup" ] || [ -f "$backup" ] || { echo "contract-diagram: backup missing: $backup" >&2; exit 1; }
    done <"$list"
    while IFS="$tab" read -r installed backup; do
      [ -n "$installed" ] || continue
      if [ -n "$backup" ]; then cp "$backup" "$installed"; echo "restored: $installed"
      else rm -f "$installed"; echo "removed: $installed"; fi
      rmdir "$(dirname "$installed")" 2>/dev/null || true
    done <"$list"
    rm -f "$list" ;;

  *) usage ;;
esac
