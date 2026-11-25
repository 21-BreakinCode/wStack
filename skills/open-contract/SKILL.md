---
name: open-contract
description: Open the HTML page of a service contract, or its vault note with --note. Use when the user asks to open, show, or view a service contract. With no service name, it opens the contract of the current repository.
---

# open-contract

Usage: `/wstack:open-contract [<service>] [--note]`.

## Config

Resolve the vault path in this order. Take the first one that is set and is not a literal `${user_config...}` text: the shell variable `WSTACK_VAULT_PATH`, then `EVAL_WSTACK_VAULT_PATH`, then `${user_config.vault_path}`. Read the shell variables with `echo "${WSTACK_VAULT_PATH:-}" "${EVAL_WSTACK_VAULT_PATH:-}"`. If no vault path is set, ask the user for it and stop. If the vault path is relative, make it absolute with `cd <value> && pwd`.

## Steps

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/contract-open.sh" --vault "<vault>" [--note] [<service>]` from the current folder. Pass `<service>` and `--note` only when the user gave them. The script finds the contract, renders the page or the note again when it is missing or older than `<service>.contract.yaml`, and opens it. The HTML page opens in the browser. The note opens in Obsidian.
2. Exit 0: tell the user the path that the script printed.
3. Exit 1: no contract matched. The script printed the rendered contracts on stderr. Show that list to the user and ask which one to open. If the list is empty, tell the user to build a contract with a `contract` task in `/wstack:start-task`.
4. Exit 2: print the stderr text and stop.
