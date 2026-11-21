# Handover Rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the handover commands from obsidian-kit (version 3.0.0), and move the existing handover setup to the wStack commands.

**Architecture:** One pull request in the `cc-plugins` repository deletes the handover code and its docs from obsidian-kit. After the merge and the plugin update, a short migration runs on this Mac. No handover note moves, because the vault layout stays the same.

**Tech Stack:** bash, Python 3, `./scripts/cicd.sh` in `cc-plugins`, gh, `claude plugin`.

**Spec:** `docs/superpowers/specs/2026-11-21-contract-gate-design.md`, section 6.11 and steps 5 and 6 of section 7.

**Depends on:** `docs/superpowers/plans/2026-11-21-renames-and-handover-move.md` is merged, and `wstack` 0.2.0 is installed and enabled on this Mac. If obsidian-kit 3.0.0 lands first, handover stops working.

## Global Constraints

- Work in `/Users/william.hung/Projects/breakincode/cc-plugins` on a new branch, not on `main`.
- Merge only with `gh pr merge <number> --merge`. The `main` ruleset needs one approving review. Use `--admin` only after the user approves it for this pull request.
- Ask the user before each push, pull request, merge, plugin update, and file change outside the repositories.
- Nothing in this plan writes into `$HOME/Projects/LifeOS/`. The migration only reads the vault.
- `common/obsidian_eval.py` stays. `scripts/excalidraw/ea_bridge.py`, `scripts/tags/apply.py`, `scripts/tags/plan.py`, `scripts/notes/migrate.py`, and `scripts/common/vault.py` import it.
- Docs pass the simple-english lint hook.

## Review Focus

1. A user still types an old name, for example `/obsidian-kit:handover-new`. The CHANGELOG and the README name the new wStack command for each old one. Test: Task 1.
2. Another obsidian-kit module still imports a removed name (`resolve_via_handover`, `archive_root`, `HANDOVER_LINK`). Every obsidian-kit Python test and `cicd.sh VERIFY` still pass. Test: Task 1.
3. The `Stop` hook entry for `offer-handover.sh` stays after the file is gone. Claude Code then reports a hook error at every turn end. Test: Task 1.
4. The vault holds a handover note with an inline body tag instead of a frontmatter tag. `/wstack:wrap-up-handovers` still finds it, because discovery uses the Obsidian tag index. Test: Task 3.
5. The `handover` line already exists in a tracked `.gitignore`, as in the wStack repository. `/wstack:init-service` prints `already present` and changes no file. Test: Task 3.

---

### Task 1: obsidian-kit 3.0.0

**Files (in `cc-plugins`):**
- Delete: `obsidian-kit/commands/handover-init-org.md`, `handover-init-service.md`, `handover-new.md`, `handover-wrap-up.md`
- Delete: `obsidian-kit/lib/` (all 5 files), `obsidian-kit/scripts/handover/` (4 files), `obsidian-kit/tests/handover/`, `obsidian-kit/hooks/offer-handover.sh`
- Modify: `obsidian-kit/hooks/hooks.json` (remove the `offer-handover.sh` entry under `Stop`)
- Modify: `obsidian-kit/scripts/common/vault.py` (remove `HANDOVER_LINK`, `DEFAULT_ARCHIVE_ROOT`, `resolve_via_handover`, `archive_root`), `obsidian-kit/scripts/common/test_common.py` (remove their tests)
- Modify: `obsidian-kit/README.md` (remove the handover parts), `obsidian-kit/CHANGELOG.md` (add `## 3.0.0`)
- Modify: `content/plugins.content.json` and `content/plugins.content.zh-TW.json` (the obsidian-kit description no longer names handover)
- Modify: `obsidian-kit/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (version `3.0.0`)
- Regenerate: `CATALOG.md` and `site/data/plugins.json` with `./scripts/cicd.sh GEN`

The CHANGELOG entry holds this table:

| Removed from obsidian-kit | Use in wStack 0.2.0 |
| --- | --- |
| `/obsidian-kit:handover-init-org` | `/wstack:init-org` |
| `/obsidian-kit:handover-init-service` | `/wstack:init-service` |
| `/obsidian-kit:handover-new` | `/wstack:create-handover` |
| `/obsidian-kit:handover-wrap-up` | `/wstack:wrap-up-handovers` |

- [ ] **Step 1: Run the checks before the change, and record the counts**

Run: `./scripts/cicd.sh VERIFY`, then each obsidian-kit test file.
Expected: `0 failed`. Write down the pass counts.

- [ ] **Step 2: Delete and edit the files in the Files list, then regenerate**

Run: `./scripts/cicd.sh GEN`

- [ ] **Step 3: Run the checks after the change**

Run: `./scripts/cicd.sh VERIFY`, then each remaining obsidian-kit test file.
Expected: `0 failed`, and generated files in sync.
Run: `grep -rn -i 'handover' obsidian-kit --exclude=CHANGELOG.md`
Expected: no output.
Run: `jq -r '.hooks.Stop[].hooks[].command' obsidian-kit/hooks/hooks.json`
Expected: no line names `offer-handover.sh`.

- [ ] **Step 4: Commit**

```bash
git add -A obsidian-kit content CATALOG.md site .claude-plugin
git commit -m "feat!: move the handover commands from obsidian-kit to wStack"
```

---

### Task 2: Ship obsidian-kit 3.0.0

- [ ] **Step 1: Ask the user for approval, then push and create the pull request**

The body names the four old commands, their wStack names, and the test counts from Task 1.

- [ ] **Step 2: Ask the user for approval, then merge with `gh pr merge <number> --merge`**

If the ruleset blocks the merge, ask the user before you add `--admin`.

- [ ] **Step 3: Ask the user for approval, then update the installed plugin**

Run: `claude plugin marketplace update 21-breakincode && claude plugin update obsidian-kit@21-breakincode`
Expected: `claude plugin list` shows `obsidian-kit` at `3.0.0` and `wstack` at `0.2.0` or later, both enabled. Tell the user to start a new session, so that the new plugin versions load.

---

### Task 3: Migrate the existing handover setup

Run each step in a new session in `/Users/william.hung/Projects/breakincode/wStack`.

- [ ] **Step 1: Run `/wstack:init-service`**

Expected: it maps `wstack` to `Services/wstack`, keeps the symlink, and prints `Local exclude: handover (already present)`, because the tracked `.gitignore` already holds `handover`. `git status --short` prints nothing.

- [ ] **Step 2: Ask the user for approval, then remove `OBSIDIAN_KIT_VAULT` from `.claude/settings.local.json`**

The file holds only that key today. Ask the user whether to delete the file or to keep it as `{}`.

- [ ] **Step 3: Report the optional cleanup**

Tell the user: no plugin reads `OBSIDIAN_KIT_VAULT` any more. Removing it from `~/.claude/settings.appier-cs.json` is optional, in the repository that owns that file.

- [ ] **Step 4: Make sure that wStack finds every live handover note**

With the Obsidian app open, run:

```bash
PYTHONPATH="<wstack install path>/scripts" python3 -c 'from handover.discover import live_handovers; print("\n".join(sorted(live_handovers())))'
```

Expected: the same list as the live notes from `obsidian search query="tag:#type/handover -tag:#status/archived"`. The vault holds 11 notes under `01Project/*/*/*/handover/` today. Each one that is not archived appears in the list.
