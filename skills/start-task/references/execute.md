# Execute

Goal: do the work in the spec without the user. Done when you believe the spec is met and `run-log.md` lists every step.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `frontmatter-set.sh`. Read the spec first. Its answers settle your questions, so do not ask the user about anything the spec already answers.

## Start

0. If `approved_at` in `spec.md` is empty, nobody approved the spec. Set `status` to `drafting`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` and follow it.
1. If `status` is `waiting-user`, read the last item of `stopped_for_user` in `run-log.md`. Go on as "Stop items" in `SKILL.md` says for its `stage`.
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

Execute never pushes `wstack/<slug>` and never opens the pull request. The Deliver stage does both. When the spec lists `open a pull request` under `## Deliver targets`, the user's approval of the spec removes the stop of Deliver for those two actions. A merge always asks.

Before a non-undoable step, stop:

1. Write a `stop` line in `run-log.md` with the reason.
2. Append a stop item with `"stage":"execute"` and the reason, as "Stop items" in `SKILL.md` says.
3. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user the step and the reason. Ask for a yes or no. End the reply. Wait.

If the guard hook asks or denies a command, treat it as a non-undoable step and stop the same way.

Stop also when the spec is wrong or unclear. Stop the same way with the reason `spec unclear: <question>`. In step 4, ask the question instead of a yes or no.

## After the user answers a stop

This rule runs the same way when the user answers in the same session and when a resumed task reaches Start step 1.

If the reason starts with `retry_limit`, follow "Retry-limit stop" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/verify.md` instead.

If the reason starts with `spec unclear`:

- The answer changes the spec: set `status` to `drafting`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` and follow it. The changed spec needs a new approval.
- The answer changes nothing in the spec: set `status` to `executing`, write a `step` line with the answer, and go on with the work.

For a stop before a non-undoable step:

- Yes: set `status` to `executing`, write a `step` line, and run the stopped step with the prefix `WSTACK_APPROVED=1`.
- No: keep `status` as `waiting-user` and ask what to change.

Add the prefix `WSTACK_APPROVED=1` to a command only after the user says yes in this session. Never add it before.

## Retry

When a try fails, write a `retry` line, read `retries` from `run-log.md`, add 1, and set it with `frontmatter-set.sh`. Then try again. Execute and Verify share this one counter, as `verify.md` says. Take the retry limit from the Config list in `SKILL.md`. When `retries` reaches the limit, stop as above with the reason `retry_limit reached`.

## Thinking and ops work

Write the result as a new note in `$vault`. Never overwrite an existing note. If the name is taken, add `-2`, `-3`, and so on. Undo means: delete that note.

## Learning tasks

- Input: find and prepare material for the user to read, watch, or study.
- Output: help the user make notes, a blog post, or a talk. Test what the user learned with quizzes, flashcards, or an "explain it back" exercise.

## Finish

When the spec is met, write a `step` line that says so. Set `status` to `verifying`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/verify.md` and follow it.
