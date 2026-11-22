#!/usr/bin/env bash
# Uploads every file in --dir to R2 under evidence/<task_id>/ with cf and prints one https://<domain>/... line per file.
# Never makes a presigned URL (spec section 12.4).
set -euo pipefail

task_id="" dir="" bucket="" domain="" repo="" local_only_repos="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task-id) task_id="${2:-}"; shift 2 ;;
    --dir) dir="${2:-}"; shift 2 ;;
    --bucket) bucket="${2:-}"; shift 2 ;;
    --domain) domain="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --local-only-repos) local_only_repos="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "evidence-upload: unknown argument: $1" >&2; exit 1 ;;
  esac
done

task_id_pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z][a-z0-9-]{0,31}$'
if ! [[ "$task_id" =~ $task_id_pattern ]]; then
  echo "evidence-upload: invalid task id '$task_id' (expected YYYY-MM-DD-slug)" >&2
  exit 1
fi
[ -d "$dir" ] || { echo "evidence-upload: --dir is not a folder: $dir" >&2; exit 1; }

# Redact in place before anything leaves the Mac or lands in the vault or the PR.
for path in "$dir"/*; do
  [ -f "$path" ] && [[ "$(file -b --mime-type "$path")" == text/* ]] || continue
  bash "$(dirname "${BASH_SOURCE[0]}")/redact-log.sh" "$path" "$path"
done

if [ -z "$bucket" ]; then
  echo "local only: $dir"
  echo "r2_bucket is empty, so nothing was uploaded."
  exit 0
fi
if [ -n "$repo" ]; then  # an empty repo would match the ",," of an empty list
  case ",$local_only_repos," in
    *",$repo,"*) echo "local only: $dir"; echo "repo $repo is in local_evidence_only_repos, so nothing was uploaded."; exit 0 ;;
  esac
fi
if [ -z "$domain" ]; then
  echo "local only: $dir"
  echo "evidence_domain is empty, so nothing was uploaded. Set evidence_domain in the plugin config."
  exit 0
fi

for path in "$dir"/*; do
  [ -f "$path" ] || continue
  name="${path##*/}"
  key="evidence/$task_id/$name"
  mime="$(file -b --mime-type "$path")"
  if [ "$dry_run" = 1 ]; then
    printf 'cf r2 objects put %q --bucket-name %q --file %q --content-type %q\n' "$key" "$bucket" "$path" "$mime"
  else
    cf r2 objects put "$key" --bucket-name "$bucket" --file "$path" --content-type "$mime" >/dev/null
  fi
  echo "https://$domain/evidence/$task_id/$(jq -rn --arg name "$name" '$name|@uri')"
done
