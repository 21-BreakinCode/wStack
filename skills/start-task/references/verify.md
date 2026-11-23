# Verify

Goal: prove the result works, prove it can be undone, and have it reviewed. Done when every check has a pass result with evidence, the undo steps exist, and no blocking finding is open.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `frontmatter-set.sh`. Read the spec first. Write results to `review.md` in the task folder. If `review.md` is not there, copy it from `${CLAUDE_PLUGIN_ROOT}/templates/review.md` and set its `task_id`.

## Order

Run the six steps in this order. If `result` in `review.md` is already `pass` when you start (a resumed task), skip to "Go on to Deliver".

1. Behavior check. First delete every line under `## Evidence` in `review.md`, so each check keeps one line. Run each check in the spec's `## Verification plan`. For each check, run the `capture-evidence` skill. It saves the evidence in `/tmp/wstack-evidence/<task_id>/` and writes one line per check under `## Evidence` in `review.md`: `- <check> → <file> → pass|fail`. A check whose only evidence is command output still gets a line. Save the output as a file in that folder. If a check fails, go to "A check fails".
   For each check that runs tests, save the test output to a file under `$TMPDIR` and run `bash "$scripts/find-test-skips.sh" "<output file>"` on it. Exit 1 means the run skipped cases. A skip line fails the check, unless `## Verification plan` in the spec names that skip with a reason. Put the skip lines in the evidence line of the check.
2. Stale references. If `## Moves and renames` in the spec lists a move or a rename, or if the diff has an `R` or `D` entry, run this step. Use the same base as step 4 uses for the diff: the merge base of `HEAD` and `origin/<base_branch>`, from `git -C "<repository folder>" merge-base HEAD "origin/<base_branch>"`. Run `bash "$scripts/find-stale-refs.sh" --repo "<repository folder>" --base "<merge base>"` and add one `--old "<old form>"` for each old form in the spec section. Exit 1 means hits. Write the hits as the evidence of the check `stale references`. Give each hit to the reviewer in step 4. Exit 2 means bad input: fix the call.
3. Rollback check. Find the undo method for the work type in the spec. Confirm that it works. Write the undo steps under `## Decisions` in `review.md`. If no working undo exists, treat it as a failed check.
4. Final review. Dispatch the `wstack:reviewer` agent defined in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`. Give it the task folder, the change (a diff file or a git range), and the stale-reference hits of step 2. If `$task_dir/contract-brief.md` exists, read the contract path with `source "$scripts/lib/frontmatter.sh"; fm_get "$task_dir/contract-brief.md" contract_file` and also give it the contract path. If `contract-brief.md` does not exist, the task has no contract: give the reviewer no contract path. For a `contract` task, tell it to check each claim in `contract.draft.md` against the code at `origin/<base_branch>`. Each claim needs a `file:line` reference. For a new project, it checks that each section has content. It writes its findings into `review.md` and sets both finding counts. If `agents/reviewer.md` is not there, stop with the reason `missing agents/reviewer.md`, as in "Stop for the user".
5. Upload the evidence. Run this after the last compression and before the page build. Run it for every task type that saved evidence.

   ```bash
   bash "$scripts/evidence-upload.sh" --task-id <task_id> --dir "/tmp/wstack-evidence/<task_id>" --bucket "<r2_bucket>" --domain "<evidence_domain>" --repo "<repo>" --local-only-repos "<local_evidence_only_repos>"
   ```

   Take the values from the Config list in `SKILL.md`. For a task with no repository, pass an empty `--repo`. The script prints `local only: <dir>` or one `https://<domain>/evidence/<task_id>/<file>` line per file. If it exits non-zero, stop with the reason `evidence upload failed`, as in "Stop for the user". Then extend each evidence line under `## Evidence` in `review.md`: `- <check> → <file> → pass|fail → <link>`. Use the printed URL whose last part is the file name. Use `local only` when the script printed `local only` or printed no URL for that file. Set `evidence_location` in the `review.md` frontmatter to `r2` or `local only`.
6. Review page. Run the `build-review-page` skill to build `review.html` in `$HOME/.wstack/pages/<task_id>/`. If the skill is not there, stop with the reason `missing build-review-page skill`, as in "Stop for the user".

After step 4, set `blocking_findings` and `non_blocking_findings` in the `review.md` frontmatter to the counts. A blocking finding is a spec mismatch, a correctness bug, or a security problem. Go to "A check fails" for each open blocking finding. A non-blocking finding (design or test coverage) does not stop the task.

When all six steps pass, set `result` to `pass` in `review.md`. Write a `step` line in `run-log.md`.

## Go on to Deliver

Run the `deliver-task` skill and follow it. It reads `status` as `verifying` and `result` as `pass`. If the `deliver-task` skill is not there, stop with the reason `missing deliver-task skill`, as in "Stop for the user".

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

Use this stop for the retry limit, a missing file, a missing tool, and a failed evidence upload.

1. Write a `stop` line in `run-log.md`.
2. Append a stop item with `"stage":"verify"` and the reason, as "Stop items" in `SKILL.md` says. For the retry limit, the reason is `retry_limit reached: <failed check>`.
3. Set `result` to `waiting` in `review.md`. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user the reason. For the retry limit, name the check that keeps failing and the number of tries, and offer three choices: try again with their direction, change the spec, or cancel. For any other stop, ask the user to fix the cause and to tell you when it is fixed. End the reply. Wait.

## After the user answers a stop

This rule runs the same way in the same session and in a resumed task. "Stop items" in `SKILL.md` sends a `verify` stop here. `execute.md` sends an Execute retry-limit stop here. Resume the stage that the item names in `stage`.

Retry-limit stop:

- Try again: set `retries` to `0`, set `status` to `executing`, and write a `step` line with the user's direction. Fix the work. If `stage` is `verify`, set `status` to `verifying` and run the Order again from step 1. If `stage` is `execute`, go on with Execute.
- Change the spec: set `retries` to `0` and `status` to `drafting`. Then follow `confirmation.md`.
- Cancel: write `retro-note.md` as step 6 of "Finish" in `${CLAUDE_PLUGIN_ROOT}/skills/deliver-task/SKILL.md` says. The note covers the work done so far, because Deliver never ran. `## Spec gaps` or `## Surprises` names the cause of the stop, with its `run-log.md` stop line. Then set `status` to `cancelled`.

Any other stop (a missing file, a missing tool, or a failed evidence upload):

- The user fixed the cause: set `status` to `verifying` and run the Order again from the step that stopped.
- Cancel: set `status` to `cancelled`.
