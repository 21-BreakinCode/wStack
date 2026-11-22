#!/usr/bin/env bash
# Open a pull request with GitHub copies of the evidence attached (gh 2.99.0+, `gh pr create --attach`).
# usage: pr-attach.sh --task-id <id> --title <t> --body-file <f> --max-mb <n> [--base <branch>] [--allow-ghes] [--repo <owner/repo> --local-only-repos <list>] <evidence files...>
# Copies go to $WSTACK_EVIDENCE_ROOT/<id>/gh/ (WSTACK_EVIDENCE_ROOT defaults to /tmp/wstack-evidence; tests override it).
# Not github.com and no --allow-ghes: creates the PR without attachments, prints "attachments skipped: not github.com".
# Repo in --local-only-repos: creates the PR without attachments, prints "attachments skipped: repo <repo> is in local_evidence_only_repos".
# A file that cannot be compressed (or fit under --max-mb) is skipped; the PR is still created,
# and "attachment upload failed: <file>" is printed for it.
# `gh pr create` fails but prints a URL (partial upload): prints the URL and "attachment upload failed", exits 0.
# Each run starts with a fresh gh/ folder. Every gh copy gets a per-index prefix (01-, 02-, ...)
# so two inputs never share an output path. '#' in a name becomes '_' (gh reads '#' as alt text).
# Exit codes: 0 PR created (attachments may have failed), 1 bad input, 2 usage,
# 3 PR not created (gh failed without printing a URL; no retry, to avoid a duplicate PR).
set -euo pipefail

usage() { echo "usage: pr-attach.sh --task-id <id> --title <t> --body-file <f> --max-mb <n> [--base <b>] [--allow-ghes] <files...>" >&2; exit 2; }

task_id=""; task_id_given=0; title=""; body_file=""; max_mb=""; base=""; allow_ghes=0; repo=""; local_only_repos=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task-id) [ $# -ge 2 ] || usage; task_id="$2"; task_id_given=1; shift 2 ;;
    --title) [ $# -ge 2 ] || usage; title="$2"; shift 2 ;;
    --body-file) [ $# -ge 2 ] || usage; body_file="$2"; shift 2 ;;
    --max-mb) [ $# -ge 2 ] || usage; max_mb="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || usage; base="$2"; shift 2 ;;
    --allow-ghes) allow_ghes=1; shift ;;
    --repo) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;;
    --local-only-repos) [ $# -ge 2 ] || usage; local_only_repos="$2"; shift 2 ;;
    --*) usage ;;
    *) break ;;
  esac
done
[ "$task_id_given" -eq 1 ] && [ -n "$title" ] && [ -n "$body_file" ] && [ -n "$max_mb" ] || usage
task_id_pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z][a-z0-9-]{0,31}$'
if ! [[ "$task_id" =~ $task_id_pattern ]]; then
  echo "pr-attach: invalid task id '$task_id' (expected YYYY-MM-DD-slug)" >&2
  exit 1
fi
[ -f "$body_file" ] || { echo "body file not found: $body_file" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gh_dir="${WSTACK_EVIDENCE_ROOT:-/tmp/wstack-evidence}/$task_id/gh"
if [ -d "$gh_dir" ]; then  # each run deletes gh/, so an input inside it would be lost
  gh_dir_real="$(cd "$gh_dir" && pwd -P)"
  for evidence_file in "$@"; do
    case "$(cd "$(dirname "$evidence_file")" 2>/dev/null && pwd -P)/" in
      "$gh_dir_real"/*) echo "pr-attach: input is inside the gh/ folder, which each run deletes: $evidence_file. Pass the top-level evidence files." >&2; exit 1 ;;
    esac
  done
fi

create_args=(--title "$title" --body-file "$body_file")
[ -z "$base" ] || create_args+=(--base "$base")

repo_url="$(gh repo view --json url -q .url)"
case "$repo_url" in
  https://github.com/*) attach_ok=1 ;;
  *) attach_ok="$allow_ghes" ;;
esac
skip_reason="not github.com"
if bash "$script_dir/repo-is-local-only.sh" "$repo" "$local_only_repos"; then
  attach_ok=0
  skip_reason="repo $repo is in local_evidence_only_repos"
fi

failed_files=()
copy_index=0
if [ "$attach_ok" -eq 1 ]; then
  rm -rf "$gh_dir"
  mkdir -p "$gh_dir/src"
  for evidence_file in "$@"; do
    copy_index=$((copy_index + 1))
    safe_name="$(printf '%02d-%s' "$copy_index" "$(basename "$evidence_file")")"
    safe_name="${safe_name//#/_}"
    source_file="$gh_dir/src/$safe_name"
    cp "$evidence_file" "$source_file"
    if gh_copy="$(bash "$script_dir/compress-media.sh" --target gh --max-mb "$max_mb" "$source_file" "$gh_dir" | tail -n 1)" && [ -n "$gh_copy" ]; then
      create_args+=(--attach "$gh_copy")
    else
      failed_files+=("$evidence_file")
    fi
  done
else
  echo "attachments skipped: $skip_reason"
fi

error_file="$(mktemp)"
trap 'rm -f "$error_file"' EXIT
status=0
output="$(gh pr create "${create_args[@]}" 2>"$error_file")" || status=$?
echo "$output"
pr_url="$(printf '%s\n' "$output" | grep -Eo 'https?://[^ ]+' | tail -n 1 || true)"
if [ "$status" -ne 0 ] && [ -z "$pr_url" ]; then
  echo "pull request not created: $(cat "$error_file")" >&2
  exit 3
fi
for failed_file in ${failed_files[@]+"${failed_files[@]}"}; do
  echo "attachment upload failed: $failed_file"
done
if [ "$status" -ne 0 ]; then
  echo "attachment upload failed"
fi
