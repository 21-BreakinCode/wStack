---
name: deliver-task
description: Use only inside a wStack task session, to deliver the finished work.
user-invocable: false
---

# Deliver

Goal: ship every target in the spec, write `report.md`, and close the task. Done when `status` is `delivered`, or when the task waits for the user's approval of a non-undoable target.

Set `$task_dir`, `$vault`, and `$scripts` as in the start-task skill. Change every frontmatter field with `frontmatter-set.sh`. Read the spec, `review.md`, and `run-log.md` first.

The Bash blocks in this skill hold placeholders such as `<task folder>`. Write the real value in place of each one. Inside single quotes, write each `'` of a value as `'\''`.

## Start

Two things start Deliver. Verify starts it with `status` as `verifying` and `result` as `pass`. The router starts it with `status` as `awaiting-deliver-approval`, or as `waiting-user` after a Deliver stop.

1. If `status` is `awaiting-deliver-approval` or `waiting-user`, go to "After the user answers".
2. Otherwise, if `result` in `review.md` is not `pass`, stop. Tell the user that Verify is not done.
3. If `report.md` is not in the task folder, copy `${CLAUDE_PLUGIN_ROOT}/templates/report.md` there and set its `task_id`.

## Sort the targets

Read `## Deliver targets` in the spec. Match each line to a row of this table. The Target column is the one name of a target. Use that name, never the raw spec text, in every stop item, in every `targets` item of `report.md`, and in every check below.

| Work type | Target | Undo | Approval |
|---|---|---|---|
| code | open a pull request | yes | no |
| code | merge | treated as no | always |
| code | deploy | no | yes |
| thinking, ops | new Obsidian note | yes | no |
| blog | draft on the blog platform | yes | no |
| blog | publish | no | yes |
| contract | write the contract files | yes | no |
| video | rendered file in a folder | yes | no |
| video | upload to a platform | no | yes |

A target in the spec's `## Non-undoable steps` needs approval too. The user approved the spec, so the pull request target needs no new approval, and that covers the push of `wstack/<slug>`.

A remaining target is a target in the spec's `## Deliver targets`, by its Target name, that has no item with the same `target` value in the `targets` list of `report.md`. Ship only remaining targets. A stop item gives only the reason of a stop. It never decides which targets remain.

Run all remaining targets that need no approval first. Then handle the ones that need approval.

## Ship a target that needs no approval

### Pull request

1. Work in `workspace_cwd`. Take `<slug>` from the task id without its date prefix.
2. Check for an open pull request: `gh pr list --head wstack/<slug> --state open --json number,url`. If the list holds one, use its `url` and go to step 7.
3. Run `git push -u origin wstack/<slug>`. If it fails, stop as in "Stop".
4. Write the pull request body to `$task_dir/pr-body.md`: the goal, what changed, the review result, and the evidence links from `review.md`. Use the `capture-evidence` skill's rule for text logs: put them in the body as text. If the repository is in `local_evidence_only_repos`, leave the text logs out of the body.
5. Run `bash "$scripts/pr-attach.sh" --task-id <task_id> --title "<title>" --body-file "$task_dir/pr-body.md" --max-mb <pr media limit> --repo "<repo>" --local-only-repos "<local_evidence_only_repos>" <evidence files>`. Take both values as Verify does for `evidence-upload.sh`. For a listed repository, `pr-attach.sh` attaches nothing and says why. The evidence files are the top-level media files in `/tmp/wstack-evidence/<task_id>/`, never the files in its subfolders. `pr-attach.sh` makes the GitHub copies. Add `--base <default branch>` when the repository default is not what `gh` picks.
6. Act on the exit code.
   - Exit 0: take the pull request URL from the last URL in the output. If the output says `attachment upload failed`, say so in the report. If the output says `attachments skipped`, say why in the report.
   - Exit 3: the pull request does not exist. Stop as in "Stop". A retry starts again at step 1, so step 2 checks for an open pull request first. Never create a second pull request.
   - Exit 1 or 2: read stderr. Stop as in "Stop".
7. Record the target: `bash "$scripts/frontmatter-set.sh" --append "$task_dir/report.md" targets '{"target":"open a pull request","url":"<url>","undo":"gh pr close <number>"}'`.

### Obsidian note

Execute already wrote the note in `$vault`. Never write it again. Record it: `{"target":"new Obsidian note","url":"<absolute note path>","undo":"delete the note <absolute note path>"}`.

### Blog draft and rendered video file

Make the draft or the file. Record its URL or path and the undo, which is to delete the draft or the file.

### Contract files

Use this for the `write the contract files` target of a `contract` task. The drafts are in `$task_dir`: `contract.draft.yaml` and `decisions.draft/`.

1. Find the contract path: `bash "$scripts/contract-path.sh" --vault "$vault" "<workspace_cwd>"`. `<workspace_cwd>` is the `workspace_cwd` value in the spec frontmatter. If it exits 1, stop as in "Stop" with the reason `repository not mapped: run /wstack:init-service`. If it exits 2, stop as in "Stop" with the stderr text. Otherwise `<contract_file>` is the path.
2. Run `bash "$scripts/contract-deliver.sh" write '<task folder>' '<contract_file>' <task_id> >'<task folder>/contract-files.txt'`. The script takes the lock and checks the draft and the decision ids before it changes anything. Then it moves the old files of the contract folder to `_archive/<task_id>/` and copies the drafts. Last, it runs `set-verified`, which renders the vault note and the HTML page. It keeps `handover/`, `decisions/`, `_archive/`, and `<app_name>.facts.md` in place. It is safe to run again after a failure. It writes one line for each file to `contract-files.txt`: `new:`, `replaced:`, `moved:`, or `unchanged:`. "Finish" builds the file tree from these lines.

   Exit 4 means the lock is busy. Write a `stop` line in `run-log.md`. Append a stop item with `"stage":"deliver"`, `"target":"write the contract files"`, and the stderr text as the reason. Set `status` to `waiting-user` and stop. Exit 1 means a check or a step failed, and the stderr text names it. Write the same `stop` line and stop item with the stderr text, and stop.
3. If `$task_dir/disagreements.md` exists and `report.md` has no `## Doc and code disagree` heading, add that heading at the end of `report.md`. Copy the lines of `disagreements.md` under it.
4. Record the target: `{"target":"write the contract files","url":"<contract_file>","undo":"bash <scripts>/contract-deliver.sh undo '<task folder>' '<contract_file>' <task_id>"}`. Write the real values for `<scripts>`, `<task folder>`, `<contract_file>`, and `<task_id>`. The undo deletes the new files and moves the archived files back, all or nothing.

## Contract write-back

Run this once, right after the `open a pull request` target is recorded, for a `code` or `ops` task. If `$task_dir/contract-brief.md` does not exist, the task has no contract: skip this section. If `targets` in `report.md` already holds a `contract write-back` item, skip it too.

Read the values in the same Bash call as the commands that use them: `source "$scripts/lib/frontmatter.sh"; contract_file="$(fm_get "$task_dir/contract-brief.md" contract_file)"`, and the same for `base_branch`. The contract folder is the folder that holds `$contract_file`. `<pr>` is the number at the end of the pull request URL.

1. Dispatch the `wstack:contract-reader` agent. Give it the repository folder, the contract path, and this input: "propose contract edits for the diff `origin/<base_branch>...wstack/<slug>` and the spec's `## Contract changes`". Write the part of the reply after the line `=== PATCH ===` to `$task_dir/contract.patch.yaml`. It is YAML with a `sections:` map and an optional `remove_planned:` list of plan ids. If that part is `None`, write no patch file and skip step 2. Decisions do not depend on the patch, so step 3 still runs.
2. Add the pending item. Run this in one Bash call. Write the real values for `<task folder>`, `<pr>`, and `<task_id>`:

   ```bash
   set -e
   scripts="${CLAUDE_PLUGIN_ROOT}/scripts"
   task_dir='<task folder>'
   source "$scripts/lib/frontmatter.sh"
   contract_file="$(fm_get "$task_dir/contract-brief.md" contract_file)"
   bash "$scripts/contract-edit.sh" lock "$contract_file"
   trap 'bash "$scripts/contract-edit.sh" unlock "$contract_file"' EXIT
   bash "$scripts/contract-edit.sh" pending-add "$contract_file" <pr> <task_id>
   ```

   Exit 4 means the lock is busy. Write a `stop` line in `run-log.md`. Append a stop item with `"stage":"deliver"`, `"target":"contract write-back"`, and the stderr text as the reason. Set `status` to `waiting-user` and stop. Any other non-zero exit means a command failed after the lock. The trap already ran `unlock`. Write the same `stop` line and stop item with the stderr text, and stop.
3. Write the decision files. If the spec's `## Decisions` is `None`, skip this step. For each item, write a draft `$task_dir/decisions.writeback/<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/decision.md`. Leave `{{id}}` as it is. Fill `{{date}}`, `{{title}}`, and `{{task_id}}`. Fill `{{tasks_dir}}` from `$tasks_dir`. Fill `## Context`, `## Options`, `## Choice`, and `## Why` from the item. If the pull request adds a file under `docs/adr/`, the decision file links that path and copies no text from it. Then number and copy the drafts in one Bash call, under the lock, so that two tasks cannot take the same id:

   ```bash
   set -e
   setopt NULL_GLOB 2>/dev/null || true
   scripts="${CLAUDE_PLUGIN_ROOT}/scripts"
   task_dir='<task folder>'
   source "$scripts/lib/frontmatter.sh"
   contract_file="$(fm_get "$task_dir/contract-brief.md" contract_file)"
   decisions_dir="$(dirname "$contract_file")/decisions"
   bash "$scripts/contract-edit.sh" lock "$contract_file"
   trap 'bash "$scripts/contract-edit.sh" unlock "$contract_file"' EXIT
   mkdir -p "$decisions_dir"
   for draft in "$task_dir/decisions.writeback"/*.md; do
     decision_file=""
     for existing in "$decisions_dir"/[0-9][0-9][0-9][0-9]-"$(basename "$draft")"; do
       [ -e "$existing" ] || continue
       if grep -s '^task: ' "$existing" | grep -qF "/$(basename "$task_dir")/spec]]"; then decision_file="$existing"; fi
     done
     if [ -z "$decision_file" ]; then
       id="$(bash "$scripts/contract-edit.sh" next-decision-id "$decisions_dir")"
       decision_file="$decisions_dir/$id-$(basename "$draft")"
       sed "s/{{id}}/$id/g" "$draft" > "$decision_file"
     fi
     echo "decision file: $decision_file"
   done
   ```

   A decision file `<id>-<slug>.md` with the same slug and the same `task` link is a copy from an earlier run of this step. The block keeps it and its id, so a retry makes no second copy. Act on a non-zero exit as in step 2.
4. Record the target: `bash "$scripts/frontmatter-set.sh" --append "$task_dir/report.md" targets '{"target":"contract write-back","url":"<contract_file>","undo":"bash <scripts>/contract-edit.sh pending-remove <contract_file> <pr>, and delete <decision files>"}'`. Write the real values for `<scripts>`, `<pr>`, and `<decision files>`. The decision files are the `decision file:` lines of step 3.

The contract text does not change here. It changes after the merge, as "Pending items" says.

## Targets that need approval

If no remaining target needs approval, go to "Finish".

1. Write the short report in your reply: each remaining target that needs approval, what it does, and how to undo it, or that it cannot be undone. For a merge, name the pull request and say that other people can see a merge before a revert. If `r2_bucket` is set and the repository is not in the local-only list, also say that a yes to the merge deletes `evidence/<task_id>/` in `<r2_bucket>` after the merge.
2. Run `bash "$scripts/frontmatter-set.sh" "$task_dir/report.md" approval_needed true`.
3. Write a `stop` line in `run-log.md`. Append one stop item for each of these targets, with `"stage":"deliver"`, its `"target"`, and the reason `<target> needs approval`, as "Stop items" in the start-task skill says.
4. Set `status` to `awaiting-deliver-approval` in `spec.md`.
5. Ask the user for a yes or no on each of these targets. End the reply with that question. Write nothing after it. Never run the target before the answer.

## After the user answers

This rule runs the same way in the same session and in a resumed task. If `status` is `waiting-user`, a target failed. Go to "Retry a failed target". Otherwise find the first remaining target that needs approval and handle only that one. Ask the user about the next one in the same reply when the user has not answered it yet.

- No: keep `status` as `awaiting-deliver-approval`. Ask what to change. If the user wants to drop the target, remove it from the spec's `## Deliver targets` first. A dropped target does not remain. Then go on as in "When no target remains".
- Yes: set `approved_at` in `report.md` to `date -u +%Y-%m-%dT%H:%M:%SZ`. Run the target.

### Merge

1. Find the pull request number with `gh pr list --head wstack/<slug> --state open --json number,url`.
2. Run `gh pr merge <number> --merge`. Always use `--merge`. Never squash.
3. If the merge works, delete the evidence in R2. Skip this if `r2_bucket` is empty or the repository is in the local-only list: `bash "$scripts/evidence-delete.sh" --task-id <task_id> --bucket "<r2_bucket>"`. The merge question named this delete, so the yes to the merge covers it. The guard still asks before the merge and before the delete.
4. Record the target: `{"target":"merge","url":"<pull request url>","undo":"gh pr revert <number>, other people can see the merge first"}`.

### Other targets

Run the target. Record its URL and its undo, or `"undo":"none"` if it has none.

### Retry a failed target

The failed target is the `target` of the last stop item, and `status` is `waiting-user`.

- Yes: set `status` to `verifying`, so a resumed task comes back to Deliver through Verify. For a target that needs approval, set `approved_at` in `report.md`. Never do this for a target that needs no approval. For `open a pull request`, run the steps of "Pull request" again from step 1. For another target, run its steps again. Record the target as usual. If it fails again, stop again as in "Stop".
- No: keep `status` as `waiting-user`. Ask what to change. If the user wants to drop the target, remove it from the spec's `## Deliver targets` first. Then go on as in "When no target remains".

### When no target remains

After each target, look for a remaining target. Ship a remaining target that needs no approval at once. For a remaining target that needs approval, handle it as above if the user already answered it, or else go to "Targets that need approval". Run "Finish" only when no target remains.

## Finish

1. Fill `## What shipped`, `## Where`, and `## How to undo` in `report.md`. List each target with its URL, and each undo step. Write `## Where` in this order:
   - The file tree: a code block with one line for each file that the targets wrote, labeled `NEW`, `REPLACED`, `MOVED`, or `UNCHANGED`. For a `contract` task, build it from the `new:`, `replaced:`, `moved:`, and `unchanged:` lines in `$task_dir/contract-files.txt`. Next to the label, write the old copy of a `replaced:` line and the new path of a `moved:` line. For another work type, build it from the `targets` list. A file path is `NEW`. If the file was there before the task, it is `REPLACED`. A URL, such as a pull request, gets one line with the URL.
   - One line for each repository of the task that the targets did not change: `<repository folder>: no change`. A `contract` task never changes its repository. Its result is in the vault, which is not a git repository, so `git diff` shows nothing.
   - The open commands, each in a code span: `open '<review.html>'`, where `<review.html>` is `$HOME/.wstack/pages/<task_id>/review.html`. For a `contract` task, also give `open '<contract page>'`, where `<contract page>` is `$HOME/.wstack/pages/contracts/<app_name>.html`. Also give the vault note name `<app_name>`, to open in Obsidian with Cmd+O. `<app_name>` is the output of `yq '.app_name' "$task_dir/contract.draft.yaml"`.
   - The reading order: the files in the order of `## Guided diff` in `review.md`. For a blog or video task, use `## Before and after`.
2. If `HERDR_ENV` is `1` and the task has a worktree or a workspace, add the cleanup command under `## How to undo`. Run `herdr workspace list` to find the workspace whose label is the task slug. Write `herdr worktree remove --workspace <id>` for a code task with a worktree. Write `herdr workspace close <id>` for any other task. Write the command only. Never run it. If `HERDR_ENV` is not `1` and the task is a code task, write `git -C "<repository folder>" worktree remove "<workspace_cwd>"` instead.
3. Set `delivered_at` and `approval_needed` in `report.md`. Set `delivered_at` to `date -u +%Y-%m-%dT%H:%M:%SZ`. Keep `approval_needed` as `true` only if a target waited for the user.
4. Set `ended_at` in `run-log.md` to the same kind of time.
5. Count the tokens. If `session_ids` in `spec.md` is not empty, run `bash "$scripts/session-tokens.sh"` with one `--session <id>` per id. Set `tokens_used` in `run-log.md` to line 1 and `subagent_tokens` to line 2. Otherwise run `bash "$scripts/session-tokens.sh" "<workspace_cwd>"`, set `tokens_used` to the number, and leave `subagent_tokens` empty. If the script exits 2, leave `tokens_used` and `subagent_tokens` empty and write a `step` line: `tokens_used not available`.
6. Write the exit note. If `$task_dir/retro-note.md` exists, keep it and skip this step. Otherwise copy `${CLAUDE_PLUGIN_ROOT}/templates/retro-note.md` to `$task_dir/retro-note.md`. Set `task_id`. Set `written_at` to `date -u +%Y-%m-%dT%H:%M:%SZ`. Then fill the six sections. Write them from `run-log.md` and from what you remember of the work. Next week's retro reads the note. Each bullet names its evidence: a `run-log.md` line, a file and line, or a command. A section with nothing to say holds `None.`
   - `## Slow or repeated steps`: what took long or ran again, and why.
   - `## Would script`: each step that you did by hand more than once, with the script that can replace it.
   - `## Spec gaps`: what the spec questions did not ask, and what that cost.
   - `## Tool and guard friction`: prompts, guard asks, failed commands, and waits.
   - `## Surprises`: anything else the next task needs to know.
   - `## Fact candidates`: a habit or rule of the user on this project that you learned in this task, with the reason. The weekly retro asks the user about each one.
7. Set `status` to `delivered` in `spec.md`.
8. Tell the user what shipped and how to undo it. Then give the parts of `## Where` in `report.md`: the file tree, the line for each repository that did not change, the open commands, and the reading order. Ask nothing.

## Stop

Use this stop when a target fails. Never retry the target before the user says yes.

1. Write a `stop` line in `run-log.md`.
2. Append a stop item with `"stage":"deliver"`, `"target":"<failed target>"`, and the reason, as "Stop items" in the start-task skill says.
3. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user the reason. Ask for a yes or no to try again. End the reply. Wait.

## Pending items

The contract gate runs this (step G4 of Confirmation). At G4 the brief does not exist yet. `$contract_file` comes from `contract-path.sh`, and `<base_branch>` from `yq '.base_branch' "$contract_file"`. Read `pending` with `yq -o json -I0 '.pending' "$contract_file"`. It is a list of `{"pr":<n>,"task":"<id>"}` items. If it is empty, do nothing.

For each item, run `gh pr view <pr> --json state -q .state` in the repository folder. The task folder of the item is the output of `(source "$scripts/lib/task-dir.sh" && task_dir_of "$vault" "$tasks_dir" <task>)`. It finds the task in the archive too. If it prints nothing, the folder does not exist.

- `OPEN`: keep the item.
- `gh` fails or prints another value: keep the item.
- `MERGED`: if the task folder of the item does not exist, keep the item, and tell the user the missing path. Otherwise write the change into the contract. Run this in one Bash call. `<task folder>` is the task folder of the item. The rules below the block say which lines to skip:

  ```bash
  set -e
  scripts="${CLAUDE_PLUGIN_ROOT}/scripts"
  contract_file='<contract_file>'
  task_folder='<task folder>'
  bash "$scripts/contract-edit.sh" lock "$contract_file"
  trap 'bash "$scripts/contract-edit.sh" unlock "$contract_file"' EXIT
  [ -f "$task_folder/contract.writeback.before.yaml" ] || cp "$contract_file" "$task_folder/contract.writeback.before.yaml"
  bash "$scripts/contract-edit.sh" apply "$contract_file" "$task_folder/contract.patch.yaml"
  bash "$scripts/contract-edit.sh" pending-remove "$contract_file" <pr>
  ```

  - If `<task folder>/contract.patch.yaml` does not exist, skip the `contract.writeback.before.yaml` line and the `apply` line.
  - The write-back has its own snapshot, `contract.writeback.before.yaml`, and it is written once. The gate's step 9 writes `contract.before.yaml`. An undo of the write-back keeps the gate's change and the changes of other tasks before the write-back.
  - `apply` prints the applied section keys, then one `planned removed: <id>` line for each plan item that the patch's `remove_planned` list removed. Read them from the output of the call. A shell variable does not outlive the call.
  - If `apply` printed a section key or a `planned removed:` line, set the undo of the `contract write-back` target to the undo command: `bash '<scripts>/contract-edit.sh' apply '<contract_file>' '<task folder>/contract.writeback.before.yaml' --sections '<applied keys, joined by commas>' --planned '<removed ids, joined by commas>'`. Do this in `report.md` of that task. Put each value in single quotes, as in the block. If `apply` printed no `planned removed:` line, leave out the `--planned` flag and its value. If `apply` printed no section key, leave out the `--sections` flag and its value. With `--planned` alone, `apply` restores only those plan items from the snapshot and changes no section.
- `CLOSED`: the pull request did not merge. The contract text must not change. The decision files of the item's task get `status: withdrawn`. Run this in one Bash call. `<task>` is the `task` value of the item:

  ```bash
  set -e
  setopt NULL_GLOB 2>/dev/null || true
  scripts="${CLAUDE_PLUGIN_ROOT}/scripts"
  contract_file='<contract_file>'
  source "$scripts/lib/frontmatter.sh"
  bash "$scripts/contract-edit.sh" lock "$contract_file"
  trap 'bash "$scripts/contract-edit.sh" unlock "$contract_file"' EXIT
  for decision_file in "$(dirname "$contract_file")/decisions"/*.md; do
    grep -s '^task: ' "$decision_file" | grep -qF '/<task>/spec]]' || continue
    fm_set "$decision_file" status withdrawn
    printf 'decision withdrawn: %s\n' "$decision_file"
  done
  bash "$scripts/contract-edit.sh" pending-remove "$contract_file" <pr>
  ```

  For each `decision withdrawn:` line, write a `step` line in `run-log.md` with the path and its undo: `source '<scripts>/lib/frontmatter.sh'; fm_set '<decision file>' status accepted`.

Exit 4 from `lock` means the lock is busy. Write a `stop` line in `run-log.md`. Append a stop item with the stage of the caller (`confirmation` at G4) and the reason `contract gate: <stderr text>`. Set `status` to `waiting-user` and stop. Any other non-zero exit means a command failed after the lock. The trap already ran `unlock`. Write the same `stop` line and stop item, with the reason `contract gate: <stderr text>`. Set `status` to `waiting-user` and stop. "After a stop" in Confirmation then runs the gate again from G1.

A `MERGED` item can stay stuck: its task folder is missing, or its call fails each time. For example, the patch can name a section key that the contract does not have. Then every later gate stops at it or keeps it. If the user says to drop the item, run `pending-remove` for its pull request, with the same lock and trap lines as the `MERGED` call. Do not withdraw its decisions.

`verified_commit` does not move here. The gate's own check finds what the merged change touched, and the reader compares those sections with the code.
