#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
stub_bin="$work_dir/bin"
preflight="$repo_root/scripts/preflight.sh"

make_stub() {  # <name> <script body>
  rm -f "$stub_bin/$1"  # never write through a symlink
  printf '#!/bin/bash\n%s\n' "$2" > "$stub_bin/$1"
  chmod +x "$stub_bin/$1"
}

fresh_bin() {  # system utilities the script needs, plus stubs for every tool
  rm -rf "$stub_bin"; mkdir -p "$stub_bin"
  for util in dirname basename sed grep head tr cut sort cat yes env bash jq; do
    ln -s "$(command -v "$util")" "$stub_bin/$util"
  done
  make_stub git 'echo "git version 2.50.1"'
  make_stub gh 'echo "gh version 2.104.0 (2026-01-01)"'
  make_stub node 'echo "v26.13.1"'
  make_stub claude 'if [ "$1" = "plugin" ]; then echo "answer-me-with-html@answer-me-with-html  enabled"; else echo "2.1.327 (Claude Code)"; fi'
  make_stub yq 'echo "yq (https://github.com/mikefarah/yq/) version v4.54.3"'
  make_stub herdr 'echo "herdr 0.5.0"'
  make_stub playwright-cli 'if [ "$1" = "install-browser" ]; then printf "FFmpeg (playwright ffmpeg v1013)\n  Install location:    %s\n  Download url:        https://example.invalid/x.zip\n" "$FAKE_FFMPEG_DIR"; else echo "0.1.24"; fi'
  make_stub ffmpeg 'if [ "$1" = "-encoders" ]; then echo " V....D libx264"; echo " V....D libx265"; else echo "ffmpeg version 7.1"; fi'
  make_stub cwebp 'echo "1.5.0"'
  make_stub vhs 'echo "vhs version 0.9.0"'
  ln -s "$repo_root/tests/fixtures/bin/cf" "$stub_bin/cf"
  export FAKE_CF_AUTH=loggedin
  mkdir -p "$work_dir/ffmpeg-1013"; export FAKE_FFMPEG_DIR="$work_dir/ffmpeg-1013"
}

run_preflight() {  # sets output and rc
  rc=0; output="$(PATH="$stub_bin" "$BASH" "$preflight" "$@" 2>&1)" || rc=$?
}

fresh_bin
run_preflight base
assert "base all present exits 0" '[ "$rc" = "0" ]'
assert "base prints OK gh" 'echo "$output" | grep -q "^OK gh 2.104.0"'

fresh_bin; make_stub yq 'echo "yq 3.4.1"'
run_preflight base
assert "python yq exits 1" '[ "$rc" = "1" ]'
assert "python yq line" 'echo "$output" | grep -qx "MISSING yq: brew install yq"'

fresh_bin; rm "$stub_bin/yq"
run_preflight base
assert "missing yq line" 'echo "$output" | grep -qx "MISSING yq: brew install yq"'

fresh_bin; rm "$stub_bin/jq"
run_preflight base
assert "missing jq exits 1" '[ "$rc" = "1" ]'
assert "missing jq line" 'echo "$output" | grep -qx "MISSING jq: brew install jq"'

fresh_bin; make_stub gh 'echo "gh version 2.98.0 (2026-01-01)"'
run_preflight base
assert "old gh exits 1" '[ "$rc" = "1" ]'
assert "old gh line" 'echo "$output" | grep -q "^OLD gh 2.98.0 (need 2.99.0): brew upgrade gh"'

fresh_bin; make_stub claude 'if [ "$1" = "plugin" ]; then echo "other-plugin"; else echo "2.1.327 (Claude Code)"; fi'
run_preflight base
assert "missing plugin exits 1" '[ "$rc" = "1" ]'
assert "missing plugin line" 'echo "$output" | grep -q "^MISSING answer-me-with-html plugin: claude plugin marketplace add"'

fresh_bin; rm "$stub_bin/playwright-cli"
run_preflight base
assert "base without playwright-cli exits 1" '[ "$rc" = "1" ]'
assert "base names the playwright-cli install" 'echo "$output" | grep -qx "MISSING playwright-cli: npm i -g @playwright/cli@0.1.24"'

fresh_bin; rm "$stub_bin/herdr"
run_preflight base
assert "no herdr still exits 0" '[ "$rc" = "0" ]'
assert "no herdr warns" 'echo "$output" | grep -q "^WARN herdr"'

fresh_bin; make_stub node 'echo "v25.1.0"'
run_preflight plan r2
assert "r2 with node 25 exits 1" '[ "$rc" = "1" ]'
assert "r2 with node 25 names mise" 'echo "$output" | grep -q "mise use -g node@26"'

fresh_bin
run_preflight plan r2
assert "r2 all fine exits 0" '[ "$rc" = "0" ]'

fresh_bin; make_stub cf 'if [ "$1" = "auth" ]; then exit 1; else echo "1.0.0-rc.1"; fi'
run_preflight plan r2
assert "r2 whoami exit 1 exits 1" '[ "$rc" = "1" ] && echo "$output" | grep -q "^MISSING cf auth: cf auth login"'

fresh_bin; export FAKE_CF_AUTH=loggedout
run_preflight plan r2
assert "r2 logged out (exit 0, authenticated false) exits 1" '[ "$rc" = "1" ]'
assert "r2 logged out reports MISSING cf auth" 'echo "$output" | grep -qx "MISSING cf auth: cf auth login"'

fresh_bin; make_stub cf 'if [ "$1" = "auth" ]; then echo "not json at all"; else echo "1.0.0-rc.1"; fi'
run_preflight plan r2
assert "r2 whoami not JSON exits 1" '[ "$rc" = "1" ] && echo "$output" | grep -qx "MISSING cf auth: cf auth login"'

fresh_bin; export FAKE_CF_AUTH=loggedin
run_preflight plan r2
assert "r2 logged in (authenticated true) exits 0" '[ "$rc" = "0" ]'
assert "r2 logged in has no MISSING cf auth" '! echo "$output" | grep -q "MISSING cf auth"'

fresh_bin; make_stub ffmpeg 'if [ "$1" = "-encoders" ]; then echo " V....D libx264"; else echo "ffmpeg version 7.1"; fi'
run_preflight plan video
assert "video without libx265 exits 1" '[ "$rc" = "1" ]'

fresh_bin; rm "$stub_bin/playwright-cli"
run_preflight plan diagram
assert "diagram needs playwright-cli" '[ "$rc" = "1" ] && echo "$output" | grep -q "^MISSING playwright-cli: npm i -g @playwright/cli@0.1.24"'

fresh_bin
run_preflight plan web
assert "web with ffmpeg installed exits 0" '[ "$rc" = "0" ]'
assert "web prints OK playwright ffmpeg" 'echo "$output" | grep -qx "OK playwright ffmpeg"'

fresh_bin; export FAKE_FFMPEG_DIR="$work_dir/not-installed"
run_preflight plan web
assert "web without ffmpeg dir exits 1" '[ "$rc" = "1" ]'
assert "web without ffmpeg dir names the install command" 'echo "$output" | grep -qx "MISSING playwright ffmpeg: playwright-cli install-browser ffmpeg"'
run_preflight plan diagram
assert "diagram needs no playwright ffmpeg" '[ "$rc" = "0" ] && ! echo "$output" | grep -q "playwright ffmpeg"'

fresh_bin; make_stub playwright-cli 'if [ "$1" = "install-browser" ]; then echo "no location here"; else echo "0.1.24"; fi'
run_preflight plan web
assert "dry run without Install location line is MISSING" '[ "$rc" = "1" ] && echo "$output" | grep -q "^MISSING playwright ffmpeg"'

fresh_bin; make_stub playwright-cli 'if [ "$1" = "install-browser" ]; then exit 1; else echo "0.1.24"; fi'
run_preflight plan web
assert "failing dry run is MISSING" '[ "$rc" = "1" ] && echo "$output" | grep -q "^MISSING playwright ffmpeg"'

fresh_bin
run_preflight plan web video webp terminal r2 diagram
assert "all needs satisfied exits 0" '[ "$rc" = "0" ]'

fresh_bin; make_stub playwright-cli 'echo "0.1.24"; exit 1'
run_preflight plan web terminal
assert "failing version command still gives OK" 'echo "$output" | grep -q "^OK playwright-cli 0.1.24"'
assert "checks after a failing version command still run" 'echo "$output" | grep -q "^OK vhs"'

fresh_bin
make_stub claude 'if [ "$1" = "plugin" ]; then echo "answer-me-with-html@answer-me-with-html enabled"; yes "filler plugin line" | head -c 300000; else echo "2.1.327 (Claude Code)"; fi'
make_stub ffmpeg 'if [ "$1" = "-encoders" ]; then echo " V....D libx264"; echo " V....D libx265"; yes " V....D filler" | head -c 300000; else echo "ffmpeg version 7.1"; fi'
for repeat in 1 2 3; do
  run_preflight base
  assert "large plugin list still OK (run $repeat)" '[ "$rc" = "0" ] && echo "$output" | grep -q "^OK answer-me-with-html plugin"'
  run_preflight plan video
  assert "large encoder list still OK (run $repeat)" '[ "$rc" = "0" ]'
done

fresh_bin; make_stub jq 'exit 1'
run_preflight base
assert "broken jq exits 1" '[ "$rc" = "1" ]'
assert "broken jq reported as MISSING" 'echo "$output" | grep -qx "MISSING jq: brew install jq"'

fresh_bin; make_stub herdr 'exit 1'
run_preflight base
assert "broken herdr only warns" '[ "$rc" = "0" ] && echo "$output" | grep -q "^WARN herdr"'

run_preflight plan bogus
assert "unknown need exits 2" '[ "$rc" = "2" ]'
finish
