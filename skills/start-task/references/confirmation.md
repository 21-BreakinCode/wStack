# Confirmation

Goal: one clear spec that the user approves. When `spec.md` holds all eight sections and `approved_at` is set, this stage is done.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" <key> <value>`.

## Contract gate

Run this gate before "Write the spec". It keeps the service contract fresh. Its steps are G1 to G6, so they do not clash with the numbered steps below.

G1. If `$task_dir/contract-brief.md`, `$task_dir/contract.gate-patch.yaml`, or `$task_dir/contract.before.new.yaml` exists, delete it. Then no older gate run leaves files behind. Keep `$task_dir/contract.before.yaml`, so the undo of step 9 still restores the text from before the first gate run. If `work_type` is not `code` or `ops`, skip the rest of the gate.
G2. Run `bash "$scripts/contract-path.sh" --vault "$vault" "<repository folder>"`. Its output is `$contract_file`.
   - Exit 0: go on. If the file `$contract_file` does not exist, skip G3 and G4. Go to G5, where the check exits 3 at once.
   - Exit 1: write `Contract: not mapped` as a `step` line in `run-log.md`. Skip the rest of the gate and go on to "Write the spec".
   - Exit 2: write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the reason `contract gate: <stderr text>`, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user` and stop.
G3. Read `base_branch`: `yq '.base_branch' "$contract_file"`. Run `git -C "<repository folder>" fetch origin "<base_branch>"`. If the fetch fails, go on with the local ref `origin/<base_branch>`. G5 then adds a line about it to the brief.
G4. Resolve the pending items of the contract, as "Pending items" in the `deliver-task` skill says.
G5. Run `bash "$scripts/contract-check.sh" "<repository folder>" "$contract_file"`.
   - Exit 3: the contract file is missing. Ask the user one question: set up the contract first (a `contract` task), or go on without a contract. End the reply. Wait. To go on without a contract, go to "Write the spec" with no `contract-brief.md`. To set up the contract first, write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the reason `contract gate: set up the contract first`, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user` and stop.
   - Exit 2: tell the user the stderr text. Ask the same question, with the same meaning. End the reply. Wait.
   - Exit 0 or 1: run `git -C "<repository folder>" rev-parse "origin/<base_branch>"` right away. This is `checked_commit`. Dispatch the `wstack:contract-reader` agent. Give it the repository folder, the contract path, the Goal text, and the output of the check. Write `$task_dir/contract-brief.md` as frontmatter, then the reply before the line `=== PATCH ===`. The reply includes its `### Project facts` part, so copy that part into `contract-brief.md` as it is. The frontmatter holds four keys: `contract_file`, `base_branch`, `checked_commit`, and `stale_sections`. `stale_sections` is the one-line JSON list from the `stale_sections:` line of the check. If the fetch in G3 failed, append the line `Fetch failed: the check used the local ref origin/<base_branch>.` to `contract-brief.md`. If the part after the marker is not `None`, write it to `$task_dir/contract.gate-patch.yaml`. It is YAML with a `sections:` map and an optional `remove_planned:` list.
G6. "Write the spec" reads `contract-brief.md` together with the vault notes.

The contract file changes in two places only: G4 applies the merged write-backs of pending items, and step 9 applies the approved patch.

## Write the spec

1. Read the Obsidian notes in `$vault` that bear on the idea. If `contract-brief.md` is in the task folder, read it too. The spec follows the project facts in it. The vault is the ground truth. If `spec.md` has a `Rough idea from launch:` line under `## Goal`, that line is the idea. Step 4 replaces that line with the Goal.
2. Find the unclear parts.
   - For a rough idea, ask the user one question at a time. Send one question, then end the reply and wait. Ask until you can fill all eight sections.
   - For a written spec, ask only about the unclear parts, one question at a time. If nothing is unclear, go on.
   - For a `contract` task, do these steps first. Propose `base_branch` from the branch that recent pull requests target, and ask the user to approve it. Run `git -C "<repository folder>" fetch origin "<base_branch>"`. If the fetch fails, tell the user the stderr text. Ask one question: fix the cause, or go on with the local ref `origin/<base_branch>`. End the reply and wait. List the files with `git -C "<repository folder>" ls-tree -r --name-only "origin/<base_branch>"`. If no listed file is a source file outside the team docs, the project is new. Then take each key under `sections:` in `${CLAUDE_PLUGIN_ROOT}/templates/contract.yaml` in turn. Skip `open_questions`, because it holds only what a later task finds. Ask the user one question at a time until you know what the section will hold and which paths it will use. End the reply after each question and wait. Every `sources` glob is a planned path. Execute writes each answer as a plan item under `planned`, and the globs as the `sources` of the section. Step 4 writes the answers under `## Contract changes`. If the project has such files, it exists. Then ask no section question. List the team docs and the code areas to read under `## Contract changes`, and Execute absorbs the code, the team docs, and the vault docs.
3. If the answers change `work_type`, fix it in the frontmatter. Then run "Contract gate" again from G1, and go back to step 1.
4. If `approved_at` is set, set it to empty first: `bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" approved_at ""`. A changed spec needs a new approval. Then write the body of `spec.md` with these eight headings. Each one has content.
   - `## Goal`: what the result must do.
   - `## Scope`: what is in and what is out. For a `contract` task, also write `base_branch: <branch>` and `project: new` or `project: existing`.
   - `## Moves and renames`: each path, file name, or name that the work moves or renames, one `- <old> -> <new>` line each. If there is none, write `None`.
   - `## Verification plan`: for each check, its name, its pass rule, and the evidence it produces. For a `contract` task, write these two checks:
     1. `contract draft checks`: `bash "$scripts/contract-verify-draft.sh" "<repository folder>" "$task_dir" "<contract path>" "<task_id>" "/tmp/wstack-evidence/<task_id>"`. Pass: exit 0. Evidence: the four files `check-contract-check.txt`, `check-contract-validate.txt`, `check-contract-refs.txt`, and `check-undo-rehearsal.txt`.
     2. `claim review`: the reviewer judges whether each ref shows its claim. Pass: no blocking finding. Evidence: `## Findings` in `review.md`.
   - `## Non-undoable steps`: every step that needs the user's approval. If there is none, write `None`.
   - `## Deliver targets`: where the result goes, for example `new Obsidian note` or `open a pull request`. For a `contract` task, write `write the contract files`.
   - `## Contract changes`: the planned contract changes, or `None`. For a new `contract` project, write one line for each section: `<section>: <content>; sources: <planned globs>`. Leave out `; sources:` for `consumers` and `gotchas`, which have no `sources`. For an existing `contract` project, list the team docs and the code areas to read. A `contract` task never writes `None` here.
   - `## Decisions`: each choice between named options, with the options and the reason, or `None`.

Status stays `drafting` until the page exists.

## Show the spec

5. Copy the body of `spec.md` without its frontmatter into a draft file, under a first heading that names the task. The heading sets the page title.
   `{ printf '# %s spec\n\n' "<task_id>"; awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{f=0;next} !f' "$task_dir/spec.md"; } > "$draft"`, where `$draft` comes from `mktemp "${TMPDIR:-/tmp}/spec-draft.XXXXXX"`.
   If `contract.gate-patch.yaml` exists, put its text in the draft right after the title line, under the heading `# Contract changes from the gate`, inside a `yaml` code fence.
6. Run `mkdir -p "$HOME/.wstack/pages/<task_id>"`. Then run `bash "$scripts/render-page.sh" "$draft" "$HOME/.wstack/pages/<task_id>/spec.html"`. The pages stay outside the vault.
   - Exit 0: the page fits at 375 px.
   - Exit 1: the page is too wide. Shorten wide tables and long lines in the draft, and run it again. Stop after 3 tries and tell the user the width.
   - Exit 2: print the stderr of the script as it is. It names the cause and the fix. Write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the reason `spec page not rendered: <first stderr line>`, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user` and stop.
7. If `mobile` is `true` in the frontmatter, publish the spec page as a Claude artifact. Follow `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/mobile.md` with `$page` set to `$HOME/.wstack/pages/<task_id>/spec.html`.
8. Set `status` to `awaiting-approval`. Tell the user the path `$HOME/.wstack/pages/<task_id>/spec.html`, and ask for approval. End the reply. Wait.

If the user asks for changes, go back to step 4, then run steps 5 to 8 again.

## After approval

9. If `$task_dir/contract-brief.md` does not exist, the task has no contract. Set `approved_at` to the current UTC time, `date -u +%Y-%m-%dT%H:%M:%SZ`, and go to step 10. Otherwise, update the contract first. Run this in one Bash call. Write the real path of `$scripts` from `SKILL.md` for `<scripts folder>`, and the real task folder for `<task folder>`. Put each value in single quotes, and write each `'` in it as `'\''`.
   - If `contract.gate-patch.yaml` does not exist, skip the three lines that name `contract.before` and the `apply` line.

   ```bash
   set -e
   scripts='<scripts folder>'
   task_dir='<task folder>'
   source "$scripts/lib/frontmatter.sh"
   contract_file="$(fm_get "$task_dir/contract-brief.md" contract_file)"
   checked_commit="$(fm_get "$task_dir/contract-brief.md" checked_commit)"
   stale_sections="$(fm_get "$task_dir/contract-brief.md" stale_sections)"
   bash "$scripts/contract-edit.sh" lock "$contract_file"
   trap 'bash "$scripts/contract-edit.sh" unlock "$contract_file"' EXIT
   [ -f "$task_dir/contract.before.yaml" ] || cp "$contract_file" "$task_dir/contract.before.new.yaml"
   bash "$scripts/contract-edit.sh" apply "$contract_file" "$task_dir/contract.gate-patch.yaml"
   [ ! -f "$task_dir/contract.before.new.yaml" ] || mv "$task_dir/contract.before.new.yaml" "$task_dir/contract.before.yaml"
   yq -p yaml -o json '[.planned[]?.id]' "$task_dir/contract.before.yaml" | jq -r --argjson remove "$(yq -p yaml -o json '.remove_planned // []' "$task_dir/contract.gate-patch.yaml")" '$remove - ($remove - .) | select(length > 0) | "undo planned: " + join(",")'
   patched_keys='[]'; [ ! -f "$task_dir/contract.gate-patch.yaml" ] || patched_keys="$(yq -p yaml -o json '.sections // {} | keys' "$task_dir/contract.gate-patch.yaml")"
   still_stale="$(jq -rn --argjson stale "${stale_sections:-[]}" --argjson patched "$patched_keys" '$stale - $patched | .[]')"
   if [ -z "$still_stale" ]; then bash "$scripts/contract-edit.sh" set-verified "$contract_file" "$checked_commit"; else printf 'still stale:\n%s\n' "$still_stale"; fi
   ```

   The snapshot `contract.before.yaml` is promoted only after `apply` succeeds, so a refused `apply` leaves no snapshot. It is written once, so a second run keeps the text from before the gate. `apply` prints the applied section keys. The line after `apply` prints `undo planned: <ids>`: each id in the patch's `remove_planned` list that the snapshot holds. It reads the snapshot, not the output of `apply`, so a second run prints the same ids, although `apply` removes nothing then.
   If each key in `stale_sections` is a key under `sections:` in the patch, `set-verified` runs. When the check exited 0, `stale_sections` is `[]`, so `set-verified` runs. If a stale section is not in the patch, the call prints `still stale:` and the keys, and `verified_commit` stays. Then tell the user which sections stay stale.
   If `apply` printed a section key or the call printed an `undo planned:` line, write a `step` line in `run-log.md` with the undo. Join its commands with ` && `, in this order. Quote each value as in the block.
   - The undo command: `bash '<scripts>/contract-edit.sh' apply '<contract_file>' '<task folder>/contract.before.yaml' --sections '<applied keys, joined by commas>' --planned '<removed ids, joined by commas>'`. The removed ids are the ids of the `undo planned:` line. If the call printed no `undo planned:` line, leave out the `--planned` flag and its value. If `apply` printed no section key, leave out the `--sections` flag and its value. With `--planned` alone, `apply` restores only those plan items and changes no section.
   - If the call did not print `still stale:`, add the commit command: `bash '<scripts>/contract-edit.sh' set-verified '<contract_file>' '<verified_commit>'`. `<verified_commit>` is the output of `yq '.verified_commit' '<task folder>/contract.before.yaml'`. Without this command, the undo leaves `verified_commit` at `checked_commit`, and the check calls the contract fresh.

   Exit 4 means the lock is busy. Write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the stderr text of `lock` as the reason. Set `status` to `waiting-user` and stop.
   Any other non-zero exit means a command failed after the lock. The trap already ran `unlock`. Write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the stderr text of that command as the reason. If the failed command is `apply`, the validator or the key check refused the patch, and the contract is unchanged. Then the reason is `contract gate: patch refused: <stderr text of apply>`, so "After a stop" runs the gate again from G1 and the reader writes a new patch. Set `status` to `waiting-user` and stop. Do not set `approved_at`.

   Then set `approved_at` to the current UTC time: `date -u +%Y-%m-%dT%H:%M:%SZ`.
10. List the tools the verification plan needs from this set: `web`, `diagram`, `video`, `webp`, `terminal`, `r2`. If the list is not empty, run `bash "$scripts/preflight.sh" plan <needs>`.
    - Exit 0: go on.
    - Exit 1: write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the reason `tools missing: <tools>`, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user`. Print the install lines. Ask the user to install the tools. When the user answers, run the same check again. Repeat until it exits 0.
11. Set `status` to `executing`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/execute.md` and follow it.

## After a stop

When the user answers a Confirmation stop, this rule runs. It runs the same way in the same session and in a resumed task.

- If the reason of the last stop item starts with `contract gate:`, set `status` to `drafting` and run Confirmation again from G1.
- For any other stop, read `approved_at`.
  - If it is empty, set `status` to `drafting` and run "Show the spec" again from step 5.
  - If it is set, run step 10 again.

## Approval scope

When the user approves a spec that lists 'open a pull request' under Deliver targets, that approval covers pushing `wstack/<slug>` and creating that pull request. A merge always asks.
