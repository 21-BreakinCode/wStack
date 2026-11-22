---
name: board
description: Show every open RD, the ones that wait for the user first, write a snapshot page, and close finished workspaces.
disable-model-invocation: true
---

# board

## Config

Resolve each value in this order. Take the first one that is set and is not a literal `${user_config...}` text.

- Vault path: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`.
- Tasks folder: `WSTACK_TASKS_DIR`, then `EVAL_WSTACK_TASKS_DIR`, then `${user_config.tasks_dir}`, then `Workflow/Tasks`.

Read the shell variables with `echo "${WSTACK_VAULT_PATH:-}" "${EVAL_WSTACK_VAULT_PATH:-}"`. Read the other shell variables the same way. If no vault path is set, ask the user for it and stop.

If the vault path is relative, make it absolute with `cd <value> && pwd`.

In this file `$vault` is the vault path, `$tasks_dir` is the tasks folder, and `$scripts` is `${CLAUDE_PLUGIN_ROOT}/scripts`.

## Steps

1. Set `$rows` to the output of `bash "$scripts/board.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. If it fails, print its stderr and stop. If `$rows` is empty, tell the user that no RD is open and stop.
2. Print one table for each group, in this order: `needs you`, `stopped`, `working`, `paused`, `finished`, `other`. Skip a group with no row. The columns are task, stage (`status`), herdr, last step, age, and goal. A `stopped` row shows the resume command `/wstack:start-task` (resume mode) in its herdr column. A `working` row with herdr `unknown` says `unknown`.
3. Under each table that has rows with a workspace id other than `n/a`, print `herdr workspace focus <id>` for each of those rows.
4. Write the same tables as a draft, with the Write tool, to a file from `mktemp "${TMPDIR:-/tmp}/board.XXXXXX"`. Set `$board_dir` to `$vault/$(dirname "$tasks_dir")/Board`. Run `mkdir -p "$board_dir"`. Run `bash "$scripts/render-page.sh" "<draft>" "$board_dir/board.html" --theme-file "${CLAUDE_PLUGIN_ROOT}/themes/notion.json"`. Print the page path. If the render fails, print its stderr and go on. Exit code 1 means the page is too wide. It still exists, so print its path.
5. If `finished` rows exist, ask once which to close: task names, `all`, or `none`. End the reply and wait. Any answer that is not a list of names or `all` means `none`.
6. For each task to close, read `workspace_cwd` from its `spec.md` and take the workspace id from its row.
   - If `git -C <workspace_cwd> rev-parse --git-dir` differs from `git -C <workspace_cwd> rev-parse --git-common-dir`, the workspace has a worktree. Run `git -C <workspace_cwd> status --porcelain`. If it prints anything, skip the task and say that the worktree has changes. Otherwise run `herdr worktree remove --workspace <id>`.
   - If both commands print the same path, or `workspace_cwd` is not a git directory, run `herdr workspace close <id>`.
   - If the variable `WSTACK_HERDR_SESSION` is set, write `--session $WSTACK_HERDR_SESSION` right after `herdr`.
7. Report what was closed and what was skipped, each with its reason.
