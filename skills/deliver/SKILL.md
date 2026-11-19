---
name: deliver
description: Use only inside a wStack task session, to deliver the finished work.
user-invocable: false
---

# Deliver

Goal: ship every target in the spec, write `report.md`, and close the task. Done when `status` is `delivered`, or when the task waits for the user's approval of a non-undoable target.

Set `$task_dir`, `$vault`, and `$scripts` as in the start-task skill. Change every frontmatter field with `frontmatter-set.sh`. Read the spec, `review.md`, and `run-log.md` first.

## Start

Two things start Deliver. Verify starts it with `status` as `verifying` and `result` as `pass`. The router starts it with `status` as `awaiting-deliver-approval`.

1. If `status` is `awaiting-deliver-approval`, go to "After the user answers".
2. Otherwise, if `result` in `review.md` is not `pass`, stop. Tell the user that Verify is not done.
3. If `report.md` is not in the task folder, copy `${CLAUDE_PLUGIN_ROOT}/templates/report.md` there and set its `task_id`.

## Sort the targets

Read `## Deliver targets` in the spec. Sort each target with this table.

| Work type | Target | Undo | Approval |
|---|---|---|---|
| code | open a pull request | yes | no |
| code | merge | treated as no | always |
| code | deploy | no | yes |
| thinking, ops | new Obsidian note | yes | no |
| blog | draft on the blog platform | yes | no |
| blog | publish | no | yes |
| video | rendered file in a folder | yes | no |
| video | upload to a platform | no | yes |

A target in the spec's `## Non-undoable steps` needs approval too. The user approved the spec, so the pull request target needs no new approval, and that covers the push of `wstack/<slug>`.

Run all targets that need no approval first. Then handle the ones that need approval.

## Ship a target that needs no approval

### Pull request

1. Work in `workspace_cwd`. Take `<slug>` from the task id without its date prefix.
2. Check for an open pull request: `gh pr list --head wstack/<slug> --state open --json number,url`. If the list holds one, use its `url` and skip the other steps.
3. Run `git push -u origin wstack/<slug>`. If it fails, stop as in "Stop".
4. Write the pull request body to `$task_dir/pr-body.md`: the goal, what changed, the review result, and the evidence links from `review.md`. Use the evidence skill's rule for text logs: put them in the body as text.
5. Run `bash "$scripts/pr-attach.sh" --task-id <task_id> --title "<title>" --body-file "$task_dir/pr-body.md" --max-mb <pr media limit> <evidence files>`. The evidence files are the media files in `/tmp/wstack-evidence/<task_id>/`. Add `--base <default branch>` when the repository default is not what `gh` picks.
6. Act on the exit code.
   - Exit 0: take the pull request URL from the last URL in the output. If the output says `attachment upload failed`, say so in the report.
   - Exit 3: the pull request does not exist. Never run it again. Stop as in "Stop".
   - Exit 1 or 2: read stderr. Stop as in "Stop".
7. Record the target: `bash "$scripts/frontmatter-set.sh" --append "$task_dir/report.md" targets '{"target":"pull request","url":"<url>","undo":"gh pr close <number>"}'`.

### Obsidian note

Execute already wrote the note in `$vault`. Never write it again. Record it: `{"target":"obsidian note","url":"<absolute note path>","undo":"delete the note <absolute note path>"}`.

### Blog draft and rendered video file

Make the draft or the file. Record its URL or path and the undo, which is to delete the draft or the file.

## Targets that need approval

If every target is shipped, skip this section.

1. Write the short report in your reply: each waiting target, what it does, and how to undo it, or that it cannot be undone. For a merge, name the pull request and say that other people can see a merge before a revert.
2. Run `bash "$scripts/frontmatter-set.sh" "$task_dir/report.md" approval_needed true`.
3. Write a `stop` line in `run-log.md`. Run `bash "$scripts/frontmatter-set.sh" --append "$task_dir/run-log.md" stopped_for_user '{"at":"<ISO time>","stage":"deliver","reason":"<target> needs approval"}'`.
4. Set `status` to `awaiting-deliver-approval` in `spec.md`.
5. Ask the user for a yes or no on each waiting target. End the reply with that question. Write nothing after it. Never run the target before the answer.

## After the user answers

This rule runs the same way in the same session and in a resumed task. Read the last item of `stopped_for_user` in `run-log.md` to find the waiting target.

- No: keep `status` as `awaiting-deliver-approval`. Ask what to change. If the user wants to drop the target, remove it from the spec's `## Deliver targets` first, then finish as below.
- Yes: set `approved_at` in `report.md` to `date -u +%Y-%m-%dT%H:%M:%SZ`. Run the target with the prefix `WSTACK_APPROVED=1`. After a failed target, run it again. Add the prefix only after the yes. Never add it before.

### Merge

1. Find the pull request number with `gh pr list --head wstack/<slug> --state open --json number,url`.
2. Run `WSTACK_APPROVED=1 gh pr merge <number> --merge`. Always use `--merge`. Never squash.
3. If the merge works, delete the evidence in R2. Skip this if `r2_bucket` is empty or the repository is in the local-only list: `bash "$scripts/evidence-delete.sh" --task-id <task_id> --bucket "<r2_bucket>"`. The guard asks before this runs. Run it with `WSTACK_APPROVED=1` after the user's yes to the merge.
4. Record the target: `{"target":"merge","url":"<pull request url>","undo":"gh pr revert <number>, other people can see the merge first"}`.

### Other targets

Run the target. Record its URL and its undo, or `"undo":"none"` if it has none.

## Finish

1. Fill `## What shipped`, `## Where`, and `## How to undo` in `report.md`. List each target with its URL, and each undo step.
2. If `HERDR_ENV` is `1` and the task has a worktree or a workspace, add the cleanup command under `## How to undo`. Run `herdr workspace list` to find the workspace whose label is the task slug. Write `herdr worktree remove --workspace <id>` for a code task with a worktree. Write `herdr workspace close <id>` for any other task. Write the command only. Never run it.
3. Set `delivered_at` and `approval_needed` in `report.md`. Set `delivered_at` to `date -u +%Y-%m-%dT%H:%M:%SZ`. Keep `approval_needed` as `true` only if a target waited for the user.
4. Set `ended_at` in `run-log.md` to the same kind of time.
5. Count the tokens: `bash "$scripts/session-tokens.sh" "<workspace_cwd>"`. Set `tokens_used` in `run-log.md` to the number. If the script exits 2, leave `tokens_used` empty and write a `step` line: `tokens_used not available`.
6. Set `status` to `delivered` in `spec.md`.
7. Tell the user what shipped, where, and how to undo it. Ask nothing.

## Stop

Use this stop when a target fails. Never retry the target.

1. Write a `stop` line in `run-log.md`.
2. Run `bash "$scripts/frontmatter-set.sh" --append "$task_dir/run-log.md" stopped_for_user '{"at":"<ISO time>","stage":"deliver","reason":"<reason>"}'`.
3. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user the reason. Ask for a yes or no to try again. End the reply. Wait.
