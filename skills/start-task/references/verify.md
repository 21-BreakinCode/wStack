# Verify

Goal: prove the result works, prove it can be undone, and have it reviewed. Done when every check has a pass result with evidence, the undo steps exist, and no blocking finding is open.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `frontmatter-set.sh`. Read the spec first. Write results to `review.md` in the task folder. If `review.md` is not there, copy it from `${CLAUDE_PLUGIN_ROOT}/templates/review.md` and set its `task_id`.

## Order

Run the four steps in this order.

1. Behavior check. Run each check in the spec's `## Verification plan`. Under `## Evidence` in `review.md`, write one line per check: the check, the command or output you saw, and `pass` or `fail`. If a check fails, go to "A check fails".
2. Rollback check. Find the undo method for the work type in the spec. Confirm that it works. Write the undo steps under `## Decisions` in `review.md`. If no working undo exists, treat it as a failed check.
3. Final review. Start the reviewer agent in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`. It writes its findings into `review.md`. If the file is not there, tell the user the reviewer is not available yet and stop.
4. Review page. Run the review-page skill to build `review.html` in the task folder. If the skill is not there, tell the user it is not available yet and stop.

After step 3, set `blocking_findings` and `non_blocking_findings` in the `review.md` frontmatter to the counts. A blocking finding is a spec mismatch, a correctness bug, or a security problem. Go to "A check fails" for each open blocking finding. A non-blocking finding (design or test coverage) does not stop the task.

When all four steps pass, set `result` to `pass` in `review.md`. Write a `step` line in `run-log.md`. Then go on to Deliver. If the Deliver stage is not available, tell the user and stop. The status stays `verifying`.

## A check fails

First decide who is wrong.

- The spec is wrong or unclear when the plan contradicts the goal. A check that the goal asks for and the work cannot meet is a failed try, not a wrong spec. Set `result` to `waiting` in `review.md`. Set `status` to `drafting`. Name the contradiction to the user. Make the last line of the reply one question about which side is right. Write nothing after it. Confirmation takes over. A wrong spec does not count as a retry.
- The work is wrong in every other case. Set `result` to `fail` in `review.md`. Count the failed try as below.

## Count the try

Execute and Verify share one counter, `retries` in `run-log.md`. A failed try in either stage adds 1.

1. Write a `retry` line in `run-log.md` that names the failed check.
2. Read `retries`, add 1, and set it: `bash "$scripts/frontmatter-set.sh" "$task_dir/run-log.md" retries <value>`.
3. Take the retry limit from the Config list in `SKILL.md`. If `retries` is less than the limit, set `status` to `executing`, fix the work, set `status` back to `verifying`, and run the order again from step 1.
4. If `retries` reached the limit, stop as below.

Never ask the user between tries. If you find no fix inside the spec's scope, run the order again anyway, so the next failure counts. Never end a reply while `status` is `executing` or `verifying`. Only the retry-limit stop or the wrong-spec path ends the loop.

## Stop at the retry limit

1. Write a `stop` line in `run-log.md`.
2. Run `bash "$scripts/frontmatter-set.sh" --append "$task_dir/run-log.md" stopped_for_user '{"at":"<ISO time>","reason":"retry_limit reached: <failed check>"}'`.
3. Set `result` to `waiting` in `review.md`. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user which check keeps failing and how many tries you made. Offer three choices: try again with their direction, change the spec, or cancel. End the reply. Wait.

## After the user answers a retry-limit stop

This rule runs the same way in the same session and in a resumed task. In a resumed task, `SKILL.md` sends `waiting-user` to `execute.md`, which sends you here when the last stop reason holds `retry_limit`.

- Try again: set `retries` to `0`, set `status` to `executing`, write a `step` line with the user's direction, and fix the work. Then run Verify again.
- Change the spec: set `status` to `drafting` and follow `confirmation.md`.
- Cancel: set `status` to `cancelled`.
