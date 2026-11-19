# Verify

Goal: prove the result works, prove it can be undone, and have it reviewed. Done when every check has a pass result with evidence, the undo steps exist, and no blocking finding is open.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `frontmatter-set.sh`. Read the spec first. Write results to `review.md` in the task folder. If `review.md` is not there, copy it from `${CLAUDE_PLUGIN_ROOT}/templates/review.md` and set its `task_id`.

## Order

Run the five steps in this order. If `result` in `review.md` is already `pass` when you start (a resumed task), skip to "Go on to Deliver".

1. Behavior check. Run each check in the spec's `## Verification plan`. For each check, run the evidence skill. It saves the evidence in `/tmp/wstack-evidence/<task_id>/` and writes one line per check under `## Evidence` in `review.md`: `- <check> → <file> → pass|fail`. A check whose only evidence is command output still gets a line. Save the output as a file in that folder. If a check fails, go to "A check fails".
2. Rollback check. Find the undo method for the work type in the spec. Confirm that it works. Write the undo steps under `## Decisions` in `review.md`. If no working undo exists, treat it as a failed check.
3. Final review. Dispatch the `wstack:reviewer` agent defined in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`. Give it the task folder and the change (a diff file or a git range). It writes its findings into `review.md` and sets both finding counts. If the file is not there, stop with the reason `missing agents/reviewer.md`, as in "Stop for the user".
4. Upload the evidence. Run this after the last compression and before the page build. Run it for every task type that saved evidence.

   ```bash
   bash "$scripts/evidence-upload.sh" --task-id <task_id> --dir "/tmp/wstack-evidence/<task_id>" --bucket "<r2_bucket>" --domain "<evidence_domain>" --repo "<repo>" --local-only-repos "<local_evidence_only_repos>"
   ```

   Take the values from the Config list in `SKILL.md`. For a task with no repository, pass an empty `--repo`. The script prints `local only: <dir>` or one `https://<domain>/evidence/<task_id>/<file>` line per file. If it exits non-zero, stop with the reason `evidence upload failed`, as in "Stop for the user". Then extend each evidence line under `## Evidence` in `review.md`: `- <check> → <file> → pass|fail → <link>`. Use the printed URL whose last part is the file name. Use `local only` when the script printed `local only` or printed no URL for that file. Set `evidence_location` in the `review.md` frontmatter to `r2` or `local only`.
5. Review page. Run the review-page skill to build `review.html` in the task folder. If the skill is not there, stop with the reason `missing review-page skill`, as in "Stop for the user".

After step 3, set `blocking_findings` and `non_blocking_findings` in the `review.md` frontmatter to the counts. A blocking finding is a spec mismatch, a correctness bug, or a security problem. Go to "A check fails" for each open blocking finding. A non-blocking finding (design or test coverage) does not stop the task.

When all five steps pass, set `result` to `pass` in `review.md`. Write a `step` line in `run-log.md`.

## Go on to Deliver

Run the deliver skill and follow it. It reads `status` as `verifying` and `result` as `pass`. If the deliver skill is not there, stop with the reason `missing deliver skill`, as in "Stop for the user".

## A check fails

First decide who is wrong.

- The spec is wrong or unclear when the plan contradicts the goal. A check that the goal asks for and the work cannot meet is a failed try, not a wrong spec. Set `result` to `waiting` in `review.md`. Set `retries` to `0` and `status` to `drafting`, so the new spec gets a fresh run of tries. Name the contradiction to the user. Make the last line of the reply one question about which side is right. Write nothing after it. Confirmation takes over. A wrong spec does not count as a retry.
- The work is wrong in every other case. Set `result` to `fail` in `review.md`. Count the failed try as below.

## Count the try

Execute and Verify share one counter, `retries` in `run-log.md`. A failed try in either stage adds 1.

1. Write a `retry` line in `run-log.md` that names the failed check.
2. Read `retries`, add 1, and set it: `bash "$scripts/frontmatter-set.sh" "$task_dir/run-log.md" retries <value>`.
3. Take the retry limit from the Config list in `SKILL.md`. If `retries` is less than the limit, set `status` to `executing`, fix the work, set `status` back to `verifying`, and run the order again from step 1.
4. If `retries` reached the limit, stop as below.

Never ask the user between tries. If you find no fix inside the spec's scope, run the order again anyway, so the next failure counts. Never end a reply while `status` is `executing` or `verifying`. Every reply ends through a stop below, the wrong-spec path, or a change to the next stage.

## Stop for the user

Use this stop for the retry limit and for a missing stage file. Execute uses it too, with `"stage":"execute"`.

1. Write a `stop` line in `run-log.md`.
2. Run `bash "$scripts/frontmatter-set.sh" --append "$task_dir/run-log.md" stopped_for_user '{"at":"<ISO time>","stage":"verify","reason":"<reason>"}'`. For the retry limit, the reason is `retry_limit reached: <failed check>`.
3. Set `result` to `waiting` in `review.md`. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user the reason. For the retry limit, name the check that keeps failing and the number of tries, and offer three choices: try again with their direction, change the spec, or cancel. For a missing file, ask the user to confirm when it is there. End the reply. Wait.

## After the user answers a stop

This rule runs the same way in the same session and in a resumed task. In a resumed task, `SKILL.md` sends `waiting-user` to `execute.md`, which sends you here when the last stop item has `"stage":"verify"` or a reason that holds `retry_limit`. Resume the stage that the item names in `stage`.

Retry-limit stop:

- Try again: set `retries` to `0`, set `status` to `executing`, and write a `step` line with the user's direction. Fix the work. If `stage` is `verify`, set `status` to `verifying` and run the Order again from step 1. If `stage` is `execute`, go on with Execute.
- Change the spec: set `retries` to `0` and `status` to `drafting`. Then follow `confirmation.md`.
- Cancel: set `status` to `cancelled`.

Missing-file stop:

- The file is there: set `status` to `verifying` and run the Order again from the step that stopped.
- Cancel: set `status` to `cancelled`.
