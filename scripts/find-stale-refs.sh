#!/usr/bin/env bash
# Usage: find-stale-refs.sh --repo <dir> --base <ref> [--old <text>]...
# Lists the tracked files at HEAD that still name an old path or an old text.
# Old forms: every --old value, and the old path of each R and D entry of
# git diff --name-status -M <base>...HEAD.
# Prints <file>:<line>: <old form>. Exit 0: no hit. Exit 1: hits. Exit 2: bad input.
set -euo pipefail

repo=""
base=""
old_forms_file="$(mktemp)"
hits_file="$(mktemp)"
trap 'rm -f "$old_forms_file" "$hits_file"' EXIT

usage_error() {
  echo "find-stale-refs.sh: $1" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ "$#" -ge 2 ] || usage_error "--repo needs a value"; repo="$2"; shift 2 ;;
    --base) [ "$#" -ge 2 ] || usage_error "--base needs a value"; base="$2"; shift 2 ;;
    --old) [ "$#" -ge 2 ] || usage_error "--old needs a value"; printf '%s\n' "$2" >>"$old_forms_file"; shift 2 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$repo" ] && [ -n "$base" ] || usage_error "usage: --repo <dir> --base <ref> [--old <text>]..."
[ "$(git -C "$repo" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || usage_error "not a git work tree: $repo"
git -C "$repo" rev-parse --verify --quiet "${base}^{commit}" >/dev/null || usage_error "unknown base: $base"

git -C "$repo" diff --name-status -M "$base"...HEAD |
  awk -F '\t' '$1 ~ /^R/ || $1 == "D" { print $2 }' >>"$old_forms_file"

while IFS= read -r old_form; do
  [ -n "$old_form" ] || continue
  { git -C "$repo" grep -n -F -e "$old_form" -- . ':(exclude)CHANGELOG.md' ':(exclude)docs/decisions.md' ':(exclude)docs/superpowers' || true; } |
    OLD_FORM="$old_form" awk '{ i = index($0, ":"); j = index(substr($0, i + 1), ":"); print substr($0, 1, i + j - 1) ": " ENVIRON["OLD_FORM"] }' >>"$hits_file"
done <"$old_forms_file"

sorted_hits="$(sort -u "$hits_file")"
[ -n "$sorted_hits" ] || exit 0
printf '%s\n' "$sorted_hits"
exit 1
