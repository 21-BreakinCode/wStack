#!/usr/bin/env bash
# Exit 0 when <repo> is in the comma list <local_evidence_only_repos>, else 1. An empty repo is never listed.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: repo-is-local-only.sh <repo> <comma-list>" >&2; exit 2; }
[ -n "$1" ] || exit 1
case ",$2," in *",$1,"*) exit 0 ;; esac
exit 1
