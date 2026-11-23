#!/usr/bin/env bash
# Fake obsidian CLI. It acts on $FAKE_VAULT and always exits 0, like the real one.
# FAKE_FAIL_MATCH: a move whose path contains this text fails.
# FAKE_MOVE_THEN_FAIL_MATCH: a move whose path contains this text moves the file, then prints an error.
# FAKE_FAIL_ARCHIVE_SOURCE=1: a move whose path starts with <FAKE_TASKS_DIR>/_archive/ fails.
set -uo pipefail
command_name="${1:-}"
case "$command_name" in
  vault) echo "$FAKE_VAULT" ;;
  move)
    from_rel="${2#path=}"; to_rel="${3#to=}"
    if [ -n "${FAKE_FAIL_MATCH:-}" ] && [[ "$from_rel" == *"$FAKE_FAIL_MATCH"* ]]; then echo "Error: fake failure"; exit 0; fi
    if [ -n "${FAKE_MOVE_THEN_FAIL_MATCH:-}" ] && [[ "$from_rel" == *"$FAKE_MOVE_THEN_FAIL_MATCH"* ]]; then mv "$FAKE_VAULT/$from_rel" "$FAKE_VAULT/$to_rel"; echo "Error: fake failure"; exit 0; fi
    if [ "${FAKE_FAIL_ARCHIVE_SOURCE:-}" = 1 ] && [[ "$from_rel" == "${FAKE_TASKS_DIR:-Tasks}/_archive/"* ]]; then echo "Error: fake failure"; exit 0; fi
    if mv "$FAKE_VAULT/$from_rel" "$FAKE_VAULT/$to_rel" 2>/dev/null; then echo "Moved: $from_rel -> $to_rel"; else echo "Error: ENOENT"; fi ;;
  *) echo "Error: unknown fake command" ;;
esac
exit 0
