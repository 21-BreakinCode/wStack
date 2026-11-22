---
name: resume-work
description: Resume paused work from its resume note. Compare the git state, show the note, and go on from the next step.
disable-model-invocation: true
---

# resume-work

Usage: `/wstack:resume-work [<note path>]`. It works in any Claude Code session. `/wstack:pause-work` writes the notes.

## Config

Read the vault path and the tasks folder as the `pause-work` skill does in its "Config" section. If no vault path is set, skip the task lookup. Each Bash call is a new shell. Start each Bash call with `vault=<abs path>; tasks_dir=<value>; scripts="${CLAUDE_PLUGIN_ROOT}/scripts"`.

## Find the note

1. With a note path, use it. A note named `pause.md` that has a `spec.md` in its folder is a task note. Any other note is a session note.
2. Without an argument, run `bash "$scripts/list-open-tasks.sh" --vault "$vault" --tasks-dir "$tasks_dir"`. If exactly one `workspace_cwd` is the current directory (`pwd`) and its folder has a `pause.md`, use that note as a task note.
3. Otherwise run `bash "$scripts/list-pause-notes.sh" "$(pwd)"`. It prints the session notes of the current folder, newest first. Use the first one. If it printed more than one line, tell the user which note you use and list the others.
4. If you found no note, tell the user there is nothing to resume and stop.

## Step 1: compare the git state

Read the `git state` field of the note. For the repository and each worktree it lists, run `git -C "<path>" rev-parse --abbrev-ref HEAD`, `git -C "<path>" rev-parse HEAD`, and `git -C "<path>" status --porcelain`. Report every difference in branch, HEAD, uncommitted paths, and worktrees. Do not discard, reset, or stash anything.

## Step 2: show the note

Show the user the goal, done, in progress, and next steps of the note. Read each file under `read first on resume`.

## Step 3: mark the note as used

- Task note: restore the status, then rename the note so the history stays and the next pause starts clean.

  ```sh
  old_status="$(source "$scripts/lib/frontmatter.sh" && fm_get "$task_dir/spec.md" paused_from)"
  bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" status "$old_status"
  mv "$task_dir/pause.md" "$task_dir/pause-<time>.md"
  ```

  `<time>` is the `time` field of the note with `:` replaced by `-`. If `paused_from` is empty, ask the user for the status.
- Session note: rename it to `<name>.resumed-<time>.md` with `mv`, so the next resume does not pick it again. `<time>` comes from `date +%Y%m%d-%H%M%S`.

## Step 4: continue

Go on from the first of the next steps. For a task note, continue from the restored status with the stage table in "Work mode" of the `start-task` skill.
