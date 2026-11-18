#!/usr/bin/env bash
# Live round trip in the real bucket. Not run by run-all. Touches only evidence/<self-test id>/.
# Needs cf on PATH (Node 26 first), a logged-in cf, and WSTACK_R2_BUCKET.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/_assert.sh"

bucket="${WSTACK_R2_BUCKET:-}"
[ -n "$bucket" ] || { echo "SKIP: WSTACK_R2_BUCKET is unset"; exit 0; }
command -v cf >/dev/null 2>&1 || { echo "SKIP: cf is not on PATH"; exit 0; }
whoami_json="$(cf auth whoami 2>/dev/null || true)"
[ "$(jq -r '.authenticated // false' <<< "$whoami_json" 2>/dev/null || echo false)" = "true" ] || { echo "SKIP: cf is not logged in"; exit 0; }

task_id="$(date +%Y-%m-%d)-wstack-selftest-$RANDOM$RANDOM"
prefix="evidence/$task_id/"
work_dir="$(mktemp -d)"
cleanup() { bash "$repo_root/scripts/evidence-delete.sh" --task-id "$task_id" --bucket "$bucket" >/dev/null 2>&1 || true; rm -rf "$work_dir"; }
trap cleanup EXIT

echo "selftest hello" > "$work_dir/note.txt"
list_keys() { cf r2 objects list --bucket-name "$bucket" --prefix "$prefix" | jq -r '.[].key'; }

out="$(bash "$repo_root/scripts/evidence-upload.sh" --task-id "$task_id" --dir "$work_dir" --bucket "$bucket" --domain evidence.example.invalid --repo o/r --local-only-repos "")"
echo "upload output: $out"
assert "upload prints url" '[[ "$out" == "https://evidence.example.invalid/${prefix}note.txt" ]]'
keys_after_upload="$(list_keys)"
echo "listed after upload: $keys_after_upload"
assert "object is listed" '[ "$keys_after_upload" = "${prefix}note.txt" ]'

delete_out="$(bash "$repo_root/scripts/evidence-delete.sh" --task-id "$task_id" --bucket "$bucket")"
echo "delete output: $delete_out"
keys_after_delete="$(list_keys)"
assert "object is gone" '[ -z "$keys_after_delete" ]'
finish
