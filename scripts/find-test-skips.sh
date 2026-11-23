#!/usr/bin/env bash
# Usage: find-test-skips.sh <log file>
# Prints each line of a saved test output that reports a skip.
# It drops a passing test line (first word PASS, ok, or ✓, with no TAP "# skip") and a zero count (Skipped: 0, 0 skipped, skipped=0).
# Exit 0: no skip line. Exit 1: skip lines found. Exit 2: bad input, or the log cannot be read.
set -euo pipefail

skip_word='(skip|skipped|skipping|xfail|xfailed)'
skip_pattern="(^|[^[:alnum:]_])${skip_word}([^[:alnum:]_]|$)|no tests ran|collected 0 items"

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: find-test-skips.sh <log file>" >&2
  exit 2
fi

skip_lines="$(LC_ALL=C /usr/bin/awk -v skip="$skip_pattern" -v word="$skip_word" '
  /^[[:space:]]*(PASS|ok|✓):?([[:space:]]|$)/ && tolower($0) !~ /#[[:space:]]*skip/ { next }
  {
    line = tolower($0)
    gsub("(^|[^[:alnum:]_.])0[[:space:]]*" word "([^[:alnum:]_]|$)", " ", line)
    gsub(word "[[:space:]]*[:=]?[[:space:]]*0([^[:alnum:]_.]|$)", " ", line)
  }
  line ~ skip
' "$1")" || exit 2
[ -n "$skip_lines" ] || exit 0
printf '%s\n' "$skip_lines"
exit 1
