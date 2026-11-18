#!/usr/bin/env bash
# Seat belt, not a wall: asks before non-undoable commands a cooperative agent might run by mistake.
set -euo pipefail

DEFAULT_MODE=ask  # S1 result: ask-prompts
mode="${WSTACK_GUARD_MODE:-$DEFAULT_MODE}"

emit() {  # <decision> <reason>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
}

if ! command -v jq >/dev/null 2>&1; then
  emit ask "wStack guard cannot parse the command: install jq"
  exit 0
fi

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
command_text="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null || echo .)"

[ "$tool_name" = "Bash" ] || exit 0
[ -n "$command_text" ] || exit 0
[[ "$command_text" =~ ^[[:space:]]*WSTACK_APPROVED=1[[:space:]] ]] && exit 0

start='(^|[^[:alnum:]_./-])'
space='[[:space:]]+'

default_branch="$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_branch#origin/}"
if [ -n "$default_branch" ]; then default_branches=("$default_branch"); else default_branches=(main master); fi

reason=""

# Returns 0 when the arguments after "git push" are risky.
push_is_risky() {
  local tail="${command_text#*git push}" word bare current positional=0
  tail="${tail%%&&*}"; tail="${tail%%;*}"; tail="${tail%%|*}"
  for word in $tail; do
    word="${word//[\'\"]/}"
    case "$word" in
      --force*|--delete|-d|-f|+*) return 0 ;;
      -*) [[ "$word" =~ ^-[a-zA-Z]*[fd][a-zA-Z]*$ ]] && return 0; continue ;;
    esac
    positional=$((positional + 1))
    for bare in "${default_branches[@]}"; do
      case "$word" in "$bare"|*":$bare"|*":refs/heads/$bare") return 0 ;; esac
    done
  done
  if [ "$positional" -le 1 ]; then  # no refspec: pushes the current branch
    current="$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || true)"
    for bare in "${default_branches[@]}"; do [ "$current" = "$bare" ] && return 0; done
  fi
  return 1
}

if [[ "$command_text" =~ ${start}gh${space}pr${space}merge ]]; then
  reason="a pull request merge"
elif [[ "$command_text" =~ ${start}gh${space}api.*pulls/[^[:space:]]+/merge ]]; then
  reason="a pull request merge through the API"
elif [[ "$command_text" =~ ${start}git${space}push ]] && push_is_risky; then
  reason="a git push to the default branch, a force push, or a remote delete"
elif [[ "$command_text" =~ ${start}gh${space}pr${space}close.*--delete-branch ]]; then
  reason="a pull request close with a remote branch delete"
elif [[ "$command_text" =~ ${start}gh${space}repo${space}delete ]]; then
  reason="a repository delete"
elif [[ "$command_text" =~ ${start}cf${space}r2${space}objects${space}[a-z-]*delete ]]; then
  reason="an R2 object delete"
elif [[ "$command_text" =~ ${start}cf${space}r2${space}buckets${space}delete ]]; then
  reason="an R2 bucket delete"
else
  for deploy_command in "npm publish" "gh release create" "docker push" "terraform apply" \
    "kubectl apply" "helm install" "helm upgrade" "vercel --prod" "vercel deploy --prod" \
    "fly deploy" "firebase deploy" "wrangler deploy" "cf workers deploy"; do
    if [[ "$command_text" =~ ${start}${deploy_command// /$space} ]]; then
      reason="a deploy or publish ($deploy_command)"
      break
    fi
  done
fi

[ -n "$reason" ] || exit 0

message="wStack guard: $reason. This step cannot be undone. Ask the user first."
if [ "$mode" = "deny" ]; then
  message="$message After the user approves, run the same command again with the prefix WSTACK_APPROVED=1."
fi
emit "$mode" "$message"
