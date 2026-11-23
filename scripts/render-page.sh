#!/usr/bin/env bash
# Usage: render-page.sh <draft.md> <out.html> [--theme-file <theme.json>]
# Renders a draft with answer-me-with-html (template doc), then checks the page at 375 px.
# Exit 0 rendered and fits, 1 too wide (width on stdout), 2 am.mjs not found, render failed, a missing draft or theme file, or an unknown third argument.
# WSTACK_AMJS (or EVAL_WSTACK_AMJS, the only name an eval case can set) overrides the am.mjs path.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
install_hint="install: claude plugin marketplace add QingYunA/answer-me-with-html && claude plugin install answer-me-with-html@answer-me-with-html"
fail() { echo "render-page: $1" >&2; exit 2; }

draft="${1:-}" out_html="${2:-}" theme_file=""
[ -f "$draft" ] && [ -n "$out_html" ] || fail "usage: render-page.sh <draft.md> <out.html> [--theme-file <theme.json>]"
if [ "${3:-}" = "--theme-file" ]; then
  theme_file="${4:-}"
  [ -f "$theme_file" ] || fail "theme file not found: ${4:-}"
elif [ "$#" -gt 2 ]; then
  fail "unknown argument: $3"
fi

amjs="${WSTACK_AMJS:-${EVAL_WSTACK_AMJS:-}}"
if [ -z "$amjs" ]; then
  plugin_list="$(claude plugin list --json 2>/dev/null)" || fail "claude plugin list failed. $install_hint"
  install_path="$(jq -r '[.[] | select(.id == "answer-me-with-html@answer-me-with-html" and .enabled == true)] | first | .installPath // empty' <<<"$plugin_list")" || fail "unreadable plugin list"
  [ -n "$install_path" ] || fail "answer-me-with-html is not installed and enabled. $install_hint"
  amjs="$install_path/answer-me-with-html/scripts/am.mjs"
fi
[ -f "$amjs" ] || fail "am.mjs not found: $amjs. $install_hint"

theme_args=()
if [ -n "$theme_file" ]; then
  theme_home="$(mktemp -d)"
  trap 'rm -rf "$theme_home"' EXIT
  mkdir -p "$theme_home/themes"
  cp "$theme_file" "$theme_home/themes/"
  theme_name="$(basename "$theme_file" .json)"
  theme_args=(--theme "$theme_name")
  export AM_HOME="$theme_home"
fi

node "$amjs" render "$draft" -o "$out_html" --no-open --template doc ${theme_args[@]+"${theme_args[@]}"} >&2 || fail "render failed. $install_hint"
[ -s "$out_html" ] || fail "render produced no page: $out_html"

bash "$script_dir/check-page-width.sh" "$out_html" 375
