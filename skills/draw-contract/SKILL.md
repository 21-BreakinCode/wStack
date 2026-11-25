---
name: draw-contract
description: Draw a diagram of a service contract with the diagram-design skill, from the contract's diagrams block. Use when the user asks to draw, redraw, or visualize a contract, or one of its flows, sequences, state lifecycles, or architecture.
---

# draw-contract

Usage: `/wstack:draw-contract [<service>] [<what to draw>]`.

The user's request to draw is the approval to write that deep dive. A deep dive is one HTML file in `diagrams/` next to the contract.

## Config

Resolve the vault path in this order. Take the first one that is set and is not a literal `${user_config...}` text: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`. Read the shell variables with `echo "${WSTACK_VAULT_PATH:-}" "${EVAL_WSTACK_VAULT_PATH:-}"`. If no vault path is set, ask the user for it and stop. If the vault path is relative, make it absolute with `cd <value> && pwd`. Inside a task, skip all of this vault work, because Deliver passes the contract path.

Set `scripts="${CLAUDE_PLUGIN_ROOT}/scripts"`.

## Inside a task

Four callers run the Draw steps in a task: Deliver, gate step 9 of Confirmation, "Pending items" of deliver-task, and the retro. Each passes the contract path, `--backup-dir`, and `--record`. So skip step 1 and the vault work in Config. In this mode, a problem never stops the task. Ask the user nothing.

- If diagram-design is not installed (step 3), write the `step` line `deep dive <subject> skipped: diagram-design is not installed` in `run-log.md` and return.
- If any other step fails, write the `step` line `deep dive <subject> failed: <reason>` in `run-log.md` and return. A failure is any non-zero exit, or a step that says to ask the user. `<reason>` is the first line of stderr.
- Use `flow` or the subject that the caller names.

In every step below, "stop" means: outside a task, print the stderr text and stop. Inside a task, write the log line above and return.

## Draw steps

1. Run `bash "$scripts/contract-open.sh" --vault "<vault>" --contract [<service>]` from the current folder. If the user gave `<service>`, pass it. It prints the contract YAML path. Exit 1 means no contract matched. Its stderr lists the rendered contracts. Show that list and ask which one to draw. Exit 2: print stderr and stop.
2. Map `<what to draw>` to one subject: `flow`, `sequence:<id>`, `states:<id>`, or `architecture`. If the user named none, the subject is `flow`. Run `bash "$scripts/contract-diagram.sh" subject "<contract>" <subject>`. Exit 0 prints `hash: <hex>` and then the subject JSON. Exit 1 means the contract has no such subject. Its stderr has a `subjects:` line. Show that line and ask which subject to draw. Exit 2 means a bad call: stop.
3. Look in the available skills for `diagram-design:diagram-design`. If it is not there, tell the user to run `/plugin marketplace add cathrynlavery/diagram-design` and `/plugin install diagram-design@diagram-design`, and stop. Inside a task, follow "Inside a task".
4. Run the `diagram-design:diagram-design` skill. Give it the subject JSON and these rules:
   - The diagram type is architecture for `flow`, sequence for `sequence:<id>`, state machine for `states:<id>`, and layers for `architecture`.
   - Use `faithful` density.
   - Draw only what the JSON holds. To get a readable picture, merge, drop, or shorten nodes and labels. Add no node, edge, or label that the JSON does not hold.
   - If diagram-design asks about its style guide, keep the default style.
   - Skip its plan approval step.

   Write the HTML to a new file in `mktemp -d`. Never write a `.diagram-design` marker into a repository.
5. Run `contract-diagram.sh install` as `bash "$scripts/contract-diagram.sh" install "<contract>" <subject> "<drawn file>"`. If the caller gave `--backup-dir <dir>` and `--record <list>`, add them. The script prints `installed: <path>` and maybe `backup: <path>`. Exit 1 means the subject is gone: stop. Exit 2 means the drawn file is bad: stop. Exit 4 means the lock is busy: stop, and outside a task tell the user to try again in a moment.
6. Run `bash "$scripts/contract-render.sh" "<contract>"`. It renders the note and the page again, so the page links the new deep dive. If it exits non-zero, stop. Otherwise print the installed path.
