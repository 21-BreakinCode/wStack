# wStack on the Plugins Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** List wStack on https://21-breakincode.com/{lang}/plugins/ with its version, changelog, skills, and install and update commands, refreshed by a wStack workflow after each release.

**Architecture:** cc-plugins keeps a snapshot of wStack's files in `external/wstack/`. Its generator treats an entry with an `external` block like a local plugin that has its own marketplace. A wStack workflow runs `cicd.sh SYNC`, `GEN`, and `VERIFY` in a cc-plugins checkout, then pushes to cc-plugins `main` with the user's token. The portfolio does not change.

**Tech Stack:** Node 20 (`node:test`), bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-22-catalog-sync-design.md`

## Global Constraints

- cc-plugins: `CATALOG.md`, `*/README.md`, and `site/data/plugins.json` are generated. Never edit them by hand. Run `./scripts/cicd.sh GEN`, then `./scripts/cicd.sh VERIFY` (exit 0) before each commit.
- cc-plugins: `site/data/plugins.json` is a public contract. Add entries, but keep every existing field name and shape.
- cc-plugins: every plugin with an English `tagline` or `summary` needs a zh-TW entry with `text` and `translatedFrom`, or `VERIFY` fails.
- wStack: run `bash tests/run-all.sh` before each commit. Scripts start with `#!/usr/bin/env bash` and `set -euo pipefail` and run on `/bin/bash` 3.2.
- The external marker is `"external": { "marketplace": "wstack", "repo": "21-BreakinCode/wStack", "source": "external/wstack" }`.
- wStack install command: `claude plugin marketplace add 21-BreakinCode/wStack && claude plugin install wstack@wstack`.
- wStack update lines: `claude plugin marketplace update wstack` and `claude plugin update wstack@wstack`.
- The token is the wStack secret `CC_PLUGINS_TOKEN`: a fine-grained personal access token for `21-BreakinCode/cc-plugins` only, with Contents read and write.
- Ask the user before each push, pull request, merge, and workflow run that pushes. Merge pull requests only with `gh pr merge <n> --merge`.
- Markdown passes the simple-english lint.

## Review Focus

1. A wStack release removes or renames a skill. The page drops the old skill, because `SYNC` clears `external/wstack/` first. Test: Task 3, `sync removes files the plugin no longer has`.
2. A new wStack CHANGELOG entry uses plain bullets. Then the page shows the version with no changes. Test: Task 1, `tests/test_changelog_format.sh`.
3. Two wStack pushes land close together. Two runs race to push cc-plugins `main`, and one is rejected. Test: Task 1, the workflow pin for `concurrency`.
4. `VERIFY` fails after a sync. Nothing is pushed, and the run fails where the user sees it. Test: Task 1, the workflow pin that `VERIFY` comes before `git push`.
5. The generator writes a README into `external/wstack/`, which then gets committed. Test: Task 3, `test ! -e external/wstack/README.md` after `GEN`.

---

### Task 1: wStack changelog format and the sync workflow (wStack repository)

**Files:**
- Modify: `CHANGELOG.md`
- Create: `.github/workflows/sync-catalog.yml`
- Create: `tests/test_changelog_format.sh`, `tests/test_sync_workflow.sh`

**Interfaces:**
- Produces: a CHANGELOG where every bullet under a `## <version> - <YYYY-MM-DD>` heading reads `- **<type>:** <text>`, with type in `feat`, `fix`, `docs`, `change`, `breaking`. The site parser (`cc-plugins/scripts/lib/site-data.mjs` `parseChangelog`) reads only these bullets.
- Consumes (from Task 3, at run time): `cc-plugins/scripts/cicd.sh SYNC <folder>`.

- [ ] **Step 1: Write the failing tests**

`tests/test_changelog_format.sh`: for each line of `CHANGELOG.md` that starts with `- ` after the first `## ` heading, assert it matches `^- \*\*(feat|fix|docs|change|breaking):\*\* `. Assert each `## ` heading matches `^## [0-9]+\.[0-9]+\.[0-9]+ - [0-9]{4}-[0-9]{2}-[0-9]{2}$`. Print `PASS`/`FAIL` lines like the other tests, and exit 1 on any FAIL.

`tests/test_sync_workflow.sh` reads `.github/workflows/sync-catalog.yml` and asserts:
- it names `CC_PLUGINS_TOKEN`, `repository: 21-BreakinCode/cc-plugins`, `cicd.sh SYNC`, `cicd.sh GEN`, and `cicd.sh VERIFY`
- the line with `cicd.sh VERIFY` comes before the line with `git push`
- it has a `concurrency:` block and `workflow_dispatch:`
- its push trigger is limited to `main` and paths `.claude-plugin/plugin.json`, `CHANGELOG.md`, and `skills/**`

- [ ] **Step 2: Run them and make sure that they fail**

Run: `bash tests/test_changelog_format.sh; bash tests/test_sync_workflow.sh`
Expected: FAIL lines for the plain bullets, and FAIL for the missing workflow.

- [ ] **Step 3: Convert `CHANGELOG.md`**

Rewrite each plain bullet as `- **<type>:** <text>`, and turn a version with only a prose line (0.1.1) into one bullet. Keep each version's heading and its meaning. Prose lead lines can stay, but the site shows only bullets. If a 0.3.1 entry exists when this task runs, convert it too.

- [ ] **Step 4: Write `.github/workflows/sync-catalog.yml`**

Triggers: `push` on `main` with the three paths, and `workflow_dispatch`. `concurrency: { group: catalog-sync, cancel-in-progress: false }`. One job on `ubuntu-latest`:
1. `actions/checkout@v4` with `path: wstack`.
2. `actions/checkout@v4` with `repository: 21-BreakinCode/cc-plugins`, `token: ${{ secrets.CC_PLUGINS_TOKEN }}`, `path: cc-plugins`.
3. `actions/setup-node@v4` with `node-version: "20"`.
4. In `cc-plugins`: `./scripts/cicd.sh SYNC "$GITHUB_WORKSPACE/wstack"`, then `./scripts/cicd.sh GEN`, then `./scripts/cicd.sh VERIFY`.
5. In `cc-plugins`: set the commit identity `wStack catalog sync` with a noreply email. Run `git add -A external content CATALOG.md site`. If `git diff --cached --quiet` fails, commit `chore: sync wstack <version>` and run `git push origin HEAD:main`. The version comes from `wstack/.claude-plugin/plugin.json`.

- [ ] **Step 5: Run the tests and make sure that they pass, then commit**

Run: `bash tests/test_changelog_format.sh; bash tests/test_sync_workflow.sh; bash tests/run-all.sh`
Expected: no FAIL lines, and `run-all.sh` exits 0.

```bash
git add CHANGELOG.md .github/workflows/sync-catalog.yml tests/test_changelog_format.sh tests/test_sync_workflow.sh
git commit -m "feat: sync wStack to the cc-plugins catalog on each release"
```

---

### Task 2: External plugins in the generator (cc-plugins repository)

**Files:**
- Modify: `scripts/lib/collect.mjs` (`buildModel`), `scripts/lib/install.mjs`, `scripts/generate-docs.mjs` (`makeReadPlugin`, `buildOutputs`)
- Test: `scripts/generate-docs.test.mjs`

**Interfaces:**
- Consumes: a content entry with the `external` marker from Global Constraints.
- Produces: `readPlugin(name, source)` returns `{ commands, skills, changelog, manifest }`, where `manifest` is the parsed `<source>/.claude-plugin/plugin.json` or `null`. Each model plugin gets `external` (the marker object, or `null`). An external plugin takes `version` and `oneLiner` from `manifest.version` and `manifest.description`, and `install` from `installExternal(name, marketplace, repo)` in `install.mjs`.

- [ ] **Step 1: Write the failing tests** in `scripts/generate-docs.test.mjs`, with a content entry `beta` that has `external: { marketplace: 'beta-mkt', repo: 'Org/beta', source: './ext/beta' }` and a `readPlugin` stub that returns `manifest: { name: 'beta', version: '2.0.0', description: 'Beta one-liner' }` for it:
  - `external plugin takes version and one-liner from its manifest`: `beta.version === '2.0.0'`, `beta.oneLiner === 'Beta one-liner'`.
  - `external plugin install adds its own marketplace`: `beta.install === 'claude plugin marketplace add Org/beta && claude plugin install beta@beta-mkt'`.
  - `install-all and update-all include the external marketplace`: `model.installAll.cli` contains `claude plugin marketplace add Org/beta` and `claude plugin install beta@beta-mkt`. `model.installAll.update` contains `claude plugin marketplace update beta-mkt` and `claude plugin update beta@beta-mkt`.
  - `settings snippet knows the external marketplace`: `extraKnownMarketplaces['beta-mkt'].source.repo === 'Org/beta'` and `enabledPlugins['beta@beta-mkt'] === true`.
  - `external plugin without a manifest version throws`: a stub with `manifest: null` makes `buildModel` throw an error that names `beta`.
  - `local plugins keep their marketplace install`: `alpha.install === 'claude plugin install alpha@cc-plugins'`, and `alpha.external === null`.

- [ ] **Step 2: Run them and make sure that they fail**

Run: `./scripts/cicd.sh TEST`
Expected: the six new tests fail. The other tests pass.

- [ ] **Step 3: Implement**

`buildModel` builds the marketplace plugins as now, then appends one plugin for each content entry with `external`, ordered by name. `cliOneLiner`, `updateAllCli`, and `settingsSnippet` add the external marketplace lines and keys for each external plugin. `makeReadPlugin` also returns `manifest`. `buildOutputs` writes no README for an external plugin.

- [ ] **Step 4: Run the tests and make sure that they pass, then commit**

Run: `./scripts/cicd.sh VERIFY`
Expected: all tests pass, and the generated files are in sync (no external entry exists yet, so the outputs do not change).

```bash
git add scripts
git commit -m "feat: let the catalog list a plugin from another marketplace"
```

---

### Task 3: SYNC, the wStack snapshot, and its content entries (cc-plugins repository)

**Files:**
- Create: `scripts/sync-external.mjs`, `scripts/sync-external.test.mjs`
- Modify: `scripts/cicd.sh` (a `SYNC` command and its HELP line)
- Modify: `content/plugins.content.json`, `content/plugins.content.zh-TW.json`
- Create (by `SYNC`): `external/wstack/`
- Regenerate: `CATALOG.md`, `site/data/plugins.json`

**Interfaces:**
- Consumes: Task 2's external support, and Task 1's converted CHANGELOG (sync from the wStack branch that holds it).
- Produces: `export function syncExternal(pluginFolder, repoRoot)` in `scripts/sync-external.mjs`, which returns the plugin's version. The CLI form is `node scripts/sync-external.mjs <plugin folder>`, wrapped as `./scripts/cicd.sh SYNC <plugin folder>`. It reads the name from `<plugin folder>/.claude-plugin/plugin.json` and empties `external/<name>/`. Then it copies `.claude-plugin/plugin.json` and `CHANGELOG.md`. For each `skills/<dir>/SKILL.md` whose front matter does not have `user-invocable: false`, it writes a `skills/<dir>/SKILL.md` that holds only the front matter. A missing `plugin.json` exits 2 with a message that names the path.

- [ ] **Step 1: Write the failing tests** in `scripts/sync-external.test.mjs`. Use a temp repo root and a temp plugin folder. The plugin folder holds plugin.json `{ "name": "demo", "version": "1.2.3" }`, a CHANGELOG, a user skill `go`, and a helper skill `help` with `user-invocable: false`.
  - `sync copies the manifest, the changelog, and user skills only`: `external/demo/.claude-plugin/plugin.json`, `external/demo/CHANGELOG.md`, and `external/demo/skills/go/SKILL.md` exist. `external/demo/skills/help` does not exist. The returned version is `1.2.3`.
  - `sync keeps only the front matter of a skill`: the copied `SKILL.md` ends with the closing `---` line, and the body text is not in it.
  - `sync removes files the plugin no longer has`: a file placed in `external/demo/skills/old/SKILL.md` before the sync is gone after it.
  - `sync without a manifest fails`: `syncExternal` on a folder with no plugin.json throws.

- [ ] **Step 2: Run them and make sure that they fail**

Run: `./scripts/cicd.sh TEST`
Expected: the four new tests fail.

- [ ] **Step 3: Implement `syncExternal` and the `SYNC` command**

Use `parseFrontmatter` from `scripts/lib/frontmatter.mjs` to decide `user-invocable`.

- [ ] **Step 4: Add the content entries**

In `content/plugins.content.json`, add `wstack` with the `external` marker, `category: "workflow"`, `dependsOn: ["answer-me-with-html@answer-me-with-html"]`, `config: []`, and:
- `tagline`: `A task workflow: confirm the spec, execute, verify with evidence, deliver`
- `summary`: two or three plain sentences on what wStack does. Name these parts:
  - one pipeline per task, in its own herdr session
  - task notes in the Obsidian vault
  - evidence on pull requests
  - the handover commands
  - service contracts with a drift check

In `content/plugins.content.zh-TW.json`, add `wstack.tagline` and `wstack.summary`, each with `text` (Traditional Chinese, Taiwan wording) and `translatedFrom` equal to the English text.

- [ ] **Step 5: Take the first snapshot and regenerate**

Run: `./scripts/cicd.sh SYNC <path of the wStack checkout that holds Task 1>`, then `./scripts/cicd.sh GEN`, then `./scripts/cicd.sh VERIFY`.
Expected: `VERIFY` exits 0. `test ! -e external/wstack/README.md` succeeds. `site/data/plugins.json` has a `wstack` plugin with `install` equal to the wStack install command, a non-empty `changelog` whose versions have changes, and six skills.

- [ ] **Step 6: Commit**

```bash
git add scripts content external CATALOG.md site
git commit -m "feat: list wStack on the plugins page"
```

---

### Task 4: Ship (ask the user before each step)

- [ ] **Step 1:** Push the cc-plugins branch, create its pull request, and merge it with `gh pr merge <n> --merge` (ask before each). Wait for `rebuild-portfolio.yml` to finish, then check that the page lists wStack.
- [ ] **Step 2:** The user creates the token and adds it as the wStack secret `CC_PLUGINS_TOKEN`. Only the user can do this.
- [ ] **Step 3:** Merge the wStack branch into `main` and push (ask first). The push changes `CHANGELOG.md`, so `sync-catalog.yml` runs.
- [ ] **Step 4:** Check the run: `gh run list --workflow sync-catalog.yml --limit 1` shows success. If the snapshot was already current, the run commits nothing, and that is a pass. Otherwise cc-plugins `main` has a `chore: sync wstack <version>` commit.
