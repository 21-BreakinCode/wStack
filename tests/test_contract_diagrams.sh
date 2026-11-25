#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
python="python3"
[ -x /usr/bin/python3 ] && python="/usr/bin/python3"
assert "contract_diagrams.py compiles" '"$python" -m py_compile "$repo_root/scripts/contract_diagrams.py"'
assert "contract_diagrams_svg.py compiles" '"$python" -m py_compile "$repo_root/scripts/contract_diagrams_svg.py"'
for check in "$repo_root"/tests/contract/test_*.py; do
  assert "$(basename "$check") passes" '"$python" "$check" >/dev/null 2>&1'
done
finish
