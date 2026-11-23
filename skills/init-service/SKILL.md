---
name: init-service
description: "Per-repo setup. Adds a repo to the service mapping table and creates the ./handover symlink into LifeOS. Takes repo paths, or --check for a read-only check of every mapped row."
argument-hint: "[<repo-path> ...] | --check"
allowed-tools: ["Bash", "Read", "Write", "Edit", "AskUserQuestion"]
disable-model-invocation: true
---

# /wstack:init-service

One-time per repo. It resolves the org of the repo, and finds or appends the service mapping row for the repo. If the LifeOS handover folder is missing, it creates one. It symlinks `./handover` to that folder, and writes `/handover` to the local git exclude file. Last, it offers to set up the service contract. It works on the current folder, or on each repo path that the user gives. `--check` reports the state of every mapped row and changes nothing.

## Vault location

Resolve the vault path. Take the first value that is set and is not a literal `${user_config...}` text, in this order: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`. Print the two shell variables in one call:

```sh
printf '%s\n' "VAULT_PATH WSTACK=${WSTACK_VAULT_PATH:-} EVAL=${EVAL_WSTACK_VAULT_PATH:-}"
```

If no value is set, ask the user for it and stop. If the value is a relative path, make it absolute with `cd <value> && pwd`. Each Bash call is a new shell. Start each Bash call that needs the vault with `vault=<the absolute path>; export LIFEOS_ROOT="$vault"`.

## Arguments

Read `$ARGUMENTS`:

- Empty: one target, the current folder (`$PWD`).
- `--check`: run "Check mode" below, then stop.
- One or more paths: the targets, in the order given. A path with a space must be quoted. Expand a leading `~` to `$HOME`. Make each relative path absolute against `$PWD`.

Test each target before Phase 1:

```bash
[ "$(git -C "$TARGET" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && echo "ok: $(git -C "$TARGET" rev-parse --show-toplevel)" || echo "not a git work tree: $TARGET"
```

Drop each target that is not a git work tree, and list it under `Skipped:` in the Phase 9 report. If two targets print the same repo root, keep the first one only. Run Phases 1 to 8 for each other target, one target at a time. An error or a "No" in one target stops that target only. Then go on to the next target. A vault that is not reachable (Phase 1, exit 3) stops the whole run. Each Bash call is a new shell, so start each call that reads the repo with `TARGET=<the absolute path>`.

## Flow

### Phase 1 — Resolve ORG

```bash
ORG=$(cd "$TARGET" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/resolve-org.sh") || {
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

Find the repository root and the main checkout. They differ in a worktree and in a subfolder:

```bash
REPO_ROOT="$(git -C "$TARGET" rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(dirname "$(git -C "$TARGET" rev-parse --path-format=absolute --git-common-dir)")"
```

Each Bash call is a new shell. If Phase 6 or Phase 7 runs in a later Bash call, set these two variables again there. Phase 8 needs only `REPO_ROOT` and `vault`.

```bash
RESULT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/resolve-service.sh" "$TARGET" "$ORG") && EXIT=$? || EXIT=$?
```

- **Exit 0:** parse `app_name|lifeos_subpath` from `$RESULT`. Report "Mapped: $APP_NAME → $LIFEOS_SUBPATH" and skip to Phase 4a.
- **Exit 1:** the repo is not mapped yet. Continue to Phase 4.
- **Exit 2 or 3:** report the error and stop.

### Phase 4 — Collect new mapping row values

Compute defaults:
- `DEFAULT_APP_NAME` = `basename "$MAIN_CHECKOUT"`, used verbatim in kebab-case (for example, `creative-studio` → `creative-studio`, `bust-backend` → `bust-backend`). If the folder name is not kebab-case, lowercase it and replace `_`, spaces, and camelCase boundaries with `-`.
- `DEFAULT_LIFEOS_SUBPATH` = `Services/$DEFAULT_APP_NAME`.

Ask with `AskUserQuestion` (batched, 2 questions in one call). The second question uses `$DEFAULT_APP_NAME`, not the answer to the first, because batched questions resolve at the same time:

1. `header: "app_name"`, `question: "App name for this repo?"`, options: `[$DEFAULT_APP_NAME]`, `[Other...]`
2. `header: "lifeos path"`, `question: "LifeOS subpath under $ORG/?"`, options: `[Services/$DEFAULT_APP_NAME]`, `[Other...]`

For an "Other..." answer, follow up with a free-form `AskUserQuestion`. If the user picked a non-default `app_name` in question 1 but accepted the default in question 2 (`Services/$DEFAULT_APP_NAME`), ask once more: "Use `Services/<app_name>` instead?" Adjust the answer to match.

Set `REPO_PATH_FOR_ROW` to `$MAIN_CHECKOUT`. If it starts with `$HOME`, write it in the `$HOME/...` form. A new row for the `## Service Mapping` table in `$INIT` looks like this:

```
| new-app | $HOME/Projects/Appier/appier/new-app | Services/new-app |
```

Single-space padding is enough. Obsidian tables tolerate it.

### Phase 4a — Confirm with user

This phase runs for every target, mapped or new, before any write. Find the exclude file:

```bash
EXCLUDE_FILE="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path info/exclude)"
```

`AskUserQuestion`:
- `question`: "Write these for $REPO_ROOT?" followed by one line per write, each with its full path:
  - New repo only: "Append this row to $INIT: | $APP_NAME | $REPO_PATH_FOR_ROW | $LIFEOS_SUBPATH |"
  - "Folder: $vault/01Project/$ORG/$LIFEOS_SUBPATH/handover/"
  - "Link $REPO_ROOT/handover -> $vault/01Project/$ORG/$LIFEOS_SUBPATH/handover"
  - "Exclude file: $EXCLUDE_FILE"

  If the folder is missing, Phase 5 creates it. If no rule ignores `handover` yet, Phase 7 writes `/handover` to the exclude file.
- `options`:
  - "Yes, write it"
  - "No, skip this repo"

If the user picks "No, skip this repo", write nothing for this target, and do not run Phases 5 to 8 for it. Its Phase 9 entry says `skipped by user`.

### Phase 5 — Write the row and create the LifeOS handover folder

If the user said yes:

For a new repo, use `Edit` to append the new row from Phase 4 to `$INIT`. If the table is empty, append it after the separator row. Otherwise, append it after the last existing data row. Keep all other content. A mapped repo already has its row, so skip the append.

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

### Phase 8 — Service contract

Run this phase for a mapped repo, also one that was mapped before this run. It runs after Phase 7, so it sees the row that Phase 5 wrote. Set `vault` and `REPO_ROOT` again in this Bash call.

```bash
contract_file=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/contract-path.sh" --vault "$vault" "$REPO_ROOT") && path_exit=0 || path_exit=$?
echo "path_exit=$path_exit contract_file=$contract_file"
[ -f "$contract_file" ] && echo file=yes || echo file=no
```

- **Exit 1:** set the `Contract:` line to `not mapped`. Go to Phase 9.
- **Exit 2:** set the `Contract:` line to the stderr text. Go to Phase 9.
- **Exit 0 and the file exists:** run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/contract-check.sh" "$REPO_ROOT" "$contract_file"`. Exit 0 or 1 prints a `status:` line. Set the `Contract:` line to `present (<status>)`, with that value. Exit 2 or 3 is an error: set the line to its stderr text. Change nothing. Go to Phase 9.
- **Exit 0 and the file does not exist:** ask one `AskUserQuestion`: "Set up the service contract now?" with the options "Launch a contract task" and "Not now". On "Not now", set the `Contract:` line to `not set up` and go to Phase 9.

On "Launch a contract task", resolve the tasks folder as start-task does. Take the first value that is set and is not a literal `${user_config...}` text: the shell variable `WSTACK_TASKS_DIR`, then `EVAL_WSTACK_TASKS_DIR`, then `${user_config.tasks_dir}`, then `Workflow/Tasks`. Print the two shell variables in one call:

```sh
printf '%s\n' "TASKS_DIR WSTACK=${WSTACK_TASKS_DIR:-} EVAL=${EVAL_WSTACK_TASKS_DIR:-}"
```

Then read "Launch mode" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/SKILL.md` (a user-invoked skill, so read the file and follow it). Set `$tasks_dir` to the tasks folder and `$scripts` to `${CLAUDE_PLUGIN_ROOT}/scripts`. Run its steps with the idea `set up the contract`, the work type `contract`, and the repository `$REPO_ROOT`. Run the `gh repo view` command from `$REPO_ROOT`.

Never run work mode in this session. Set the `Contract:` line from the result of Launch mode:

| Result | `Contract:` line |
|---|---|
| `launch-task.sh` exit 0 | `task <task_id> launched` |
| `launch-task.sh` exit 3 (not inside herdr) | `task <task_id> created, not launched (not inside herdr)`. Print `cd "$REPO_ROOT" && claude "/wstack:start-task --task <task_id>"`. |
| `launch-task.sh` exit 5 | The first stderr line. Print the cleanup hint from stderr. |
| `launch-task.sh` exit 1, 4, or 6, or a failed preflight | The first stderr line (or output line for the preflight). |

In every case go to Phase 9.

### Phase 9 — Report

Print one block for each target, in the order given. For a target that stopped early, print its path and the reason instead of the block. Then print the dropped targets:

```
✓ Service initialized:
    ORG:            $ORG
    APP_NAME:       $APP_NAME
    LIFEOS path:    $vault/01Project/$ORG/$LIFEOS_SUBPATH/handover/
    Symlink:        $REPO_ROOT/handover -> (above)
    Local exclude:  /handover (added | already present)
    Contract:       present (<status>) | task <task_id> launched | not set up | <error>

✗ $REPO_ROOT: skipped by user | <the error that stopped it>

Skipped:
    <path>: not a git work tree

Next: /wstack:create-handover <topic>
```

If no target was dropped, leave out the `Skipped:` part.

## Check mode

`--check` reads the service mapping table of one org and reports each row. It writes nothing.

1. Resolve the ORG as in Phase 1, with `TARGET="$PWD"`. If `$ORG` is empty, ask with `AskUserQuestion`, and list the folders under `$vault/01Project/` that have a `handover_handler__initiation.md`.
2. Run the check:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/check-mapping.sh" "$vault" "$ORG" && rc=0 || rc=$?
   echo "rc=$rc"
   ```

   The output is one header line and one tab-separated line per row. Exit 0 means every row is `ok`. Exit 1 means at least one row is `fix` or `broken`. For exit 2, report the stderr text and stop.
3. Show the rows as a table with the columns status, app_name, repo_path, link, ignore, vault, contract, and notes. Then explain each row that is not `ok`:
   - `fix`: the repo exists, but the link, the ignore rule, or the vault folder is missing or wrong. The init flow fixes it.
   - `broken`: the repo path does not exist, it is not a git work tree, or the row has no `lifeos_subpath`. Tell the user to fix or remove the row by hand, because this command never rewrites rows. The contract check needs the repo, so a `broken` row shows only whether the contract file is `present` or `missing`.
   - The note `app_name is not kebab-case`: the contract file name uses `app_name` as written, but `/wstack:create-handover` converts it to kebab-case. Suggest a rename of the row by hand.
   - A `contract` value of `missing` or `stale` does not make a row fail. Name the repos with no contract, and say that the init flow offers a contract task.
4. If one or more rows are `fix`, ask one `AskUserQuestion`: "Run the init flow for the <N> repos that need it?", with the options "Yes, all <N>" and "Not now". The user can name a subset in the free-text answer.
5. On yes, use the `repo_path` values of the chosen rows as the targets, and run the flow from "Arguments" on. The rows come from this org's table. So in Phase 1, use the `$ORG` of this check for every target, and do not run `resolve-org.sh`. Each repo still gets its own Phase 4a question.

## Non-negotiable rules

- Check mode writes nothing. Only the init flow writes, after the Phase 4a question.

- Never destroy a non-empty `./handover/` folder. If there is a conflict, stop and ask the user.
- Service mapping rows are append-only via this command. Never rewrite existing rows.
- The command never edits `.gitignore`. It writes `/handover` to the local exclude file, which git never commits.
- BustDice currently uses `Devops/` instead of `Services/`. If the user picks a `lifeos_subpath` that does not start with `Services/`, warn and allow it.
