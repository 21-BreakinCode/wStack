#!/usr/bin/env bash
# Open a pull request with GitHub copies of the evidence attached (gh 2.99.0+, `gh pr create --attach`).
# usage: pr-attach.sh --task-id <id> --title <t> --body-file <f> --max-mb <n> [--base <branch>] [--allow-ghes] <evidence files...>
# Copies go to $WSTACK_EVIDENCE_ROOT/<id>/gh/ (WSTACK_EVIDENCE_ROOT defaults to /tmp/wstack-evidence; tests override it).
# Not github.com and no --allow-ghes: creates the PR without attachments, prints "attachments skipped: not github.com".
# `gh pr create` fails but prints a URL: prints the URL and "attachment upload failed", exits 0.
set -euo pipefail

usage() { echo "usage: pr-attach.sh --task-id <id> --title <t> --body-file <f> --max-mb <n> [--base <b>] [--allow-ghes] <files...>" >&2; exit 2; }

task_id=""; title=""; body_file=""; max_mb=""; base=""; allow_ghes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task-id) [ $# -ge 2 ] || usage; task_id="$2"; shift 2 ;;
    --title) [ $# -ge 2 ] || usage; title="$2"; shift 2 ;;
    --body-file) [ $# -ge 2 ] || usage; body_file="$2"; shift 2 ;;
    --max-mb) [ $# -ge 2 ] || usage; max_mb="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || usage; base="$2"; shift 2 ;;
    --allow-ghes) allow_ghes=1; shift ;;
    --*) usage ;;
    *) break ;;
  esac
done
[ -n "$task_id" ] && [ -n "$title" ] && [ -n "$body_file" ] && [ -n "$max_mb" ] || usage
[ -f "$body_file" ] || { echo "body file not found: $body_file" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gh_dir="${WSTACK_EVIDENCE_ROOT:-/tmp/wstack-evidence}/$task_id/gh"

create_args=(--title "$title" --body-file "$body_file")
[ -z "$base" ] || create_args+=(--base "$base")

repo_url="$(gh repo view --json url -q .url)"
case "$repo_url" in
  https://github.com/*) attach_ok=1 ;;
  *) attach_ok="$allow_ghes" ;;
esac

if [ "$attach_ok" -eq 1 ]; then
  for evidence_file in "$@"; do
    gh_copy="$(bash "$script_dir/compress-media.sh" --target gh --max-mb "$max_mb" "$evidence_file" "$gh_dir" | tail -n 1)"
    create_args+=(--attach "$gh_copy")
  done
else
  echo "attachments skipped: not github.com"
fi

status=0
output="$(gh pr create "${create_args[@]}")" || status=$?
echo "$output"
if [ "$status" -ne 0 ]; then
  pr_url="$(printf '%s\n' "$output" | grep -Eo 'https?://[^ ]+' | tail -n 1 || true)"
  [ -n "$pr_url" ] || exit "$status"
  echo "attachment upload failed"
fi
