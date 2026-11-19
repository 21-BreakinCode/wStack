#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
script="$repo_root/scripts/free-agent-slug.sh"

# fake herdr: agent names listed in $TAKEN (space separated) exist
mkdir -p "$work_dir/bin"
cat > "$work_dir/bin/herdr" <<'FAKE'
#!/usr/bin/env bash
args=("$@"); [ "${args[0]}" = "--session" ] && args=("${args[@]:2}")
[ "${args[0]} ${args[1]}" = "agent get" ] || exit 9
case " $TAKEN " in *" ${args[2]} "*) exit 0 ;; *) exit 1 ;; esac
FAKE
chmod +x "$work_dir/bin/herdr"
export PATH="$work_dir/bin:$PATH" WSTACK_HERDR_SESSION=wstack-test

out="$(HERDR_ENV=1 TAKEN="" bash "$script" fix-login)"
assert "free slug is kept" '[ "$out" = fix-login ]'
out="$(HERDR_ENV=1 TAKEN="fix-login fix-login-2" bash "$script" fix-login)"
assert "taken slugs get the next number" '[ "$out" = fix-login-3 ]'
long="abcdefghijklmnopqrstuvwxyz-abcdef"
out="$(HERDR_ENV=1 TAKEN="${long:0:32}" bash "$script" "${long:0:32}")"
assert "suffix keeps the slug at 32 characters" '[ "${#out}" -le 32 ] && [ "${out: -2}" = -2 ]'
out="$(HERDR_ENV= TAKEN="fix-login" bash "$script" fix-login)"
assert "outside herdr the slug is kept" '[ "$out" = fix-login ]'
bad_exit=0
HERDR_ENV=1 TAKEN="" bash "$script" "Bad Slug" >/dev/null 2>&1 || bad_exit=$?
assert "bad slug exits 1" '[ "$bad_exit" -eq 1 ]'
finish
