---
name: start-task
description: Start, continue, or resume a wStack task. Confirm the spec, execute, verify, deliver.
disable-model-invocation: true
---

# start-task

Pick the mode from the arguments.

| Arguments | Mode |
|---|---|
| `--task <task_id>` | work |
| any other text | launch |
| none | resume |

## Config

Resolve each value in this order. Take the first one that is set and is not a literal `${user_config...}` text.

- Vault path: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`.
- Tasks folder: `WSTACK_TASKS_DIR`, then `EVAL_WSTACK_TASKS_DIR`, then `${user_config.tasks_dir}`, then `Workflow/Tasks`.

Read the shell variables with `echo "${WSTACK_VAULT_PATH:-}" "${EVAL_WSTACK_VAULT_PATH:-}"`. If no vault path is set, ask the user for it and stop.

If a value is a relative path, make it absolute with `cd <value> && pwd`.

In this file `$vault` is the vault path, `$tasks_dir` is the tasks folder, and `$scripts` is `${CLAUDE_PLUGIN_ROOT}/scripts`.

## Launch mode

The argument is a rough idea. Run these steps in order.

1. Run `bash "$scripts/preflight.sh" base`. If it exits 1, print its output and stop. The output holds the install commands.
2. Pick the work type: `code`, `ops`, `thinking`, `blog`, or `video`.
3. Pick the slug. Write 2 to 4 English words from the idea, lowercase, joined by hyphens. It starts with a letter, holds only `a-z`, `0-9`, and `-`, and has 32 characters at most. For an idea in another language, use English words for its meaning.
4. Run `bash "$scripts/free-agent-slug.sh" <slug>`. Use the slug it prints. It adds `-2`, `-3`, and so on when a herdr agent has the name.
5. After steps 3 and 4, pick the repository when the type is `code`. Use the git repository of the current directory, or a repository that the idea names. Take the path from `git rev-parse --show-toplevel` and `owner/repo` from `gh repo view --json nameWithOwner -q .nameWithOwner`. If the task is code and no repository exists, ask the user one question and stop until they answer.
6. Set mobile when the arguments contain `--mobile` or the word "mobile". Remove `--mobile` from the idea text.
7. Run `bash "$scripts/new-task-folder.sh" --vault "$vault" --tasks-dir "$tasks_dir" --slug <slug> --work-type <type> [--repo owner/repo] [--mobile]`. The last output line is `$task_dir`. The task id is the folder name.
8. Run `bash "$scripts/launch-task.sh" --task-dir "$task_dir" [--repo-path <path>] [--mobile]`. Add `--repo-path` only for a code task with a repository. Act on the exit code:

| Exit | Meaning | Action |
|---|---|---|
| 0 | launched | Print the task id, the workspace label, and the Remote Control name (both are the slug). Stop. The new session runs the work mode. |
| 3 | not inside herdr | Run work mode in this session for `$task_dir`. |
| 4 | agent name taken (a race) | Tell the user that the name is taken. Stop. |
| 5 | the agent did not start after the workspace was made | Print the workspace id and the cleanup commands from the script's stderr. Offer to resume with `bash "$scripts/resume-task.sh" --task-dir "$task_dir"`. Stop. |
| 6 | herdr could not create the workspace or worktree | Print the herdr error from stderr. Stop. |
| 1 | bad input | Print stderr. Stop. |

The idea text is the starting point of the spec. In the exit 3 case, keep the idea in mind when work mode starts Confirmation.

## Work mode

The argument is `--task <task_id>`. The task folder is `$vault/$tasks_dir/<task_id>`.

1. Read the status: `sed -n 's/^status: //p' "$task_dir/spec.md"`.
2. Continue from that stage:

| Status | Stage |
|---|---|
| `drafting`, `awaiting-approval` | Confirmation. Read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` and follow it. |
| `executing`, `waiting-user` | Execute. Read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/execute.md` and follow it. |
| `verifying`, `awaiting-deliver-approval` | The Verify and Deliver stages are written in later reference files in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/`. If the file for the stage is not there, tell the user the stage is not available yet and stop. |
| `delivered`, `cancelled` | Tell the user the task is closed. Stop. |

Change `status` only with `bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" status <value>`.

## Resume mode

No arguments.

1. Run `bash "$scripts/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. Each line is `task_id`, `status`, `workspace_cwd`, and `folder`, split by tabs.
2. If there are no lines, tell the user there is no open task. Stop.
3. Ask the user which task to resume. Show the task id and the status of each.
4. Run `bash "$scripts/resume-task.sh" --task-dir "<folder>"`. It prints `focused` or `restarted`. Tell the user which one.
5. If it exits 1, tell the user that the working directory of the task is gone, and print the stderr.
6. If it exits 5 or 6, print the stderr. Stop.
