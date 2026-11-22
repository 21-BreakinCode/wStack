#!/usr/bin/env bash
# Seat belt, not a wall: asks before non-undoable commands a cooperative agent might run by mistake.
set -euo pipefail

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

start='(^|[^[:alnum:]_.-])'
space='[[:space:]]+'
optional_quote='["'"'"'"'"'"']?'
# cf accepts global flags (with an optional value) between any two command words
# words that may stand in front of a command: env assignments, wrappers, shell keywords, "bash -c"
command_prefix='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|command|sudo|nice|time|exec|eval|then|do|else|\{|!|bash|sh|zsh|-c)[[:space:]]+)*'
cf_flags='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'

default_branch="$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_branch#origin/}"
if [ -n "$default_branch" ]; then default_branches=("$default_branch"); else default_branches=(main master); fi

# Judges the words of one "git ... push ..." segment. Returns 0 when risky.
push_is_risky() {  # <words...>, starting at the word "git"
  local word bare repo_dir="$cwd" current positional=0 seen_push=0 skip_next="" refspec_is_current=0
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
      --force*|--delete|--mirror|--all|-d|-f|+*|:*) return 0 ;;
      -*) [[ "$word" =~ ^-[a-zA-Z]*[fd][a-zA-Z]*$ ]] && return 0; continue ;;
    esac
    positional=$((positional + 1))
    [ "$positional" -ge 2 ] && case "$word" in HEAD|@) refspec_is_current=1 ;; esac
    for bare in "${default_branches[@]}"; do
      case "$word" in "$bare"|"refs/heads/$bare"|*":$bare"|*":refs/heads/$bare") return 0 ;; esac
    done
  done
  [ "$seen_push" = 1 ] || return 1
  if [ "$positional" -le 1 ] || [ "$refspec_is_current" = 1 ]; then  # no refspec, HEAD, or @: pushes the current branch
    case "$repo_dir" in /*) ;; *) repo_dir="$cwd/$repo_dir" ;; esac
    current="$(git -C "$repo_dir" symbolic-ref --short HEAD 2>/dev/null || true)"
    for bare in "${default_branches[@]}"; do
      [ "$current" = "$bare" ] && return 0
      [ "$switches_to_default" = 1 ] && return 0  # an earlier segment switched to the default branch
    done
  fi
  return 1
}

# Read-only exemption. Off when the whole command can run text as code or fan out to another command.
exemption_allowed=1
runs_other_commands='(^|[^[:alnum:]_.-])(bash|sh|zsh|eval|source|xargs|parallel)([^[:alnum:]_-]|$)|-exec|`|\$[^A-Za-z0-9_]|>|(^|[[:space:]])\.[[:space:]]'
[[ "$command_text" =~ $runs_other_commands ]] && exemption_allowed=0

# Succeeds when the segment only reads: a "for ... in ..." header, or a known read-only tool.
is_read_only_segment() {  # <segment>
  local -a words
  local word
  # shellcheck disable=SC2206
  words=($1)
  while [ "${#words[@]}" -gt 0 ]; do
    case "${words[0]}" in do|then|else) words=("${words[@]:1}") ;; *) break ;; esac
  done
  [ "${#words[@]}" -gt 0 ] || return 1
  word="${words[0]//[\'\"]/}"
  case "$word" in
    for) [[ "${words[*]}" =~ ^for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in([[:space:]]|$) ]]; return ;;
  esac
  case "$word" in
    file) for word in "${words[@]}"; do word="${word//[\'\"\\]/}"; [[ ( "$word" == -*C* && "$word" != --* ) || "$word" == --co* ]] && return 1; done; return 0 ;;
    cat|head|tail|grep|wc|ls|stat|diff|nl) return 0 ;;
    git)
      words=("${words[@]:1}")
      while [ "${#words[@]}" -gt 0 ]; do
        case "${words[0]}" in
          -C) words=("${words[@]:2}") ;;
          --no-pager|-P|--no-optional-locks) words=("${words[@]:1}") ;;
          -*) return 1 ;;  # other global options take a separate value or set config
          diff|show|log|blame|status)  # --output=FILE writes a file
            for word in "${words[@]}"; do word="${word//[\'\"\\]/}"; [[ "$word" == --output* ]] && return 1; done
            return 0 ;;
          *) return 1 ;;
        esac
      done ;;
  esac
  return 1
}

# Sets $reason for one command segment.
judge_segment() {
  local segment="$1" deploy_command bare first_word
  for bare in "${default_branches[@]}"; do
    [[ "$segment" =~ ^[[:space:]]*${command_prefix}${optional_quote}([^[:space:]]*/)?git${optional_quote}${cf_flags}${space}(checkout|switch)([[:space:]]+-[^[:space:]]+)*${space}${optional_quote}${bare}${optional_quote}([^[:alnum:]_./-]|$) ]] && switches_to_default=1
  done
  if [[ "$segment" =~ ${start}gh${cf_flags}${space}pr${cf_flags}${space}merge ]]; then
    reason="a pull request merge"
  elif [[ "$segment" =~ ${start}gh${space}api.*pulls/[^[:space:]]+/merge ]]; then
    reason="a pull request merge through the API"
  elif [[ "$segment" =~ ${start}gh${cf_flags}${space}pr${cf_flags}${space}close.*([[:space:]]-d([[:space:]]|$)|--delete-branch) ]]; then
    reason="a pull request close with a remote branch delete"
  elif [[ "$segment" =~ ${start}gh${space}repo${space}delete ]]; then
    reason="a repository delete"
  elif [[ "$segment" =~ ${start}cf${cf_flags}${space}r2${cf_flags}${space}objects${cf_flags}${space}[a-z-]*delete ]]; then
    reason="an R2 object delete"
  elif [[ "$segment" =~ ${start}cf${cf_flags}${space}r2${cf_flags}${space}buckets${cf_flags}${space}delete ]]; then
    reason="an R2 bucket delete"
  elif [[ "$segment" =~ ${start}cf${cf_flags}${space}r2${cf_flags}${space}buckets${cf_flags}${space}jobs${cf_flags}${space}create ]]; then
    reason="an R2 bucket job (a prefixDelete job deletes objects or empties the bucket)"
  elif [[ "$segment" =~ ${start}[^[:space:]]*evidence-delete\.sh${optional_quote}([[:space:]]|$) && "$segment" != *"--dry-run"* ]]; then
    reason="an R2 evidence delete (evidence-delete.sh runs cf delete commands)"
  else
    for deploy_command in "npm publish" "gh release create" "docker push" "terraform apply" \
      "kubectl apply" "helm install" "helm upgrade" "vercel --prod" "vercel deploy --prod" \
      "pnpm publish" "yarn publish" "yarn npm publish" "cargo publish" "fly deploy" "firebase deploy" "wrangler deploy" "cf workers deploy"; do
      if [[ "$segment" =~ ${start}${deploy_command// /$space} ]]; then
        reason="a deploy or publish ($deploy_command)"
        return 0
      fi
    done
    # shellcheck disable=SC2086
    set -- $segment
    while [ "$#" -gt 0 ]; do
      first_word="${1//[\'\"]/}"
      if [ "${first_word##*/}" = "git" ] && push_is_risky "$@"; then
        reason="a git push to the default branch, a force push, or a remote delete"
        break
      fi
      shift
    done
  fi
  return 0
}

switches_to_default=0
separated="${command_text//[&|;()<>]/$'\n'}"
# The exemption holds only when every segment reads: text in one segment can reach another through a pipe or a loop variable.
if [ "$exemption_allowed" = 1 ]; then
  while IFS= read -r segment; do
    [[ "$segment" =~ ^[[:space:]]*(done|fi|\})?[[:space:]]*$ ]] && continue
    is_read_only_segment "$segment" || { exemption_allowed=0; break; }
  done <<< "$separated"
  [ "$exemption_allowed" = 0 ] || exit 0
fi
reason=""
while IFS= read -r segment; do
  judge_segment "$segment"
  [ -z "$reason" ] || break
done <<< "$separated"

[ -n "$reason" ] || exit 0

emit ask "wStack guard: $reason. This step cannot be undone. Ask the user first."
