# Execute

Goal: do the work in the spec without the user. Done when you believe the spec is met and `run-log.md` lists every step.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `frontmatter-set.sh`. Read the spec first. Its answers settle your questions, so do not ask the user about anything the spec already answers.

## Start

1. Set `status` to `executing` if it is `waiting-user`.
2. If `started_at` in `run-log.md` is empty, set it once to `date -u +%Y-%m-%dT%H:%M:%SZ`: `bash "$scripts/frontmatter-set.sh" "$task_dir/run-log.md" started_at <time>`. Never set it again.
3. For a code task, work in `workspace_cwd`. Run `git switch -c wstack/<slug>`, or `git switch wstack/<slug>` if the branch exists. `<slug>` is the task id without its date prefix. Commit only on that branch. Never commit to the default branch.

## Log

Write one line to `run-log.md` under `## Steps` for each step, each retry, and each stop:

`- <ISO time> <step|retry|stop> <text>`

Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the time. Append the line after the step succeeds.

## Work

Iterate on your own. Test your work as you go.

## Stop before a non-undoable step

A non-undoable step is one the spec lists under `## Non-undoable steps`. A merge, a push to the default branch, a force push, a delete, and a deploy are always non-undoable.

Exception: the spec lists `open a pull request` under `## Deliver targets`. That approval covers pushing `wstack/<slug>` and creating that one pull request. Do those two without a stop. Leave them to the Deliver stage if it is available.

Before any other non-undoable step, stop:

1. Write a `stop` line in `run-log.md` with the reason.
2. Run `bash "$scripts/frontmatter-set.sh" --append "$task_dir/run-log.md" stopped_for_user '{"at":"<ISO time>","reason":"<reason>"}'`.
3. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user the step and the reason. Ask for a yes or no. End the reply. Wait.

If the guard hook asks or denies a command, treat it as a non-undoable step and stop the same way.

Add the prefix `WSTACK_APPROVED=1` to a command only after the user says yes in this session. Never add it before. When the user says yes, set `status` to `executing`, log a `step` line, and run the command with the prefix.

Stop also when the spec is wrong or unclear. Set `status` to `waiting-user` and ask the user.

## Retry

When a try fails, write a `retry` line, add 1 to `retries` in `run-log.md`, and try again. Read `retry_limit` from the plugin config. If it is not set, use 3. After `retry_limit` failed tries, stop as above.

## Thinking and ops work

Write the result as a new note in `$vault`. Never overwrite an existing note. If the name is taken, add `-2`, `-3`, and so on. Undo means: delete that note.

## Learning tasks

- Input: find and prepare material for the user to read, watch, or study.
- Output: help the user make notes, a blog post, or a talk. Test what the user learned with quizzes, flashcards, or an "explain it back" exercise.

## Finish

When the spec is met, write a `step` line that says so. Set `status` to `verifying`. The Verify stage is written in a later reference file in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/`. If it is not there, tell the user the stage is not available yet and stop.
