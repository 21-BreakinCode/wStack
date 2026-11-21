#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
python="python3"
[ -x /usr/bin/python3 ] && python="/usr/bin/python3"
for module in "$repo_root"/scripts/handover/*.py; do
  assert "$(basename "$module") compiles" '"$python" -m py_compile "$module"'
done
for check in "$repo_root"/tests/handover/test_*.py; do
  assert "$(basename "$check") passes" '"$python" "$check" >/dev/null'
done
finish
