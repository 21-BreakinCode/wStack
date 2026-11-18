#!/usr/bin/env bash
# Usage: preflight.sh base | preflight.sh plan <need>...
# needs: web video webp terminal r2 diagram. Reports only; never installs.
set -euo pipefail

CF_NODE_RANGE='^22.23.0 || ^24.22.0 || ^26.12.0'
failed=0

# true when $1 >= $2, comparing dot-separated numbers
version_ge() {
  local found_rest="$1" min_rest="$2" found_part min_part
  while [ -n "$found_rest$min_rest" ]; do
    found_part="${found_rest%%.*}"; min_part="${min_rest%%.*}"
    [ "${found_part:-0}" -gt "${min_part:-0}" ] && return 0
    [ "${found_part:-0}" -lt "${min_part:-0}" ] && return 1
    case "$found_rest" in *.*) found_rest="${found_rest#*.}" ;; *) found_rest="" ;; esac
    case "$min_rest" in *.*) min_rest="${min_rest#*.}" ;; *) min_rest="" ;; esac
  done
  return 0
}

first_version() { grep -oE '[0-9]+\.[0-9]+\.[0-9]+[-.0-9a-z]*' | head -1 || true; }

missing() { echo "MISSING $1: $2"; failed=1; }

# check <tool> <version command> <min version or empty> <install command>
check() {
  local tool="$1" version_command="$2" min="$3" install="$4" found version_output version_ran=1
  command -v "$tool" >/dev/null 2>&1 || { missing "$tool" "$install"; return; }
  version_output="$(eval "$version_command" 2>&1)" || version_ran=0
  found="$(printf '%s\n' "$version_output" | first_version)"
  # a printed version wins; a nonzero exit with no version means a broken binary
  [ "$version_ran" = "1" ] || [ -n "$found" ] || { missing "$tool" "$install"; return; }
  if [ -n "$min" ] && ! version_ge "${found:-0}" "$min"; then
    echo "OLD $tool ${found:-unknown} (need $min): $install"; failed=1; return
  fi
  echo "OK $tool ${found:-unknown}"
}

node_accepted_by_cf() {
  local major minor
  major="${1#v}"; major="${major%%.*}"
  case "$major" in
    22) version_ge "${1#v}" 22.23.0 ;;
    24) version_ge "${1#v}" 24.22.0 ;;
    26) version_ge "${1#v}" 26.12.0 ;;
    *) return 1 ;;
  esac
}

check_base() {
  check git 'git --version' '' 'xcode-select --install'
  check gh 'gh --version' 2.99.0 'brew upgrade gh'
  check node 'node --version' '' 'mise use -g node@26'
  check jq 'jq --version' '' 'brew install jq'
  check claude 'claude --version' 2.1.51 'claude update'
  local plugin_install='claude plugin marketplace add QingYunA/answer-me-with-html && claude plugin install answer-me-with-html@answer-me-with-html'
  local plugin_list=""
  command -v claude >/dev/null 2>&1 && plugin_list="$(claude plugin list 2>/dev/null || true)"
  case "$plugin_list" in
    *answer-me-with-html*) echo "OK answer-me-with-html plugin" ;;
    *) missing 'answer-me-with-html plugin' "$plugin_install" ;;
  esac
  local herdr_version=""
  command -v herdr >/dev/null 2>&1 && herdr_version="$(herdr --version 2>&1 | first_version || true)"
  if [ -n "$herdr_version" ]; then echo "OK herdr $herdr_version"
  else echo "WARN herdr: not found or broken, panes fall back to the current terminal: brew install herdr"
  fi
}

check_video() {
  check ffmpeg 'ffmpeg -version' '' 'brew install ffmpeg'
  command -v ffmpeg >/dev/null 2>&1 || return 0
  local encoders encoder
  encoders="$(ffmpeg -encoders 2>/dev/null || true)"
  for encoder in libx264 libx265; do
    case "$encoders" in
      *"$encoder"*) ;;
      *) missing "ffmpeg $encoder" 'brew install ffmpeg' ;;
    esac
  done
}

check_r2() {
  local node_found cf_install='npm i -g cf@1.0.0-rc.1, then cf auth login'
  check cf 'cf --version' '' "$cf_install"
  node_found="$(node --version 2>/dev/null || true)"
  if [ -z "$node_found" ] || ! node_accepted_by_cf "$node_found"; then
    echo "OLD node ${node_found:-unknown} (need $CF_NODE_RANGE): mise use -g node@26"; failed=1
  fi
  if command -v cf >/dev/null 2>&1; then
    # S4: logged-out `cf auth whoami` exits 0 and prints {"authenticated": false, ...}
    local whoami_json authenticated
    whoami_json="$(cf auth whoami 2>/dev/null || true)"
    authenticated="$(printf '%s' "$whoami_json" | jq -r '.authenticated' 2>/dev/null || true)"
    [ "$authenticated" = "true" ] || missing 'cf auth' 'cf auth login'
  fi
}

check_need() {
  case "$1" in
    web|diagram) check playwright-cli 'playwright-cli --version' '' 'npm i -g @playwright/cli@0.1.24' ;;
    video) check_video ;;
    webp) check cwebp 'cwebp -version' '' 'brew install webp' ;;
    terminal) check vhs 'vhs --version' '' 'brew install vhs' ;;
    r2) check_r2 ;;
    *) echo "unknown need: $1" >&2; exit 2 ;;
  esac
}

mode="${1:-}"
case "$mode" in
  base) check_base ;;
  plan)
    shift
    for need in "$@"; do check_need "$need"; done ;;
  *) echo "usage: preflight.sh base | plan <need>..." >&2; exit 2 ;;
esac
exit "$failed"
