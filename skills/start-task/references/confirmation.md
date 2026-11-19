# Confirmation

Goal: one clear spec that the user approves. Done when `spec.md` holds all five sections and `approved_at` is set.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `bash "$scripts/frontmatter-set.sh" "$task_dir/spec.md" <key> <value>`.

## Write the spec

1. Read the Obsidian notes in `$vault` that bear on the idea. The vault is the ground truth.
2. Find the unclear parts.
   - For a rough idea, ask the user one question at a time. Send one question, then end the reply and wait. Ask until you can fill all five sections.
   - For a written spec, ask only about the unclear parts, one question at a time. If nothing is unclear, go on.
3. Fix `work_type` in the frontmatter if the answers change it.
4. Write the body of `spec.md` with these five headings. Each one has content.
   - `## Goal`: what the result must do.
   - `## Scope`: what is in and what is out.
   - `## Verification plan`: for each check, its name, its pass rule, and the evidence it produces.
   - `## Non-undoable steps`: every step that needs the user's approval. Write `None` if there is none.
   - `## Deliver targets`: where the result goes, for example `new Obsidian note` or `open a pull request`.

Status stays `drafting` until the page exists.

## Show the spec

5. Copy the body of `spec.md` without its frontmatter into a draft file:
   `awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{f=0;next} !f' "$task_dir/spec.md" > "$draft"`, where `$draft` comes from `mktemp "${TMPDIR:-/tmp}/spec-draft.XXXXXX"`.
6. Run `bash "$scripts/render-page.sh" "$draft" "$task_dir/spec.html"`.
   - Exit 0: the page fits at 375 px.
   - Exit 1: the page is too wide. Shorten wide tables and long lines in the draft, and run it again. Stop after 3 tries and tell the user the width.
   - Exit 2: print the stderr of the script as it is. It names the cause and the fix. Set `status` to `waiting-user` and stop.
7. If `mobile` is `true` in the frontmatter, publish `spec.html` as a Claude artifact. Follow `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/mobile.md` with `$page` set to `$task_dir/spec.html`.
8. Set `status` to `awaiting-approval`. Tell the user the path of `spec.html`, and ask for approval. End the reply. Wait.

If the user asks for changes, go back to step 4, then run steps 5 to 8 again.

## After approval

9. Set `approved_at` to the current UTC time: `date -u +%Y-%m-%dT%H:%M:%SZ`.
10. List the tools the verification plan needs from this set: `web`, `diagram`, `video`, `webp`, `terminal`, `r2`. If the list is not empty, run `bash "$scripts/preflight.sh" plan <needs>`.
    - Exit 0: go on.
    - Exit 1: set `status` to `waiting-user`. Print the install lines. Ask the user to install the tools. When the user answers, run the same check again. Repeat until it exits 0.
11. Set `status` to `executing`. The Execute stage is written in a later reference file in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/`. If it is not there, tell the user the stage is not available yet and stop.

## Approval scope

When the user approves a spec that lists 'open a pull request' under Deliver targets, that approval covers pushing `wstack/<slug>` and creating that pull request. A merge always asks.
