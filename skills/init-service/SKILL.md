---
name: init-service
description: "Per-repo setup. Adds the current repo to the service mapping table and creates the ./handover symlink into LifeOS."
allowed-tools: ["Bash", "Read", "Write", "Edit", "AskUserQuestion"]
disable-model-invocation: true
---

# /wstack:init-service

One-time per repo. It resolves the current org, and finds or appends the service mapping row for this repo. If the LifeOS handover folder is missing, it creates one. It symlinks `./handover` to that folder, and writes `/handover` to the local git exclude file.

## Vault location

Resolve the vault path. Take the first value that is set and is not a literal `${user_config...}` text, in this order: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`. Print the two shell variables in one call:

```sh
printf '%s\n' "VAULT_PATH WSTACK=${WSTACK_VAULT_PATH:-} EVAL=${EVAL_WSTACK_VAULT_PATH:-}"
```

If no value is set, ask the user for it and stop. If the value is a relative path, make it absolute with `cd <value> && pwd`. Each Bash call is a new shell. Start each Bash call that needs the vault with `vault=<the absolute path>; export LIFEOS_ROOT="$vault"`.

## Flow

### Phase 1 — Resolve ORG

```bash
ORG=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/resolve-org.sh") || {
    rc=$?
    [ "$rc" -eq 3 ] && { echo "Vault not reachable at $vault. Check the vault path and stop."; exit 3; }
    ORG=""
}
```

- If `$ORG` is empty, tell the user "Did not auto-detect an ORG. If this is a new ORG, run /wstack:init-org first. Otherwise, pick from the existing ORGs." Then use `AskUserQuestion` to list the ORG folders under `$vault/01Project/`. If the user picks one with no initiation.md, stop and tell them to run `/wstack:init-org $ORG` first.

Report: "Org: $ORG".

### Phase 2 — Verify initiation.md exists

```bash
INIT="$vault/01Project/$ORG/handover_handler__initiation.md"
[ -f "$INIT" ] || { echo "Run /wstack:init-org first — $INIT missing"; exit 1; }
```

### Phase 3 — Resolve service mapping

```bash
RESULT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/resolve-service.sh" "$PWD" "$ORG") && EXIT=$? || EXIT=$?
```

- **Exit 0:** parse `app_name|lifeos_subpath` from `$RESULT`. Report "Mapped: $APP_NAME → $LIFEOS_SUBPATH" and skip to Phase 5.
- **Exit 1:** the repo is not mapped yet. Continue to Phase 4.
- **Exit 2 or 3:** report the error and stop.

### Phase 4 — Collect new mapping row values

Find the repository root and the main checkout. They differ in a worktree and in a subfolder:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
```

Compute defaults:
- `DEFAULT_APP_NAME` = `basename "$MAIN_CHECKOUT"`, used verbatim in kebab-case, used verbatim in kebab-case (for example, `creative-studio` → `creative-studio`, `bust-backend` → `bust-backend`). If the folder name is not kebab-case, lowercase it and replace `_`, spaces, and camelCase boundaries with `-`.
- `DEFAULT_LIFEOS_SUBPATH` = `Services/$DEFAULT_APP_NAME`.

Ask with `AskUserQuestion` (batched, 2 questions in one call). The second question uses `$DEFAULT_APP_NAME`, not the answer to the first, because batched questions resolve at the same time:

1. `header: "app_name"`, `question: "App name for this repo?"`, options: `[$DEFAULT_APP_NAME]`, `[Other...]`
2. `header: "lifeos path"`, `question: "LifeOS subpath under $ORG/?"`, options: `[Services/$DEFAULT_APP_NAME]`, `[Other...]`

For an "Other..." answer, follow up with a free-form `AskUserQuestion`. If the user picked a non-default `app_name` in question 1 but accepted the default in question 2 (`Services/$DEFAULT_APP_NAME`), ask once more: "Use `Services/<app_name>` instead?" Adjust the answer to match.

If `$MAIN_CHECKOUT` starts with `$HOME`, write the row repo_path in the `$HOME/...` form. A new row for the `## Service Mapping` table in `$INIT` looks like this:

```
| new-app | $HOME/Projects/Appier/appier/new-app | Services/new-app |
```

Single-space padding is enough. Obsidian tables tolerate it.

### Phase 4a — Confirm with user

`AskUserQuestion`:
- `question`: "Append this row to $INIT and create $vault/01Project/$ORG/$LIFEOS_SUBPATH/handover/?\n| $APP_NAME | $MAIN_CHECKOUT | $LIFEOS_SUBPATH |"
- `options`:
  - "Yes, write it"
  - "No, abort"

If the user picks "No, abort", stop. Do not write the row and do not run Phase 5.

### Phase 5 — Write the row and create the LifeOS handover folder

If the user said yes:

Use `Edit` to append the new row from Phase 4 to `$INIT`. If the table is empty, append it after the separator row. Otherwise, append it after the last existing data row. Keep all other content.

```bash
mkdir -p "$vault/01Project/$ORG/$LIFEOS_SUBPATH/handover"
```

### Phase 6 — Symlink ./handover

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/ensure-symlink.sh" \
    "$REPO_ROOT/handover" \
    "$vault/01Project/$ORG/$LIFEOS_SUBPATH/handover"
EXIT=$?
```

Handle exit codes:
- 0: continue.
- 1: `./handover/` exists with content. Stop and report. Do not destroy data.
- 3: the target folder is missing. Stop and report.
- 4: the symlink exists and points elsewhere. `AskUserQuestion`: `[Keep existing]`, `[Overwrite (force)]`, `[Abort]`. If the user picks overwrite, run the script again with `force`.

### Phase 7 — Local exclude

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/ensure-exclude.sh" "$REPO_ROOT"`. Report its output.

### Phase 8 — Report

```
✓ Service initialized:
    ORG:            $ORG
    APP_NAME:       $APP_NAME
    LIFEOS path:    $vault/01Project/$ORG/$LIFEOS_SUBPATH/handover/
    Symlink:        $REPO_ROOT/handover -> (above)
    Local exclude:  /handover (added | already present)

Next: /wstack:create-handover <topic>
```

## Non-negotiable rules

- Never destroy a non-empty `./handover/` folder. If there is a conflict, stop and ask the user.
- Service mapping rows are append-only via this command. Never rewrite existing rows.
- The command never edits `.gitignore`. It writes `/handover` to the local exclude file, which git never commits.
- BustDice currently uses `Devops/` instead of `Services/`. If the user picks a `lifeos_subpath` that does not start with `Services/`, warn and allow it.
