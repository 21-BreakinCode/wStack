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
set -f  # word splitting below must not glob

start='(^|[^[:alnum:]_./-])'
space='[[:space:]]+'
# cf accepts global flags (with an optional value) between any two command words
cf_flags='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'

default_branch="$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_branch#origin/}"
if [ -n "$default_branch" ]; then default_branches=("$default_branch"); else default_branches=(main master); fi

# Judges the words of one "git ... push ..." segment. Returns 0 when risky.
push_is_risky() {  # <words...>, starting at the word "git"
  local word bare repo_dir="$cwd" current positional=0 seen_push=0 skip_next=""
  shift  # drop "git"
  for word in "$@"; do
    word="${word//[\'\"]/}"
    if [ -n "$skip_next" ]; then
      [ "$skip_next" = "C" ] && repo_dir="$word"
      skip_next=""; continue
    fi
    if [ "$seen_push" = 0 ]; then
      case "$word" in
        -C) skip_next="C" ;;
        -c) skip_next="c" ;;
        -*) ;;
        push) seen_push=1 ;;
        *) return 1 ;;  # another git subcommand
      esac
      continue
    fi
    case "$word" in
      --force*|--delete|-d|-f|+*) return 0 ;;
      -*) [[ "$word" =~ ^-[a-zA-Z]*[fd][a-zA-Z]*$ ]] && return 0; continue ;;
    esac
    positional=$((positional + 1))
    for bare in "${default_branches[@]}"; do
      case "$word" in "$bare"|"refs/heads/$bare"|*":$bare"|*":refs/heads/$bare") return 0 ;; esac
    done
  done
  [ "$seen_push" = 1 ] || return 1
  if [ "$positional" -le 1 ]; then  # no refspec: pushes the current branch
    case "$repo_dir" in /*) ;; *) repo_dir="$cwd/$repo_dir" ;; esac
    current="$(git -C "$repo_dir" symbolic-ref --short HEAD 2>/dev/null || true)"
    for bare in "${default_branches[@]}"; do [ "$current" = "$bare" ] && return 0; done
  fi
  return 1
}

# Sets $reason for one command segment.
judge_segment() {
  local segment="$1" words word deploy_command
  [[ "$segment" =~ ^[[:space:]]*WSTACK_APPROVED=1([[:space:]]|$) ]] && return 0
  if [[ "$segment" =~ ${start}gh${space}pr${space}merge ]]; then
    reason="a pull request merge"
  elif [[ "$segment" =~ ${start}gh${space}api.*pulls/[^[:space:]]+/merge ]]; then
    reason="a pull request merge through the API"
  elif [[ "$segment" =~ ${start}gh${space}pr${space}close.*--delete-branch ]]; then
    reason="a pull request close with a remote branch delete"
  elif [[ "$segment" =~ ${start}gh${space}repo${space}delete ]]; then
    reason="a repository delete"
  elif [[ "$segment" =~ ${start}cf${cf_flags}${space}r2${cf_flags}${space}objects${cf_flags}${space}[a-z-]*delete ]]; then
    reason="an R2 object delete"
  elif [[ "$segment" =~ ${start}cf${cf_flags}${space}r2${cf_flags}${space}buckets${cf_flags}${space}delete ]]; then
    reason="an R2 bucket delete"
  elif [[ "$segment" =~ ${start}cf${cf_flags}${space}r2${cf_flags}${space}buckets${cf_flags}${space}jobs${cf_flags}${space}create ]]; then
    reason="an R2 bucket job (a prefixDelete job deletes objects or empties the bucket)"
  else
    for deploy_command in "npm publish" "gh release create" "docker push" "terraform apply" \
      "kubectl apply" "helm install" "helm upgrade" "vercel --prod" "vercel deploy --prod" \
      "fly deploy" "firebase deploy" "wrangler deploy" "cf workers deploy"; do
      if [[ "$segment" =~ ${start}${deploy_command// /$space} ]]; then
        reason="a deploy or publish ($deploy_command)"
        return 0
      fi
    done
    for word in $segment; do
      if [ "${word//[\'\"]/}" = "git" ]; then
        words="${segment#*"$word"}"
        # shellcheck disable=SC2086
        push_is_risky git $words && reason="a git push to the default branch, a force push, or a remote delete"
        break
      fi
    done
  fi
  return 0
}

separated="${command_text//&&/$'\n'}"
separated="${separated//||/$'\n'}"
separated="${separated//;/$'\n'}"
separated="${separated//|/$'\n'}"
reason=""
while IFS= read -r segment; do
  judge_segment "$segment"
  [ -z "$reason" ] || break
done <<< "$separated"

[ -n "$reason" ] || exit 0

message="wStack guard: $reason. This step cannot be undone. Ask the user first."
if [ "$mode" = "deny" ]; then
  message="$message After the user approves, run the same command again with the prefix WSTACK_APPROVED=1."
fi
emit "$mode" "$message"
