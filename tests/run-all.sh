#!/usr/bin/env bash
set -euo pipefail
tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for test_file in "$tests_dir"/test_*.sh; do
  echo "== $(basename "$test_file")"
  bash "$test_file" || failed=1
done
exit "$failed"
