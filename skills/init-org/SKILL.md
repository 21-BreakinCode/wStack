---
name: init-org
description: "Scaffold handover_handler__initiation.md for the current ORG in $LifeOS/01Project/$ORG/. One-time per ORG."
allowed-tools: ["Bash", "Read", "Write", "AskUserQuestion"]
disable-model-invocation: true
---

# /wstack:init-org

One-time setup per ORG. Creates `handover_handler__initiation.md` in `$LifeOS/01Project/$ORG/`. Safe to re-run. If already initialized, it does nothing.

## Vault location

Resolve the vault path as the first bullet of "Config" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/SKILL.md` says. If it is not set, ask the user for it and stop. Then run:

```bash
export LIFEOS_ROOT="$vault"
```

## Flow

### Phase 1 — Verify 01Project reachable

```bash
[ -d "$vault/01Project" ] || { echo "01Project not reachable at $vault/01Project" >&2; exit 3; }
```

If it is unreachable, print the message and stop. Tell the user to check iCloud sync.

### Phase 2 — Resolve ORG

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/resolve-org.sh"` from the current working directory.

- **Exit 0 (org printed):** use that org name. Tell the user "Detected org: $ORG".
- **Exit 1 (no match):** list directories under `$vault/01Project/` (excluding `RawHandover/`), then `AskUserQuestion`:
  - `question`: "Which ORG is this initiation for?"
  - `options`: one per existing directory, plus "New ORG (enter name)"
- **Exit 3 (vault unreachable):** stop. Phase 1 already handles this, so treat it as a second guard.

If the user picks "New ORG", follow up with `AskUserQuestion` with a free-form question for the ORG name. Use a single option whose label is "Continue".

### Phase 3 — Check existing initiation.md

```bash
INIT="$vault/01Project/$ORG/handover_handler__initiation.md"
```

- If `$INIT` exists, report "Already initialized at $INIT" and stop.
- Otherwise continue.

### Phase 4 — Confirm with user

`AskUserQuestion`:
- `question`: "Scaffold initiation.md for $ORG?"
- `options`:
  - "Yes, scaffold the template"
  - "No, abort"

### Phase 5 — Write template

If the user said yes:

```bash
mkdir -p "$vault/01Project/$ORG"
sed "s/__ORG__/$ORG/g" "${CLAUDE_PLUGIN_ROOT}/templates/initiation.md" > "$INIT"
```

### Phase 6 — Report

Print:
```
Scaffolded: $INIT

Next steps:
  1. Edit the file in Obsidian. Fill in:
     - github_orgs (frontmatter)
     - One Prompt Clone (bash block)
  2. Run /wstack:init-service from each repo to populate the Service Mapping table.
```

## Non-negotiable rules

- Never overwrite an existing `handover_handler__initiation.md`. Always check first.
- Always use `${CLAUDE_PLUGIN_ROOT}/templates/initiation.md` as the source. Do not inline the template. Keep it editable in one place.
- Always check with the user via `AskUserQuestion` before writing.
