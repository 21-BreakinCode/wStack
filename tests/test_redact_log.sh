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
GET /cb#access_token=fr5&state=s
{"api_key": "zz1", "page": 2, "name": "x"}
{"token":"zz2","monkey": "m1","key_id": "kid1"}
{"Authorization":"Basic jj8","cookie":"sid=jj9","password":"pw \"q\" 3"}
{"key":"kk8","refresh_token":"rt1","id_token":"it1","client_secret":"cs1"}
GET /oauth?refresh_token=rtq1&client_secret=csq2&page=4
> apikey: hk1
> X-Goog-Api-Key: hk2
> X-Amz-Security-Token: hk3
{"accessToken":"jk1","refreshToken":"jk2","secret":"jk3","session_token":"jk4","private_key":"jk5"}
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
for secret in fr5 zz1 zz2 jj8 jj9 pw kk8 rt1 it1 cs1; do
  assert "secret $secret removed" '[[ "$out" != *"$secret"* ]]'
done
assert "fragment state kept" '[[ "$out" == *"#access_token=[REDACTED]&state=s"* ]]'
for name in api_key token Authorization cookie password key refresh_token id_token client_secret; do
  assert "json key $name kept" '[[ "$out" == *"\"$name\":"*"[REDACTED]"* ]]'
done
assert "json number kept" '[[ "$out" == *"\"page\": 2"* ]]'
assert "json other key kept" '[[ "$out" == *"\"name\": \"x\""* ]]'
assert "monkey unchanged" '[[ "$out" == *"\"monkey\": \"m1\""* ]]'
assert "key_id unchanged" '[[ "$out" == *"\"key_id\": \"kid1\""* ]]'
for secret in rtq1 csq2 hk1 hk2 hk3 jk1 jk2 jk3 jk4 jk5; do
  assert "secret $secret removed" '[[ "$out" != *"$secret"* ]]'
done
assert "page=4 kept" '[[ "$out" == *"page=4"* ]]'
finish
