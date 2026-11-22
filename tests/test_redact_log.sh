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
printf 'caf\xe9 token=bad9&page=5\n' > "$work_dir/bad.log"
bad_status=0
bash "$script" "$work_dir/bad.log" "$work_dir/bad.out" || bad_status=$?
assert "invalid UTF-8 exits 0" '[ "$bad_status" -eq 0 ]'
assert "invalid UTF-8 log is redacted" '! LC_ALL=C grep -q bad9 "$work_dir/bad.out" && LC_ALL=C grep -q "page=5" "$work_dir/bad.out"'

# A3-14: short counters (names ending in tokens or count, and "Token: 5 requests") are not secrets.
# A3-15: non-string JSON secrets are redacted.
cat > "$work_dir/num.log" <<'LOG'
GET /x?max_tokens=4096&input_tokens=1200&token=abc99
Token: 5 requests
Token: 1234567
{"max_tokens": 4096, "input_tokens":1200, "accessToken": 12345678, "secret": true, "password": 1234567.5}
{"usage":{"input_tokens": 1200,"token_count": 7,"token": 7}}
?token=1234567&access_token=12&token_count=12
LOG
bash "$script" "$work_dir/num.log" "$work_dir/num.out"
num_out="$(cat "$work_dir/num.out")"
for kept in "max_tokens=4096" "input_tokens=1200" "Token: 5 requests" '"max_tokens": 4096' '"input_tokens":1200' '"input_tokens": 1200' '"token_count": 7' "token_count=12"; do
  assert "short counter kept: $kept" '[[ "$num_out" == *"$kept"* ]]'
done
for gone in abc99 1234567 12345678 true '"token": 7' "access_token=12"; do
  assert "value removed: $gone" '[[ "$num_out" != *"$gone"* ]]'
done
assert "json number secret becomes a string" '[[ "$num_out" == *"\"accessToken\": \"[REDACTED]\""* ]]'
assert "no marker byte left" '! LC_ALL=C grep -q "$(printf "\001")" "$work_dir/num.out"'

# Short secret values and a header value with a tail are still redacted
cat > "$work_dir/short.log" <<'LOG'
password: 123456
X-Api-Key: 123456
GET /verify?token=482913
password: 1234 my secret phrase
Token: 5 requests sk-live-abcdef
Cookie: 1 sid=abcdef
LOG
bash "$script" "$work_dir/short.log" "$work_dir/short.out"
short_out="$(cat "$work_dir/short.out")"
for gone in 123456 482913 "my secret phrase" sk-live-abcdef sid=abcdef; do
  assert "short or tailed secret removed: $gone" '[[ "$short_out" != *"$gone"* ]]'
done
finish
