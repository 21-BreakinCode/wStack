# Confirmation

Goal: one clear spec that the user approves. Done when `spec.md` holds all seven sections and `approved_at` is set.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" <key> <value>`.

## Contract gate

Run this gate before "Write the spec". It keeps the service contract fresh. Its steps are G1 to G6, so they do not clash with the numbered steps below.

G1. If `work_type` is not `code` or `ops`, skip the gate.
G2. Run `bash "$scripts/contract-path.sh" --vault "$vault" "<repository folder>"`. Its output is `$contract_file`.
   - Exit 0: go on.
   - Exit 1: write `Contract: not mapped` as a `step` line in `run-log.md`. Skip the rest of the gate and go on to "Write the spec".
   - Exit 2: write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the stderr text as the reason, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user` and stop.
G3. Read `base_branch`: `source "$scripts/lib/frontmatter.sh"; fm_get "$contract_file" base_branch`. Run `git -C "<repository folder>" fetch origin "<base_branch>"`. If the fetch fails, go on with the local ref `origin/<base_branch>` and say so in the brief.
G4. Resolve the pending items of the contract, as "Pending items" in the `deliver-task` skill says.
G5. Run `bash "$scripts/contract-check.sh" "<repository folder>" "$contract_file"`.
   - Exit 3: the contract file is missing. Ask the user one question: set up the contract first (a `contract` task), or go on without a contract. End the reply. Wait.
   - Exit 2: tell the user the stderr text. Ask the same question. End the reply. Wait.
   - Exit 0 or 1: dispatch the `wstack:contract-reader` agent. Give it the repository folder, the contract path, the Goal text, and the output of the check. Write the reply before the line `=== PATCH ===` to `$task_dir/contract-brief.md`. If the part after that line is not `None`, write it to `$task_dir/contract.gate-patch.md`.
G6. "Write the spec" reads `contract-brief.md` together with the vault notes.

The gate never changes the contract file. Step 9 does that, after approval.

## Write the spec

1. Read the Obsidian notes in `$vault` that bear on the idea. If `contract-brief.md` is in the task folder, read it too. The vault is the ground truth. The idea is the `Rough idea from launch:` line under `## Goal` in `spec.md`, when that line exists. Step 4 replaces that line when it writes the Goal.
2. Find the unclear parts.
   - For a rough idea, ask the user one question at a time. Send one question, then end the reply and wait. Ask until you can fill all seven sections.
   - For a written spec, ask only about the unclear parts, one question at a time. If nothing is unclear, go on.
3. Fix `work_type` in the frontmatter if the answers change it.
4. If `approved_at` is set, set it to empty first: `bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" approved_at ""`. A changed spec needs a new approval. Then write the body of `spec.md` with these seven headings. Each one has content.
   - `## Goal`: what the result must do.
   - `## Scope`: what is in and what is out.
   - `## Verification plan`: for each check, its name, its pass rule, and the evidence it produces.
   - `## Non-undoable steps`: every step that needs the user's approval. Write `None` if there is none.
   - `## Deliver targets`: where the result goes, for example `new Obsidian note` or `open a pull request`.
   - `## Contract changes`: the planned contract changes, or `None`.
   - `## Decisions`: each choice between named options, with the options and the reason, or `None`.

Status stays `drafting` until the page exists.

## Show the spec

5. Copy the body of `spec.md` without its frontmatter into a draft file, under a first heading that names the task. The heading sets the page title.
   `{ printf '# %s spec\n\n' "<task_id>"; awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{f=0;next} !f' "$task_dir/spec.md"; } > "$draft"`, where `$draft` comes from `mktemp "${TMPDIR:-/tmp}/spec-draft.XXXXXX"`.
   If `contract.gate-patch.md` exists, put its text first in the draft, under the heading `# Contract changes from the gate`.
6. Run `bash "$scripts/render-page.sh" "$draft" "$task_dir/spec.html"`.
   - Exit 0: the page fits at 375 px.
   - Exit 1: the page is too wide. Shorten wide tables and long lines in the draft, and run it again. Stop after 3 tries and tell the user the width.
   - Exit 2: print the stderr of the script as it is. It names the cause and the fix. Write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the reason `spec page not rendered: <first stderr line>`, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user` and stop.
7. If `mobile` is `true` in the frontmatter, publish `spec.html` as a Claude artifact. Follow `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/mobile.md` with `$page` set to `$task_dir/spec.html`.
8. Set `status` to `awaiting-approval`. Tell the user the path of `spec.html`, and ask for approval. End the reply. Wait.

If the user asks for changes, go back to step 4, then run steps 5 to 8 again.

## After approval

9. If the check in G5 exited 1, update the contract first. Run these commands in order. If `contract.gate-patch.md` does not exist, or holds no `## ` section other than `## Remove from plan`, skip the `cp` and `apply` lines.

   ```bash
   bash "$scripts/contract-edit.sh" lock "$contract_file"
   [ -f "$task_dir/contract.before.md" ] || cp "$contract_file" "$task_dir/contract.before.md"
   bash "$scripts/contract-edit.sh" apply "$contract_file" "$task_dir/contract.gate-patch.md"
   bash "$scripts/contract-edit.sh" set-verified "$contract_file" "$(git -C "<repository folder>" rev-parse "origin/<base_branch>")"
   bash "$scripts/contract-edit.sh" unlock "$contract_file"
   ```

   If `lock` exits 4, write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the stderr text of `lock` as the reason. Set `status` to `waiting-user` and stop.

   Then set `approved_at` to the current UTC time: `date -u +%Y-%m-%dT%H:%M:%SZ`.
10. List the tools the verification plan needs from this set: `web`, `diagram`, `video`, `webp`, `terminal`, `r2`. If the list is not empty, run `bash "$scripts/preflight.sh" plan <needs>`.
    - Exit 0: go on.
    - Exit 1: write a `stop` line in `run-log.md`. Append a stop item with `"stage":"confirmation"` and the reason `tools missing: <tools>`, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user`. Print the install lines. Ask the user to install the tools. When the user answers, run the same check again. Repeat until it exits 0.
11. Set `status` to `executing`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/execute.md` and follow it.

## After a stop

This rule runs when the user answers a Confirmation stop, in the same session or in a resumed task.

- If `approved_at` is empty, set `status` to `drafting` and run "Show the spec" again from step 5.
- If `approved_at` is set, run step 10 again.

## Approval scope

When the user approves a spec that lists 'open a pull request' under Deliver targets, that approval covers pushing `wstack/<slug>` and creating that pull request. A merge always asks.
