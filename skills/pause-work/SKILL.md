---
name: pause-work
description: Pause the work of this session. Write a resume note, then stop every background agent, shell, and process the session started.
disable-model-invocation: true
---

# pause-work

Usage: `/wstack:pause-work [--task <task_id>]`. It works in any Claude Code session. Compacting a conversation does not stop background agents or shells, so run this skill before you close the computer.

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

If a value is a relative path, make it absolute with `cd <value> && pwd`. If no vault path is set, this is a session pause: skip "Find the context" step 1 and go to step 3. Each Bash call is a new shell. Start each Bash call with `vault=<abs path>; tasks_dir=<value>; scripts="${CLAUDE_PLUGIN_ROOT}/scripts"`.

## Find the context

1. With `--task <task_id>`, this is a task pause. The task folder `$task_dir` is `$vault/$tasks_dir/<task_id>`. If it has no `spec.md`, tell the user and stop.
2. Without `--task`, run `bash "$scripts/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. Each line is `task_id`, `status`, `workspace_cwd`, and `folder`, split by tabs. If exactly one `workspace_cwd` is the current directory (`pwd`), this is a task pause for that line. If more than one matches, ask the user for the task id.
3. In any other case, this is a session pause.
4. For a task pause, read the status: `(source "$scripts/lib/frontmatter.sh" && fm_get "$task_dir/spec.md" status)`. If status is `paused`, tell the user the task is already paused and stop. The note in `pause.md` stays as it is. If status is `delivered` or `cancelled`, tell the user the task is closed and stop.

## Step 1: write the resume note first

Write the note before you stop anything, so a failed stop still leaves a note.

- Task pause: `$task_dir/pause.md`.
- Session pause: `~/.wstack/pauses/<current folder name>-<YYYYMMDD-HHMMSS>.md`. Create the folder with `mkdir -p ~/.wstack/pauses`. Take the time from `date +%Y%m%d-%H%M%S`.

The note holds these fields. Fill them from your own context and from git.

```md
# Pause

- time: <ISO time from `date -u +%Y-%m-%dT%H:%M:%SZ`>
- folder: <the current folder, absolute path>
- status before the pause: <task pause only: the status from step 4 above>
- goal: <the goal of the session in one or two lines>
- done: <what is finished>
- in progress: <the step you were on>
- next steps: <the next steps, in order>
- git state: <for the current repository and for every worktree the session used: path, branch, HEAD, uncommitted paths from `git -C "<path>" status --porcelain`, or none>
- read first on resume: <the plans, ledgers, and reports the session relied on, one path per line>
```

The line `- folder: <path>` must keep exactly that form. `resume-work` finds a session note by it. Leave the uncommitted work where it is. Do not commit, stash, or discard it.

## Step 2: stop background work

1. List every background agent and background shell this session started. Use your own context. If the ListAgents tool is available, use it to find the subagents. Stop each one with the TaskStop tool.
2. Look for processes the session started that outlive its tools: test runs, `playwright-cli` sessions, and dev servers. Run `pgrep -fl "<current folder>"` and the same for each worktree path the session used. Stop only a process you can trace to this session, with `kill <pid>`. Ignore the `pgrep` process and this Claude Code session. Run `pgrep` again for each path.
3. List every other process you saw and did not stop.

## Step 3: finish the note

Add two lines to the note:

- `- stopped: <each agent, shell, and process you stopped, or none>`
- `- still running: <each process you saw and did not stop, with its pid, or none>`

For a task pause only, set the status and add a log line:

```sh
bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" paused_from "<status before the pause>"
bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" status paused
```

Append `- <ISO time> pause <in progress>` to `$task_dir/run-log.md` under `## Steps`.

## Step 4: tell the user

Tell the user the note path, what you stopped, and anything still running. Give the resume command: `/wstack:resume-work`. For a task, `/wstack:start-task --task <task_id>` also works.
