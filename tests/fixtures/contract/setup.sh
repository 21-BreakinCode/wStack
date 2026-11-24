#!/usr/bin/env bash
# Build a contract test world in <dir>. Prints the path of a shell file that sets
# ORIGIN, REPO, VAULT, CONTRACT, FIRST_COMMIT, ORG_DIR.
set -euo pipefail
dir="${1:?usage: setup.sh <dir>}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd -P)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

ORIGIN="$dir/origin.git"
REPO="$dir/ws/svc"
VAULT="$dir/vault"
ORG_DIR="$VAULT/01Project/Acme"
CONTRACT="$ORG_DIR/Services/svc/svc.contract.yaml"

git init -q --bare -b main "$ORIGIN"
mkdir -p "$dir/ws"
git clone -q "$ORIGIN" "$REPO" 2>/dev/null
git -C "$REPO" checkout -q -b main 2>/dev/null || true
mkdir -p "$REPO/cmd" "$REPO/api" "$REPO/docs" "$REPO/tests"
echo 'package main' > "$REPO/cmd/main.go"
echo 'package api' > "$REPO/api/routes.go"
echo '# PRD' > "$REPO/docs/PRD.md"
echo 'package tests' > "$REPO/tests/a_test.go"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "commit 1"
git -C "$REPO" push -q -u origin main 2>/dev/null
FIRST_COMMIT="$(git -C "$REPO" rev-parse HEAD)"

mkdir -p "$(dirname "$CONTRACT")"
cat > "$ORG_DIR/handover_handler__initiation.md" <<INIT
---
org: Acme
workspace_root: $dir/ws
github_orgs: [acme-org]
tags: [type/config]
---

# Acme initiation

## Service Mapping

| app_name | repo_path | lifeos_subpath |
| --- | --- | --- |
| svc | $REPO | Services/svc |
INIT
cat > "$CONTRACT" <<DOC
app_name: svc
repo: acme-org/svc
base_branch: main
verified_commit: "$FIRST_COMMIT"
verified_at: "2026-11-21T10:00:00Z"
pending: []
ignore: ["tests/**"]
tags: [type/contract]
summary: Test service.
sections:
  team_docs:
    sources: [docs/PRD.md]
  abilities:
    sources: [cmd/**]
    items: []
  interfaces:
    sources: [api/**]
    items: []
  depends_on:
    sources: []
    items: []
  consumers:
    items: []
  gotchas:
    items: []
  open_questions:
    items: []
planned: []
DOC

out="$dir/world.env"
printf 'ORIGIN=%q\nREPO=%q\nVAULT=%q\nCONTRACT=%q\nFIRST_COMMIT=%q\nORG_DIR=%q\n' \
  "$ORIGIN" "$REPO" "$VAULT" "$CONTRACT" "$FIRST_COMMIT" "$ORG_DIR" > "$out"
echo "$out"
