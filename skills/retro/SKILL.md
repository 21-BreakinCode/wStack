---
name: retro
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

## Write the retro

1. Set `$week` to `date -j -f %Y-%m-%d "$today" +%G-W%V`. Set `$retro_dir` to `$vault/$(dirname "$tasks_dir")/Retros`. Run `mkdir -p "$retro_dir"`. The retro file is `$retro_dir/$week.md`.
2. Set `$data` to `mktemp "${TMPDIR:-/tmp}/retro-data.XXXXXX"`. Run `bash "$scripts/collect-week.sh" --vault "$vault" --tasks-dir "$tasks_dir" --today "$today" > "$data"`. If it fails, print its stderr and stop.
3. If `jq length "$data"` is `0`, tell the user that no task folder is in the last 7 days. Stop.
4. Dispatch the agent `wstack:retro-analyst`. In the prompt, give the path `$data` and the count of tasks. Its reply is a list of proposal blocks `P1`, `P2`, and so on, or `No proposals.`
5. Write `$retro_dir/$week.md` with this shape. Paste the analyst reply under `## Proposals` as it is.

```
# Retro <week>

Tasks read: <count>, from the 7 days up to <today>.

## Proposals

<analyst reply>

## Applied

None yet.
```

6. Run `bash "$scripts/render-page.sh" "$retro_dir/$week.md" "$retro_dir/$week.html"`.
   - Exit 0 or 1: the page exists. Exit 1 means the page is wider than 375 px. Tell the user the width.
   - Exit 2: print the stderr of the script as it is. Keep the `.md` file. Go on.
7. Tell the user the path of the page (or of the `.md` file when the render failed). List each proposal with its number and title. If the reply was `No proposals.`, stop here.
8. Ask which proposals to apply, by number. End the reply. Wait.

## After the user picks

Apply only the proposals the user named. Make the change that each one names in its `Change` line.

A change to wStack itself goes to the wStack source repository. Never edit `${CLAUDE_PLUGIN_ROOT}`, because an update replaces it. The source repository is a git checkout whose `.claude-plugin/plugin.json` has `"name": "wstack"`. If the current directory is not that checkout, ask the user for its path, end the reply, and wait.

In the source repository, run `git switch -c wstack/retro-$week` once, then commit each change there. Never push.

After each applied proposal, add a line under `## Applied` in `$retro_dir/$week.md`: the proposal number, the title, and the commit SHA when there is one. Replace `None yet.` on the first line. Render the page again as in step 6.

Tell the user which proposals you applied and which you skipped.
