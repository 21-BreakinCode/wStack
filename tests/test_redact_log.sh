#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
script="$repo_root/scripts/redact-log.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cat > "$work_dir/in.log" <<'LOG'
> authorization: Bearer abc123
> COOKIE: sid=1
< Set-Cookie: s=2
> x-api-key: k9
> Proxy-Authorization: Basic pp77
> X-Auth-Token: tt55
GET /v1/items?api_key=zz&page=2
GET /v1/items?page=3&access_token=at88&token=tk99&key=kk11&apikey=ak22
body: {"note":"see Bearer xyz789 here"}
LOG
bash "$script" "$work_dir/in.log" "$work_dir/out.log"
out="$(cat "$work_dir/out.log")"
for secret in abc123 sid=1 s=2 k9 zz pp77 tt55 at88 tk99 kk11 ak22 xyz789; do
  assert "secret $secret removed" '[[ "$out" != *"$secret"* ]]'
done
assert "page=2 kept" '[[ "$out" == *"page=2"* ]]'
assert "page=3 kept" '[[ "$out" == *"page=3"* ]]'
for name in authorization COOKIE Set-Cookie x-api-key Proxy-Authorization X-Auth-Token; do
  assert "header $name kept" '[[ "$out" == *"$name: [REDACTED]"* ]]'
done
assert "missing input fails" '! bash "$script" "$work_dir/nope" "$work_dir/x" 2>/dev/null'
finish
