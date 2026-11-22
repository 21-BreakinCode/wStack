---
name: run-retro
description: Review the past week of wStack tasks, propose improvements, and apply the ones the user picks.
disable-model-invocation: true
---

# retro

## Config

Resolve each value in this order. Take the first one that is set and is not a literal `${user_config...}` text.

- Vault path: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`.
- Tasks folder: `WSTACK_TASKS_DIR`, then `EVAL_WSTACK_TASKS_DIR`, then `${user_config.tasks_dir}`, then `Workflow/Tasks`.
- Today: `WSTACK_TODAY`, then `EVAL_WSTACK_TODAY`, then the output of `date +%Y-%m-%d`.

Read the shell variables with `echo "${WSTACK_VAULT_PATH:-}" "${EVAL_WSTACK_VAULT_PATH:-}"`. Read the other shell variables the same way. If no vault path is set, ask the user for it and stop.

If the vault path is relative, make it absolute with `cd <value> && pwd`.

In this file `$vault` is the vault path, `$tasks_dir` is the tasks folder, `$today` is today, and `$scripts` is `${CLAUDE_PLUGIN_ROOT}/scripts`.

## Collect the week

1. Set `$week` to `date -j -f %Y-%m-%d "$today" +%G-W%V`. Set `$retro_dir` to `$vault/$(dirname "$tasks_dir")/Retros`. Run `mkdir -p "$retro_dir"`. Set `$retro_name` to `$week`. If `$retro_dir/$retro_name.md` exists, write `$week-2` instead, then `$week-3`, and so on, until the file does not exist. A second retro in the same week must never replace the first.
2. Set `$data` to `mktemp "${TMPDIR:-/tmp}/retro-data.XXXXXX"`. Run `bash "$scripts/collect-week.sh" --vault "$vault" --tasks-dir "$tasks_dir" --today "$today" > "$data"`. If it fails, print its stderr and stop.
3. If `jq length "$data"` is `0`, tell the user that no task folder is in the last 7 days. Skip step 4. In step 5, write `Tasks read: 0` and use `No proposals.` as the analyst reply. Set `$proposals` to `No proposals.` The retro goes on, because the contract drift part needs no task folder.
4. Dispatch the agent `wstack:retro-analyst`. In the prompt, give the path `$data` and the count of tasks. Its reply is a list of proposal blocks `P1`, `P2`, and so on, or `No proposals.` It can end with a `## Questions` block. Keep the proposal blocks as `$proposals`. Keep the `## Questions` block as `$questions`. Then run "Ask the RDs" below. If the reply has no `## Questions` block, it does nothing.

## Ask the RDs

This part never stops the retro. It runs after step 4 and before step 5. If `$questions` has no `### Q<n> <task id>` entry, go on to step 5 with no answers. Otherwise do the rest.

Set `$answers` to `mktemp "${TMPDIR:-/tmp}/retro-answers.XXXXXX"`. Each `### Q<n> <task id>` entry can hold several `- Question:` lines. For each task id in `$questions`, do R1 to R5 once, with all the entries of that task in one prompt.

R1. Read `session_ids` and `workspace_cwd` from `spec.md` in the `folder` of that task in `$data`. Take the last id in `session_ids`. Run `source "$scripts/lib/transcripts.sh"; session_id_ok "<id>"; transcript_main_files "<id>"`. If the id is not valid or no transcript is found, the answer is `not reachable: no transcript`. Go on to the next task.
R2. Set `$fork_dir` to `workspace_cwd`. If `workspace_cwd` is empty, use the current folder. If `$fork_dir` does not exist, run `mkdir -p "$fork_dir"` and note that this step created it. The spike showed that a resume works from a folder that was created again empty.
R3. Set `$prompt_file` to `mktemp "${TMPDIR:-/tmp}/retro-prompt.XXXXXX"`. Write the prompt into it with the Write tool. Never put the prompt on a command line, because it can hold words that the guard hook stops on. The prompt holds the `### Q<n> <task id>` entries of that task and these rules. Answer under each Q id. Answer from what you remember and from the files. Change nothing. If you do not know, say "I do not know".
R4. Run the fork with a timeout of 10 minutes. The prompt comes first, because `--tools` takes many values and a prompt after it becomes a tool name. `--strict-mcp-config` keeps MCP tools out of the fork. `--no-session-persistence` leaves no transcript of the fork. The fork leaves the original session as it was. The stdout of the fork is the answer.

   ```bash
   cd "$fork_dir" && env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
     claude -p "$(cat "$prompt_file")" --resume <id> --fork-session --tools Read,Grep,Glob --strict-mcp-config --no-session-persistence </dev/null
   ```

   If the call fails, the answer is the first line of its stderr, and it is an error line. Go on.
R5. If R2 created `$fork_dir`, run `rmdir "$fork_dir"`. Remove the prompt file. Go on to the next task.

Write one entry per `### Q<n> <task id>` to `$answers`, in the shape of `## RD answers` in step 5. If at least one fork reply exists (an error line does not count), dispatch `wstack:retro-analyst` a second time. Give it the path `$data`, the path `$answers`, and the proposals of the first run. It revises the proposals with the answers, and it asks no new question. Its reply replaces `$proposals`.

## Save the retro file

5. Write `$retro_dir/$retro_name.md` with this shape. Paste `$proposals` under `## Proposals` as it is. If `$answers` has entries, paste them under `## RD answers`. With no entry, leave out `## RD answers`. Each entry has this shape. Quote the whole reply with `>` on every line, so that a `##` heading in a reply cannot split the file.

```
### Q<n> <task id>
- Question: <the question text>
- Answer:
  > <the reply, or the error line>
```

```
# Retro <week>

Tasks read: <count>, from the 7 days up to <today>.

## Proposals

<proposals>

## RD answers

<answers, only when there are any>

## Applied

None yet.
```

6. Run `bash "$scripts/render-page.sh" "$retro_dir/$retro_name.md" "$retro_dir/$retro_name.html"`.
   - Exit 0 or 1: the page exists. Exit 1 means the page is wider than 375 px. Tell the user the width.
   - Exit 2: print the stderr of the script as it is. Keep the `.md` file. Go on.
7. Tell the user the path of the page (or of the `.md` file when the render failed). List each proposal with its number and title. Then run "Contract drift" below. With `No proposals.` and no stale section that has a patch block, stop here.
8. Ask which proposals to apply, by number. If at least one stale section has a patch block, also ask which contract sections to update: names, `all`, or `none`. Put both in one question. A reply with no section part means `none`. With `No proposals.`, ask only for the contract sections. End the reply. Wait.

## Contract drift

This part runs after step 7 and before step 8. It never stops the retro. Every outcome has a status line that starts with `Contract:`. A step below can say "skip". Then add the section `## Contract` with that status line to `$retro_dir/$retro_name.md`. Render the page again as in step 6. Go on to step 8 with no contract sections.

D1. Run `git rev-parse --show-toplevel`. It is `$repo`. If it fails, say `Contract: not a git project` and skip.
D2. Run `contract_file="$(bash "$scripts/contract-path.sh" --vault "$vault" "$repo")"`.
   - Exit 1: say `Contract: not mapped` and skip.
   - Exit 2: say `Contract: path check failed: <first stderr line>` and skip.
   - Exit 0 and the file `$contract_file` does not exist: say `Contract: missing`, point to `/wstack:init-service`, and skip.
D3. Set `base_branch` with `source "$scripts/lib/frontmatter.sh"; fm_get "$contract_file" base_branch`. If `base_branch` is empty, say so and go on to the pending items below. Otherwise run `git -C "$repo" fetch origin "$base_branch"`. If it fails, tell the user and go on with the local ref `origin/$base_branch`. The current branch is the output of `git -C "$repo" branch --show-current`. A detached HEAD prints nothing, so no fast-forward runs. If the current branch is `$base_branch` and `git -C "$repo" status --porcelain` prints nothing, also run `git -C "$repo" merge --ff-only "origin/$base_branch"`. If that fails, tell the user and go on. In every other case, say that only a fetch ran. The retro never merges, rebases, or stashes the work of the user.
   Then resolve the pending items of the contract before D4, as the gate's G4 does. A merged write-back then lands in the contract before D6 moves `verified_commit`. Read "Pending items" in `${CLAUDE_PLUGIN_ROOT}/skills/deliver-task/SKILL.md` and follow it. Run `gh` in `$repo`. A file read by path keeps its plugin root variable, so in its blocks set `scripts` to the `$scripts` of this skill. The retro has no task, so set no status. Keep each line that it puts in `run-log.md`, and add it to the `## Contract` section of the retro file. If it says to stop, say `Contract: pending items failed: <stderr text>` and skip.
D4. Run `bash "$scripts/contract-check.sh" "$repo" "$contract_file"`.
   - Exit 0: say `Contract: fresh` and skip.
   - Exit 2 or 3: say `Contract: check failed: <cause>` and skip.
   - Exit 1: go on.
D5. If the `stale_sections:` line of the check is `[]`, the check is stale only by dependencies or unclaimed files. Say `Contract: stale (dependencies or unclaimed files), no section to update` and skip. Otherwise run `git -C "$repo" rev-parse "origin/$base_branch"`. It is `$checked_commit`. Dispatch the agent `wstack:contract-reader`. Give it `$repo`, `$contract_file`, the output of the check, and the goal `refresh the stale sections`. The reply is a brief, then the line `=== PATCH ===`, then the patch. If the part after the marker is `None`, say `Contract: stale, no patch` and skip. Otherwise write it to `$retro_dir/$retro_name.contract-patch.md`. List each stale section (the `stale_sections:` line of the check) with a one-line summary of the change that the patch proposes. A stale section with no block in the patch is listed as `no patch`.
D6. After the answer to step 8, read the chosen sections. If the user chose none, write `Contract: stale, not updated` in the `## Contract` section of the retro file and skip. Otherwise update the contract in one Bash call. Write the real value for each `<...>` in single quotes, and write each `'` in a value as `'\''`. `<chosen section names, one per line>` holds each chosen name on its own line (`all` means every stale section that has a `## <name>` block in the patch). Drop any chosen name that has no such block. If no name is left, write `Contract: stale, no patch for the chosen sections` and skip.

   ```bash
   set -e
   scripts='<scripts folder>'
   retro_dir='<retro folder>'
   retro_name='<retro name>'
   contract_file='<contract file>'
   checked_commit='<checked commit>'
   stale_sections='<stale_sections JSON>'
   chosen_sections='<chosen section names, one per line>'
   patch="$retro_dir/$retro_name.contract-patch.md"
   section_args=()
   while IFS= read -r name; do section_args+=(--section "$name"); done <<<"$chosen_sections"
   bash "$scripts/contract-edit.sh" lock "$contract_file"
   trap 'bash "$scripts/contract-edit.sh" unlock "$contract_file"' EXIT
   [ -f "$retro_dir/$retro_name.contract-before.md" ] || cp "$contract_file" "$retro_dir/$retro_name.contract-before.md"
   bash "$scripts/contract-edit.sh" apply "$contract_file" "$patch" "${section_args[@]}"
   still_stale="$(jq -r '.[]' <<<"${stale_sections:-[]}" | CHOSEN="$chosen_sections" awk -v patch="$patch" 'BEGIN { n = split(ENVIRON["CHOSEN"], names, "\n"); for (i = 1; i <= n; i++) chosen[names[i]] = 1; while ((getline line < patch) > 0) if (line ~ /^## / && (substr(line, 4) in chosen)) applied[substr(line, 4)] = 1 } !($0 in applied)')"
   if [ -z "$still_stale" ]; then bash "$scripts/contract-edit.sh" set-verified "$contract_file" "$checked_commit"; else printf 'still stale:\n%s\n' "$still_stale"; fi
   ```

   If every stale section was applied, run `set-verified` (the block does it). When the block prints `still stale:` and names, `verified_commit` stays, because the contract still drifts. Tell the user which sections stay stale. `apply` prints the applied names, and a warning on stderr for each section it adds as new.
   Exit 4 means the lock is busy. Tell the user, write `Contract: not updated, the lock is busy` in the `## Contract` section, and go on. Any other non-zero exit means a command failed after the lock. The trap already ran `unlock`. Print the stderr text, write `Contract: update failed` in the `## Contract` section, and go on.
D7. After `apply` ran, add the `## Contract` section to `$retro_dir/$retro_name.md`. Every other outcome added it with one status line already. It holds the status (`updated` or `still stale`), the applied section names, the still stale names, and the undo. Build the undo as step 9 of `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` does, with `$retro_dir/$retro_name.contract-before.md` as the before copy. First comes the old-section command. Then comes the new-section command for each applied section that has no `## <name>` line in the before copy. Last, after a run of `set-verified`, comes the commit command. Render the page again as in step 6.

## After the user picks

Apply only the proposals the user named. Make the change that each one names in its `Change` line.

A change to wStack itself goes to the wStack source repository. Never edit `${CLAUDE_PLUGIN_ROOT}`, because an update replaces it. The source repository is a git checkout whose `.claude-plugin/plugin.json` has `"name": "wstack"`. If the current directory is not that checkout, ask the user for its path, end the reply, and wait.

In the source repository, run `git status --porcelain` first. If it prints anything, the checkout has uncommitted changes. Tell the user and stop. Then run `git switch -c wstack/retro-$week`. If the branch exists, run `git switch wstack/retro-$week` instead. Commit each change there. Never push.

After each applied proposal, add a line under `## Applied` in `$retro_dir/$retro_name.md`: the proposal number, the title, and the commit SHA when there is one. Replace `None yet.` on the first line. Render the page again as in step 6.

Tell the user which proposals you applied and which you skipped.
