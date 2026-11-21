#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
org_script="$repo_root/scripts/handover/resolve-org.sh"
service_script="$repo_root/scripts/handover/resolve-service.sh"
fixtures="$repo_root/tests/fixtures/handover"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
# Physical path, so it equals what git prints.
export HOME="$(cd "$work_dir" && pwd -P)"
export LIFEOS_ROOT="$HOME/My Vault"
mkdir -p "$LIFEOS_ROOT/01Project/Appier" "$LIFEOS_ROOT/01Project/BreakinCode"
appier_init="$LIFEOS_ROOT/01Project/Appier/handover_handler__initiation.md"
cp "$fixtures/initiation-block.md" "$appier_init"
echo '| my-svc | $HOME/Projects/Appier/my svc | Services/my-svc |' >> "$appier_init"
cat > "$LIFEOS_ROOT/01Project/BreakinCode/handover_handler__initiation.md" <<'INIT'
---
org: BreakinCode
workspace_root: $HOME/Projects/BreakinCode
github_orgs: [21-BreakinCode]
---
INIT

make_repo() {  # <path> [remote]
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  if [ -n "${2:-}" ]; then git -C "$1" remote add origin "$2"; fi
}
org_rc() { set +e; org_out="$(cd "$1" && bash "$org_script" 2>/dev/null)"; org_status=$?; set -e; }
service_rc() { set +e; service_out="$(bash "$service_script" "$@" 2>/dev/null)"; service_status=$?; set -e; }

make_repo "$HOME/elsewhere/svc" git@github.com:appier/svc.git
org_rc "$HOME/elsewhere/svc"
assert "org from remote, block list" '[ "$org_status" = 0 ] && [ "$org_out" = Appier ]'

make_repo "$HOME/elsewhere/wstack" https://github.com/21-BreakinCode/wStack.git
org_rc "$HOME/elsewhere/wstack"
assert "org from remote, inline list" '[ "$org_out" = BreakinCode ]'

make_repo "$HOME/Projects/Appier/x"
org_rc "$HOME/Projects/Appier/x"
assert "org from workspace_root" '[ "$org_out" = Appier ]'

git -C "$HOME/Projects/Appier/x" worktree add -q "$HOME/.herdr/worktrees/x/feat" -b feat
org_rc "$HOME/.herdr/worktrees/x/feat"
assert "org inside a worktree" '[ "$org_out" = Appier ]'

make_repo "$HOME/other/y"
org_rc "$HOME/other/y"
assert "org no match" '[ "$org_status" = 1 ]'

mkdir -p "$work_dir/novault"
set +e; (cd "$HOME/other/y" && LIFEOS_ROOT="$work_dir/novault" bash "$org_script" >/dev/null 2>&1); no_vault_status=$?; set -e
assert "vault unreachable exits 3" '[ "$no_vault_status" = 3 ]'

make_repo "$HOME/Projects/Appier/my svc"
service_rc "$HOME/Projects/Appier/my svc" Appier
assert "service with a space" '[ "$service_out" = "my-svc|Services/my-svc" ]'

git -C "$HOME/Projects/Appier/my svc" worktree add -q "$HOME/.herdr/worktrees/my svc/feat" -b feat
service_rc "$HOME/.herdr/worktrees/my svc/feat" Appier
assert "service inside a worktree" '[ "$service_out" = "my-svc|Services/my-svc" ]'

make_repo "$HOME/Projects/Appier/z"
service_rc "$HOME/Projects/Appier/z" Appier
assert "service not mapped" '[ "$service_status" = 1 ]'

service_rc "$HOME/Projects/Appier/z" Nope
assert "initiation missing" '[ "$service_status" = 2 ]'
finish
