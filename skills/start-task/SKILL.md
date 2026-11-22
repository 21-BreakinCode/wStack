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
- Retry limit: `WSTACK_RETRY_LIMIT`, then `EVAL_WSTACK_RETRY_LIMIT`, then `${user_config.retry_limit}`, then `3`.
- R2 bucket: `WSTACK_R2_BUCKET`, then `EVAL_WSTACK_R2_BUCKET`, then `${user_config.r2_bucket}`, then empty.
- Evidence domain: `WSTACK_EVIDENCE_DOMAIN`, then `EVAL_WSTACK_EVIDENCE_DOMAIN`, then `${user_config.evidence_domain}`, then empty.
- Local-only evidence repos: `WSTACK_LOCAL_EVIDENCE_ONLY_REPOS`, then `EVAL_WSTACK_LOCAL_EVIDENCE_ONLY_REPOS`, then `${user_config.local_evidence_only_repos}`, then empty. The value is a comma list of `owner/repo`.
- Pull request media limit in MB: `WSTACK_PR_MEDIA_MAX_MB`, then `EVAL_WSTACK_PR_MEDIA_MAX_MB`, then `${user_config.pr_media_max_mb}`, then `10`.

Print every config shell variable in one call:

```sh
printf '%s\n' \
  "VAULT_PATH WSTACK=${WSTACK_VAULT_PATH:-} EVAL=${EVAL_WSTACK_VAULT_PATH:-}" \
  "TASKS_DIR WSTACK=${WSTACK_TASKS_DIR:-} EVAL=${EVAL_WSTACK_TASKS_DIR:-}" \
  "RETRY_LIMIT WSTACK=${WSTACK_RETRY_LIMIT:-} EVAL=${EVAL_WSTACK_RETRY_LIMIT:-}" \
  "R2_BUCKET WSTACK=${WSTACK_R2_BUCKET:-} EVAL=${EVAL_WSTACK_R2_BUCKET:-}" \
  "EVIDENCE_DOMAIN WSTACK=${WSTACK_EVIDENCE_DOMAIN:-} EVAL=${EVAL_WSTACK_EVIDENCE_DOMAIN:-}" \
  "LOCAL_EVIDENCE_ONLY_REPOS WSTACK=${WSTACK_LOCAL_EVIDENCE_ONLY_REPOS:-} EVAL=${EVAL_WSTACK_LOCAL_EVIDENCE_ONLY_REPOS:-}" \
  "PR_MEDIA_MAX_MB WSTACK=${WSTACK_PR_MEDIA_MAX_MB:-} EVAL=${EVAL_WSTACK_PR_MEDIA_MAX_MB:-}"
```

Use the printed values in the order above. If no vault path is set, ask the user for it and stop.

If a value is a relative path, make it absolute with `cd <value> && pwd`.

In this file `$vault` is the vault path, `$tasks_dir` is the tasks folder, and `$scripts` is `${CLAUDE_PLUGIN_ROOT}/scripts`.

## Launch mode

The argument is a rough idea. Run these steps in order.

1. Run `bash "$scripts/preflight.sh" base`. If it exits 1, print its output and stop. The output holds the install commands.
2. Pick the work type: `code`, `ops`, `thinking`, `blog`, `video`, or `contract`. If the idea asks to set up, create, or rebuild a service contract, pick `contract`.
3. Pick the slug. Write 2 to 4 English words from the idea, lowercase, joined by hyphens. It starts with a letter, holds only `a-z`, `0-9`, and `-`, and has 32 characters at most. For an idea in another language, use English words for its meaning.
4. After step 3, pick the repository for a `code` or `contract` task. Use the git repository of the current directory, or a repository that the idea names. Take the path from `git rev-parse --show-toplevel` and `owner/repo` from `gh repo view --json nameWithOwner -q .nameWithOwner`. If the task is `code` or `contract` and no repository exists, ask the user one question and stop until they answer.
5. Set mobile when the arguments contain `--mobile` or the word "mobile". Remove `--mobile` from the idea text.
6. Run `bash "$scripts/new-task-folder.sh" --vault "$vault" --tasks-dir "$tasks_dir" --slug <slug> --work-type <type> [--repo owner/repo] [--mobile] --idea '<idea text>'`. The idea text is the arguments without `--mobile`. Put it in single quotes, and write each `'` in it as `'\''`. If a task folder or a herdr agent already has the slug, the script adds `-2`, `-3`, and so on. The last output line is `$task_dir`. The task id is the folder name.
7. Run `bash "$scripts/launch-task.sh" --task-dir "$task_dir" [--repo-path <path>] [--mobile]`. Add `--repo-path` only for a `code` or `contract` task with a repository. Act on the exit code:

| Exit | Meaning | Action |
|---|---|---|
| 0 | launched | Print the task id, the workspace label, and the Remote Control name (both are the slug). Stop. The new session runs the work mode. |
| 3 | not inside herdr | For a `code` task, read `workspace_cwd` from `$task_dir/spec.md`. It is a new worktree. Tell the user to run `cd "<workspace_cwd>" && claude "/wstack:start-task --task <task_id>"`. Stop, and do not run work mode in this session. For any other work type, run work mode in this session for `$task_dir`. `/wstack:init-service` hands a `contract` task off in the same way: it reads this Launch mode by file and handles exit 3 itself, so it never runs work mode. |
| 4 | agent name taken (a race) | Tell the user that the name is taken. Stop. |
| 5 | the agent did not start after the workspace was made | Print the workspace id and the cleanup commands from the script's stderr. Offer to resume with `bash "$scripts/resume-task.sh" --task-dir "$task_dir"`. Stop. |
| 6 | herdr or git could not create the workspace or worktree | Print the error from stderr. Stop. |
| 1 | bad input | Print stderr. Stop. |

`new-task-folder.sh` writes the idea text under `## Goal` in `spec.md`. After exit 0 and after exit 3, work mode reads the idea there.

## Work mode

The argument is `--task <task_id>`. The task folder is `$vault/$tasks_dir/<task_id>`.

1. Record this session on the task: `bash "$scripts/session-id-add.sh" "$task_dir/spec.md" "${CLAUDE_SESSION_ID}"`. If it exits 3, write the `step` line `session id not available` in `run-log.md`. If it exits with any other non-zero code, write the `step` line `session id not recorded: <first stderr line>`. Go on in every case.
2. Read the status from the frontmatter only: `(source "$scripts/lib/frontmatter.sh" && fm_get "$task_dir/spec.md" status)`.
3. Continue from that stage:

| Status | Stage |
|---|---|
| `drafting`, `awaiting-approval` | Confirmation. Read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` and follow it. |
| `executing` | Execute. Read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/execute.md` and follow it. |
| `paused` | Read `${CLAUDE_PLUGIN_ROOT}/skills/resume-work/SKILL.md` and follow Steps 1-3 with the note `$task_dir/pause.md`. Then continue with the restored status. |
| `waiting-user` | Read the last item of `stopped_for_user` in `run-log.md`. Go on as "Stop items" says for its `stage`. |
| `verifying` | Verify. Read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/verify.md` and follow it. |
| `awaiting-deliver-approval` | Deliver. Run the `deliver-task` skill and follow its "After the user answers" section. |
| `delivered`, `cancelled` | Tell the user the task is closed. Stop. |

Change `status` only with `bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" status <value>`.

## Stop items

Each time a stage sets `status` to `waiting-user`, it first appends one stop item to `stopped_for_user` in `run-log.md`:

`bash "$scripts/frontmatter-set.sh" --append "$task_dir/run-log.md" stopped_for_user '{"at":"<ISO time>","stage":"<stage>","reason":"<reason>"}'`

`<ISO time>` comes from `date -u +%Y-%m-%dT%H:%M:%SZ`. The stage is `confirmation`, `execute`, `verify`, or `deliver`. A Deliver item also has `"target":"<target>"`, the Target name from the table in the `deliver-task` skill. No other item has `target`.

When the user answers a stop, in the same session or in a resumed task, tell the user the reason of the last item. Then go on by its `stage`:

| Stage | Go on with |
|---|---|
| `confirmation` | "After a stop" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` |
| `execute` | "After the user answers a stop" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/execute.md` |
| `verify` | "After the user answers a stop" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/verify.md` |
| `deliver` | The `deliver-task` skill. Follow its "After the user answers" section. |

If `stopped_for_user` is empty, ask the user which stage to resume.

## Resume mode

No arguments.

1. Run `bash "$scripts/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. Each line is `task_id`, `status`, `workspace_cwd`, and `folder`, split by tabs.
2. If there are no lines, tell the user there is no open task. Stop.
3. Ask the user which task to resume. Show the task id and the status of each.
4. Read `echo "${HERDR_ENV:-}"`. If it is not `1`, skip the steps below. For a `code` task, tell the user to run `cd "<workspace_cwd>" && claude "/wstack:start-task --task <task_id>"`, and stop. For any other work type, run work mode for the chosen task in this session.
5. Run `bash "$scripts/resume-task.sh" --task-dir "<folder>"`. It prints `focused` or `restarted`. Tell the user which one. For a `paused` task, also tell the user to run `/wstack:start-task --task <task_id>` in that session. `restarted` runs `claude --continue` with no prompt, and `focused` only focuses the pane, so neither one runs the resume.
6. If it exits 1, tell the user that the working directory of the task is gone, and print the stderr.
7. If it exits 5 or 6, print the stderr. Stop.
