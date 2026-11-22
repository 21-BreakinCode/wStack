---
name: pause-task
description: Stop a wStack task in the middle, stop its background work, and save where it stopped.
disable-model-invocation: true
---

# pause-task

Usage: `/wstack:pause-task [--task <task_id>]`.

## Config

Resolve each value in this order. Take the first one that is set and is not a literal `${user_config...}` text.

- Vault path: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`.
- Tasks folder: `WSTACK_TASKS_DIR`, then `EVAL_WSTACK_TASKS_DIR`, then `${user_config.tasks_dir}`, then `Workflow/Tasks`.

Print the shell variables in one call:

```sh
printf '%s\n' \
  "VAULT_PATH WSTACK=${WSTACK_VAULT_PATH:-} EVAL=${EVAL_WSTACK_VAULT_PATH:-}" \
  "TASKS_DIR WSTACK=${WSTACK_TASKS_DIR:-} EVAL=${EVAL_WSTACK_TASKS_DIR:-}"
```

If no vault path is set, ask the user for it and stop. If a value is a relative path, make it absolute with `cd <value> && pwd`. Each Bash call is a new shell. Start each Bash call with `vault=<abs path>; tasks_dir=<value>; scripts="${CLAUDE_PLUGIN_ROOT}/scripts"`.

## Find the task

1. With `--task <task_id>`, the task folder is `$vault/$tasks_dir/<task_id>`. If it has no `spec.md`, tell the user and stop.
2. Without `--task`, run `bash "$scripts/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. Each line is `task_id`, `status`, `workspace_cwd`, and `folder`, split by tabs. Take the line whose `workspace_cwd` is the current directory (`pwd`). If no line or more than one line matches, ask the user for the task id and stop.
3. Read the status: `(source "$scripts/lib/frontmatter.sh" && fm_get "$task_dir/spec.md" status)`.
4. If status is `paused`, tell the user the task is already paused and stop. The note in `pause.md` stays as it is.
5. If status is `delivered` or `cancelled`, tell the user the task is closed and stop.

## Step 1: stop background work

1. Stop every background agent and background shell that this session started. Call the TaskStop tool once for each one.
2. Look for a test run that started from the task workspace: `pgrep -fl "<workspace_cwd>"`. Ignore the `pgrep` process itself and this Claude Code session. Stop each other match with `kill <pid>`. Run `pgrep -fl "<workspace_cwd>"` again. If a match is left, name it to the user.

Write down what you stopped for Step 2.

## Step 2: save the state

Write `$task_dir/pause.md` with these fields:

```md
# Pause

- time: <ISO time from `date -u +%Y-%m-%dT%H:%M:%SZ`>
- status before the pause: <the status from the Find the task step>
- step in progress: <the step you were on, in one sentence>
- git HEAD: <`git -C "<workspace_cwd>" rev-parse HEAD`>
- uncommitted paths: <`git -C "<workspace_cwd>" status --porcelain`, one path per line, or none>
- stopped: <each background agent, shell, and process you stopped, or none>
- next step: <the first action the next session takes>
```

Leave the uncommitted work where it is. Do not commit, stash, or discard it.

## Step 3: set the status

```sh
old_status="<status before the pause>"
bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" paused_from "$old_status"
bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" status paused
```

Append this line to `$task_dir/run-log.md` under `## Steps`: `- <ISO time> pause <step in progress>`.

## Step 4: tell the user

Tell the user the task is paused and what you stopped. Give the resume command: `/wstack:start-task --task <task_id>`. Without an argument, `/wstack:start-task` lists the open task too.
