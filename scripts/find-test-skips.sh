#!/usr/bin/env bash
# Usage: find-test-skips.sh <log file>
# Prints each line of a saved test output that reports a skip.
# Exit 0: no skip line. Exit 1: skip lines found. Exit 2: bad input.
set -euo pipefail

skip_pattern='(^|[^[:alnum:]_])(skip|skipped|skipping|xfail|xfailed)([^[:alnum:]_]|$)|no tests ran|collected 0 items'

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: find-test-skips.sh <log file>" >&2
  exit 2
fi

if /usr/bin/grep -i -E -e "$skip_pattern" -- "$1"; then
  exit 1
fi
