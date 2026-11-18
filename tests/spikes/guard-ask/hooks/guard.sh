#!/bin/bash
if grep -q WSTACK_SPIKE; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"spike"}}'
fi
