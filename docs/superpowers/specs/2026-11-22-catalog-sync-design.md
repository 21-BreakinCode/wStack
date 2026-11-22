# wStack on the plugins page: design

Date: 2026-11-22. Size: a small change across two repositories.

## Intent

The user wants one page that shows all of their Claude Code plugins, with each version, changelog, and install and update commands. The page is https://21-breakincode.com/{lang}/plugins/. It lists the cc-plugins marketplace today. wStack lives in its own repository and marketplace, so it is missing. The page is for the user. After each wStack release, the page must show the new version without a manual step.

## How the page works today

- `cc-plugins/scripts/cicd.sh GEN` reads `.claude-plugin/marketplace.json`, `content/plugins.content.json`, the zh-TW content file, and each plugin folder (`commands/`, `skills/*/SKILL.md`, `CHANGELOG.md`). It writes `CATALOG.md`, each plugin's `README.md`, and `site/data/plugins.json`.
- `VERIFY` (unit tests and a drift check) runs in the pre-commit hook and in `docs-check.yml`.
- A push to `main` that changes `site/data/plugins.json` runs `rebuild-portfolio.yml`. It waits 300 seconds for the raw GitHub cache, then calls the Cloudflare Pages deploy hook. The portfolio fetches `site/data/plugins.json` from `main` at build time (`portfolio/src/utils/pluginCatalog.ts:12`).

## Approaches

- A. wStack joins the cc-plugins catalog through a snapshot of its files. Chosen. The portfolio does not change, and wStack keeps its repository, tests, and marketplace.
- B. Move wStack into the cc-plugins monorepo. Rejected: wStack loses its own repository setup, and cc-plugins CI carries its tests.
- C. The portfolio reads a second catalog that wStack generates. Rejected: three repositories change, and the generator is copied.

Sync options considered: a scheduled pull in cc-plugins, a push from wStack on release, and a manual command. The user chose the push from wStack, triggered by the release.

## Design

```
wStack main (version bump)
  └─ .github/workflows/sync-catalog.yml
       1. check out wStack, and cc-plugins with secret CC_PLUGINS_TOKEN
       2. cc-plugins/scripts/cicd.sh SYNC <wStack folder>   -> cc-plugins/external/wstack/
       3. cc-plugins/scripts/cicd.sh GEN, then VERIFY
       4. if anything changed: commit "chore: sync wstack <version>", push to cc-plugins main
cc-plugins main (push by the user's token, admin bypass)
  └─ docs-check.yml, deploy-pages.yml, rebuild-portfolio.yml run as for any push
portfolio rebuild -> the page shows wStack <version>
```

cc-plugins:
- `external/wstack/` holds the snapshot, in wStack's own layout: `.claude-plugin/plugin.json`, `CHANGELOG.md`, and `skills/<name>/SKILL.md` for the six skills the user invokes (front matter only). The generator reads it like a local plugin folder.
- `content/plugins.content.json` and the zh-TW file get a `wstack` entry in the `workflow` category. The entry marks wStack as external, with its marketplace name `wstack` and repository `21-BreakinCode/wStack`.
- The generator adds external entries to the model. An external plugin's install command is `claude plugin marketplace add 21-BreakinCode/wStack && claude plugin install wstack@wstack`. Its update command is `claude plugin marketplace update wstack && claude plugin update wstack@wstack`. The install-all and update-all lines include it. The generator writes no README into `external/`.
- `cicd.sh SYNC <folder>` copies the snapshot files from a wStack checkout. The consumer owns the snapshot format.
- Generator tests cover the external entry: its commands, the install-all and update-all lines, and no README.

wStack:
- `.github/workflows/sync-catalog.yml` runs on a push to `main` that changes `.claude-plugin/plugin.json`, `CHANGELOG.md`, or a skill, and on `workflow_dispatch`.
- If `VERIFY` fails in cc-plugins, the workflow does not push, and the run fails where the user sees it.

The token:
- A fine-grained personal access token with access to `21-BreakinCode/cc-plugins` only, and the Contents permission set to read and write. It is stored as the wStack secret `CC_PLUGINS_TOKEN`. The user creates it. When it expires, the user renews it. A push with this token counts as the user, who is an admin. The `main: require pull request` rule lets an admin through (bypass mode `always`). The push also starts the cc-plugins workflows.

## Goals, non-goals, anti-goals

- Goal: about 10 minutes after a wStack release, the page shows the new version, changelog, skills, and commands. Most of that time is the 300-second cache wait.
- Non-goals: moving wStack into cc-plugins, a separate wStack site, a portfolio change, and a list of wStack's helper skills.
- Anti-goal: a wStack release must never leave cc-plugins `main` broken. The workflow runs `VERIFY` before it pushes.

## Left to the builder

- The exact field names for the external marker in the content file, in the generator's style.
- Whether the portfolio's catalog validation (`pluginCatalog.ts:71`) accepts the external entry as is. If it needs a new required field, keep the existing field shape instead.
- The zh-TW wording of the wStack entry.
