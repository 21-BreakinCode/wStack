---
name: resume-work
description: Resume paused work from its resume note. Compare the git state, show the note, and go on from the next step.
disable-model-invocation: true
---

# resume-work

Usage: `/wstack:resume-work [<note path>]`. It works in any Claude Code session. `/wstack:pause-work` writes the notes.

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

If a value is a relative path, make it absolute with `cd <value> && pwd`. If no vault path is set, skip the task lookup. Each Bash call is a new shell. Start each Bash call with `vault=<abs path>; tasks_dir=<value>; scripts="${CLAUDE_PLUGIN_ROOT}/scripts"`.

## Find the note

1. With a note path, use it. A note named `pause.md` that has a `spec.md` in its folder is a task note. Any other note is a session note.
2. Without an argument, look for both kinds. Run `bash "$scripts/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. For a task note, check that exactly one `workspace_cwd` is the current directory (`pwd`) and that its folder has a `pause.md`. Run `bash "$scripts/list-pause-notes.sh" "$(pwd)"`. It prints the session notes of the current folder, newest first.
3. If only one kind exists, use it. For session notes, use the first line. If it printed more than one line, tell the user which note you use and list the others.
4. If both kinds exist, list them and ask the user which one to resume.
5. If you found no note, tell the user there is nothing to resume and stop.

## Step 1: compare the git state

Read the `git state` field of the note. For the repository and each worktree it lists, run `git -C "<path>" rev-parse --abbrev-ref HEAD`, `git -C "<path>" rev-parse HEAD`, and `git -C "<path>" status --porcelain`. Report every difference in branch, HEAD, uncommitted paths, and worktrees. Do not discard, reset, or stash anything.

If a path in the note does not exist, for example a moved folder or another Mac, say so. Keep the note. Ask the user before you go on.

## Step 2: show the note

Show the user the goal, done, in progress, and next steps of the note. Read each file under `read first on resume`. If a listed file does not exist, say so, keep the note, and ask the user before you go on.

## Step 3: mark the note as used

- Task note: read the status with `(source "$scripts/lib/frontmatter.sh" && fm_get "$task_dir/spec.md" status)`. If the status is `paused`, restore the old status. If the status is any other value, leave it alone. Then clear `paused_from` and rename the note, so the history stays and the next pause starts clean.

  ```sh
  old_status="$(source "$scripts/lib/frontmatter.sh" && fm_get "$task_dir/spec.md" paused_from)"
  bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" status "$old_status"
  bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" paused_from ""
  mv "$task_dir/pause.md" "$task_dir/pause-<time>.md"
  ```

  `<time>` is the `time` field of the note with `:` replaced by `-`. If the status is not `paused`, tell the user, change nothing, and still rename the note. If `paused_from` is empty, ask the user for the status.
- Session note: rename it to `<name>.resumed-<time>.md` with `mv`, so the next resume does not pick it again. `<time>` comes from `date +%Y%m%d-%H%M%S`.

## Step 4: continue

Go on from the first of the next steps. For a task note, read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/SKILL.md` and follow "Work mode" with the restored status.
