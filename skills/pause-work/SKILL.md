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

If a value is a relative path, make it absolute with `cd <value> && pwd`. If no vault path is set and the user gave `--task`, ask the user for the vault path and stop. If no vault path is set and there is no `--task`, this is a session pause: go to "Step 1". Each Bash call is a new shell. Start each Bash call with `vault=<abs path>; tasks_dir=<value>; scripts="${CLAUDE_PLUGIN_ROOT}/scripts"`.

## Find the context

1. With `--task <task_id>`, this is a task pause. The task folder `$task_dir` is `$vault/$tasks_dir/<task_id>`. If it has no `spec.md`, tell the user and stop.
2. Without `--task`, run `bash "$scripts/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. Each line is `task_id`, `status`, `workspace_cwd`, and `folder`, split by tabs. Pick the lines whose `workspace_cwd` is the current directory (`pwd`). Of those, keep the tasks for which your context shows that you ran `/wstack:start-task --task <id>` (or its work mode) in this session. If you keep one task, this is a task pause for it, and `$task_dir` is its `folder`. If you keep more than one, ask the user which task to pause, or this session only. If you keep none but picked at least one line, ask the user once: "Pause task <id>, or this session only?" with each picked id, and follow the answer. A repository root can be the `workspace_cwd` of a task that this session never touched.
3. If no line has the current directory as its `workspace_cwd`, this is a session pause.
4. For a task pause, read the status: `(source "$scripts/lib/frontmatter.sh" && fm_get "$task_dir/spec.md" status)`. If status is `paused`, tell the user the task is already paused. If status is `delivered` or `cancelled`, tell the user the task is closed. In both cases do not write a note and do not change the status, but still run "Step 2" and report what you stopped.

## Step 1: write the resume note first

Write the note before you stop anything, so a failed stop still leaves a note.

- Task pause: `$task_dir/pause.md`.
- Session pause: `~/.wstack/pauses/<current folder name>-<YYYYMMDD-HHMMSS>.md`. Create the folder with `mkdir -p ~/.wstack/pauses`. Take the time from `date +%Y%m%d-%H%M%S`.

The note holds these fields. Fill them from your own context and from git.

```md
# Pause

- time: <ISO time from `date -u +%Y-%m-%dT%H:%M:%SZ`>
- folder: <the current folder, absolute path>
- status before the pause: <task pause only: the status from "Find the context" step 4>
- goal: <the goal of the session in one or two lines>
- done: <what is finished>
- in progress: <the step you were on>
- next steps: <the next steps, in order>
- git state: <for the current repository and for every worktree the session used: path, branch, HEAD, uncommitted paths from `git -C "<path>" status --porcelain`, or none>
- read first on resume: <the plans, ledgers, and reports the session relied on, one path per line>
```

The line `- folder: <path>` must keep exactly that form. `resume-work` finds a session note by it. Leave the uncommitted work where it is. Do not commit, stash, or discard it.

## Step 2: stop background work

1. List every background agent and background shell this session started. Use your own context. If the ListAgents tool is available, use it to find the subagents. Stop each one with the TaskStop tool. A compaction can remove the task ids from your context. Then tell the user to open `/tasks`. It lists everything running in the background. The user stops what they pick there.
2. Look for processes the session started that outlive its tools: test runs, `playwright-cli` sessions, and dev servers. A path match alone is not a trace, because other sessions run in the same repository. A process is traced to this session only in one of two cases.
   - (a) Its parent chain reaches the Claude process of this session.
   - (b) This session started it with a named Bash call. Its command line matches that call. Its working folder is the current folder or a worktree this session used. To read the working folder, run `lsof -a -p <pid> -d cwd -Fn`. The line that starts with `n` holds it.

   A process that an earlier Bash call started with `&` has parent 1 after that call ends, so rule (a) does not find it. Judge a process with parent 1 by rule (b). If your context no longer shows the Bash call that started it, do not stop it. List it and ask the user.

   Run this in one Bash call. It lists the candidates with the answer for rule (a). Replace `<path>` with the current folder, then with each worktree path.

   ```sh
   session_pid="$(ps -o ppid= -p $$ | tr -d ' ')"
   reaches_session() {  # <pid>
     walk="$1"
     while [ -n "$walk" ] && [ "$walk" -gt 1 ]; do
       [ "$walk" = "$session_pid" ] && return 0
       walk="$(ps -o ppid= -p "$walk" | tr -d ' ')"
     done
     return 1
   }
   ps -axo pid=,command= | grep -F -- "<path>" | grep -v "grep -F" | while read -r pid command; do
     [ "$pid" = "$session_pid" ] && continue
     if reaches_session "$pid"; then echo "traced $pid $command"; else echo "other $pid $command"; fi
   done
   ```

   Stop each `traced` process with `kill <pid>`. Never stop a direct child of `$session_pid` that is not a shell. It is an MCP or LSP server. If an `other` process meets rule (b), stop it. Leave every other process alone. Run the command again to check.
3. Stop the browser sessions of `playwright-cli`. Its browser daemon runs detached as `node …/cliDaemon.js <session>`, with no folder path, so the search above does not find it. Run `ps -axo pid=,command= | grep -F 'cliDaemon.js '`. The word after `cliDaemon.js` is the session name. Stop a session that this session opened. When `ps -p <pid>` prints nothing for a session named `wstack-width-<pid>` or `wstack-excalidraw-<pid>`, the script that opened it is gone. Stop that session too. Stop a session with `cd "$(mktemp -d)" && playwright-cli -s <session> close`, not with `kill`. Leave every other session alone.
4. List every process and session you saw and did not stop.

## Step 3: finish the note

If "Find the context" step 4 refused the task, skip this step. If not, do these:

1. Read the git state again with `git -C "<path>" status --porcelain` and `rev-parse HEAD` for each path, and replace the `git state` line, because stopped work can change the files.
2. Add two lines to the note: `- stopped: <each agent, shell, and process you stopped, or none>` and `- still running: <each process you saw and did not stop, with its pid, or none>`.
3. For a task pause only, set the status and add a log line:

```sh
bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" paused_from "<status before the pause>"
bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" status paused
```

Append `- <ISO time> pause <in progress>` to `$task_dir/run-log.md` under `## Steps`.

## Step 4: tell the user

Tell the user the note path, what you stopped, and anything still running. Give the resume command. For a session pause, it is `cd "<folder>" && claude "/wstack:resume-work <note path>"`, with the `folder` field of the note. For a task pause, it is `cd "<workspace_cwd>" && claude "/wstack:start-task --task <task_id>"`. `/wstack:resume-work` prints the same command for a task note. After a refusal, tell the user the reason and what you stopped.
