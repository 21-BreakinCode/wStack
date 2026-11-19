#!/usr/bin/env bash
# Deletes every object under evidence/<task_id>/ with cf: list the prefix, then bulk-delete by key list (at most 1000 keys per call).
# Never uses bulk-delete --prefix, which starts a prefix-delete job.
set -euo pipefail

task_id="" bucket="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task-id) task_id="${2:-}"; shift 2 ;;
    --bucket) bucket="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "evidence-delete: unknown argument: $1" >&2; exit 1 ;;
  esac
done

task_id_pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z][a-z0-9-]{0,31}$'
if ! [[ "$task_id" =~ $task_id_pattern ]]; then
  echo "evidence-delete: invalid task id '$task_id' (expected YYYY-MM-DD-slug)" >&2
  exit 1
fi
[ -n "$bucket" ] || { echo "evidence-delete: --bucket is required" >&2; exit 1; }

prefix="evidence/$task_id/"
if [ "$dry_run" = 1 ]; then
  printf 'cf r2 objects list --bucket-name %q --prefix %q --per-page 1000\n' "$bucket" "$prefix"
  printf 'cf r2 objects bulk-delete --bucket-name %q --body <JSON array of the listed keys, at most 1000> --force\n' "$bucket"
  exit 0
fi

# A listing page holds at most 1000 keys. Delete it and list again until the prefix is empty.
previous_listing="" deleted_count=0
for _round in $(seq 1 1000); do
  keys_json="$(cf r2 objects list --bucket-name "$bucket" --prefix "$prefix" --per-page 1000 | jq -c --arg prefix "$prefix" 'if type == "array" then [.[].key | select(startswith($prefix))] | .[:1000] else error("cf list output is not a JSON array") end')"
  if [ "$keys_json" = "[]" ]; then
    if [ "$deleted_count" = 0 ]; then echo "nothing found under $prefix"; else echo "deleted $deleted_count objects under $prefix"; fi
    exit 0
  fi
  if [ "$keys_json" = "$previous_listing" ]; then
    echo "evidence-delete: the same keys are still listed after a delete under $prefix" >&2
    exit 1
  fi
  cf r2 objects bulk-delete --bucket-name "$bucket" --body "$keys_json" --force >/dev/null
  deleted_count=$((deleted_count + $(jq 'length' <<< "$keys_json")))
  previous_listing="$keys_json"
done
echo "evidence-delete: too many delete rounds under $prefix" >&2
exit 1
