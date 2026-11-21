# wStack design: changes on top of spec 1.0

Date: 2026-11-18
Status: draft, waits for the user's approval
Base: `docs/spec.md` (version 1.0). This document adds rules and changes rules. If this document and `docs/spec.md` disagree, this document wins. Everything that this document does not mention stays as `docs/spec.md` says.

## 1. Intent

wStack runs one fixed pipeline for most of the user's work. Agents do the work, often overnight. The user approves only the spec and the steps that cannot be undone (spec section 1).

The user added these wishes in the design talk:

1. Each task gets its own herdr workspace with the task's name, so that tasks stay apart. The user always works inside herdr.
2. Excalidraw diagrams: in the design docs, in the README, and in the review page.
3. Lighter, current tools: the Playwright CLI instead of the Playwright library, and Cloudflare's `cf` CLI instead of wrangler.
4. wStack never installs system tools. It finds missing tools early and tells the user the install command.

## 2. Goals, non-goals, anti-goals

Goals:

- Everything in spec section 1.1.
- The herdr launcher (section 5.1), the guard hook (section 5.2), the preflight checks (section 5.3), and Excalidraw diagrams (section 5.4).

Non-goals:

- Everything in spec section 1.2.
- Automatic install of any system tool.
- Automation of the Cloudflare setup in spec section 18. `cf` can probably do it later, but it is not in version 1.

Anti-goals. The build fails if any of these happen, even when every done check passes:

- An overnight task merges, pushes to the default branch, deletes remote data, or publishes, and nobody saw a prompt.
- An overnight task stops for hours at a permission prompt for a routine command, such as `npm test`.
- A test run writes into the user's real vault at `$HOME/Projects/LifeOS/`.
- A test run creates, closes, or changes workspaces in the user's main herdr session.

## 3. Constraints

- Repository: `21-BreakinCode/wStack` on github.com, private. The local clone is at `/Users/williamhung/Projects/breakincode/wStack`.
- The repository root is the plugin root. It also holds `.claude-plugin/marketplace.json` with the marketplace name `wstack` and one plugin entry with `"source": "./"`. Then `claude plugin marketplace add 21-BreakinCode/wStack` installs it. The plugin keeps the layout of spec section 4, at the repository root instead of in a `wstack/` folder.
- Versions on the user's Mac: Claude Code 2.1.327, gh 2.104.0, herdr 0.9.5. The user switches global Node to 26 LTS with `mise use -g node@26`.
- Git rules come from the user's global rules: commit format `<type>: <description>`, new branch for work, and `gh pr merge --merge` only.
- Pull request approval inside a task session (the user's decision): spec section 11 wins over the user's global rule "creating PR from local needs approval". When the user approves a spec that lists "open a pull request" as a deliver target, that approval covers the push of `wstack/<slug>` and the creation of that one pull request. The start-task skill states this override in writing. A merge always asks.
- While wStack itself is built, the global rule applies: the user approves every pull request creation and every merge in the wStack repository.
- Documents follow the user's simple-english rules.

## 4. Approaches

The user chose each row in the design talk.

| Decision | Options considered | Chosen | Reason |
|---|---|---|---|
| Where a task's session runs in herdr | Launcher: start a new Claude session in the new workspace. Move self: move the current pane into the new workspace. Side workspace: the task runs where it started, and the new workspace holds only helper panes. | Launcher | Each task gets a fresh context, its own Remote Control entry on the phone, and the session that started it is free again. |
| Permission mode for task sessions | bypassPermissions plus a guard hook. bypassPermissions only. Auto mode. | bypassPermissions plus guard hook | Nothing stalls overnight, and code enforces the approval rules of spec section 14, not only skill text. |
| What Excalidraw covers | Design docs and README only. Also the review page. One vault drawing. | Also the review page | The user wants one diagram style everywhere. This replaces diagram-design in spec section 10.4. |
| How the diagram gets into `review.html` | Render to SVG once, at build time. Render in the browser at page open, from a CDN. A link to excalidraw.com. | Build-time SVG | Works offline, inside Claude artifacts, and at 375 px. The link option fails the phone rule in spec section 10.1. |
| Browser automation | Playwright library. Playwright CLI. | Playwright CLI | Lighter, and made for coding agents. |
| R2 tool | wrangler. `cf`. | `cf` | `cf` is Cloudflare's successor to wrangler and has a bulk delete. |
| Node version for `cf` | Global Node 26. Node 26 only for `cf` through mise. Keep wrangler. | Global Node 26 | One Node for every tool. `cf` requires `^22.23.0 || ^24.22.0 || ^26.12.0`. |
| Missing tools | Install them automatically. Check and tell the user. | Check and tell | The user installs system tools. |
| Pull request creation in a task | Spec section 11: no approval. The user's global rule: approval. | Spec section 11 | An overnight code task ends with a pull request ready. Spec approval covers it. |
| Guard strength | Seat belt: catch mistakes by a cooperative agent. Hard boundary: also MCP tools, full `gh api` parsing, and branch protection. | Seat belt | In bypassPermissions mode an agent can edit hook files, so no hook is a full wall. The seat belt stops accidents at a small cost. |

## 5. Changes to the spec

### 5.1 herdr launcher (new; changes spec sections 7.1, 7.6, and 8.1)

`/wstack:start-task` has three modes:

| Call | Mode | Who runs it |
|---|---|---|
| `/wstack:start-task <rough idea>` | launch | the session where the user typed it |
| `/wstack:start-task --task <task_id>` | work | the new task session. The launcher sends this prompt. |
| `/wstack:start-task` with no arguments | resume | any session |

Launch mode, inside herdr (`HERDR_ENV=1`):

```
/wstack:start-task "fix login timeout" [--mobile]
  1. base preflight (5.3) ── missing tool? ─► print install commands, stop
  2. pick the slug, guess the work type and the repository
  3. new-task-folder.sh ─► <vault>/<tasks_dir>/2026-11-18-fix-login-timeout/
  4. code task with a repository?
       yes ─► herdr worktree create --cwd <repo> --branch wstack/<slug>
                --label <slug> --no-focus
       no  ─► herdr workspace create --cwd ~/.wstack/tasks/<task_id>/ --label <slug> --no-focus
  5. write workspace_cwd into spec.md
  6. herdr agent start <slug> --kind claude --pane <root pane>
       -- --remote-control <slug> --name <slug> --permission-mode bypassPermissions
  7. herdr agent prompt <slug> "/wstack:start-task --task <task_id> [--mobile]"
  8. herdr workspace focus <new workspace>
  9. print: task id, workspace label, Remote Control name. The launcher is done.
```

Rules:

- One name everywhere. The slug is the herdr workspace label, the herdr agent name, the `claude --name` value, and the Remote Control name. herdr agent names must match `[a-z][a-z0-9_-]{0,31}`, so a slug starts with a letter and has 32 characters at most. If the agent name or the task folder already exists, the launcher adds `-2`, `-3`, and so on.
- Repository. The launcher uses the git repository of the current directory, or a repository that the idea names. If the task looks like code and neither exists, the launcher asks the user one question. The work session can still change `work_type` during Confirmation.
- Focus. The launcher focuses the new workspace, because the next step, Confirmation, needs the user there. On the phone, the new task appears as its own Remote Control session.
- Outside herdr (`HERDR_ENV` is not `1`), the launcher skips steps 4 to 8 and runs the work mode in the current session. This is the behavior of spec section 7.1.
- Working directory for non-code tasks (my call): `~/.wstack/tasks/<task_id>/`, outside the vault. Then tool output, such as `playwright-cli` snapshots or VHS files, never lands in the synced vault. The session writes notes into the vault with absolute paths.
- New `spec.md` frontmatter field: `workspace_cwd`, the absolute path where the task session runs (the worktree or `~/.wstack/tasks/<task_id>/`).

Resume mode (replaces the ASSUME rule in spec section 7.6):

1. The agent lists the tasks whose status is not `delivered` or `cancelled`, from the `spec.md` frontmatter in the vault.
2. The user picks one.
3. If `herdr agent get <slug>` finds a live agent, the agent focuses that agent's workspace.
4. If not, the agent creates a workspace at `workspace_cwd` and starts `claude --continue` there with the flags of launch step 6. `--continue` picks the newest session in that directory, and each task has its own directory.

Cleanup:

- The task session never deletes its own working directory.
- After delivery, `report.md` gives the user the command that removes the worktree or closes the workspace (`herdr worktree remove ...` or `herdr workspace close ...`).

ASSUME: the herdr server keeps panes alive when the terminal window closes. If that is true, a closed terminal window no longer ends a task, and spec section 7.6 changes. Section 5.7 step 0 tests it.

### 5.2 Guard hook (new; enforces spec section 14)

- The plugin ships `hooks/hooks.json` with a `PreToolUse` hook on `Bash`. The hook runs `scripts/guard.sh`, which reads the tool call as JSON on stdin.
- Strength (the user's decision): a seat belt. The guard catches mistakes by a cooperative agent. It is not a wall against an agent that works around it on purpose, because in bypassPermissions mode an agent can edit hook files.
- The guard returns `permissionDecision: "ask"`, with a reason, for these commands:
  - `gh pr merge`, and `gh api` calls to a pull request merge endpoint (`.../pulls/<n>/merge`)
  - `git push` to the default branch through any refspec (for example `git push origin HEAD:main`), `git push --force`, `git push --delete`
  - `gh pr close --delete-branch`, `gh repo delete`
  - `cf r2 objects` delete commands, and `cf` delete commands for buckets
  - deploy and publish commands that the task's spec lists under "Non-undoable steps". Builder's call: how the guard reads that list, or a fixed starter list.
- Every other command passes through unchanged. The guard does not check MCP tools.
- The guard fires in every session where wStack is enabled, not only in task sessions. My call: it asks and does not block, and the user's own rules already require approval for a merge.
- Risk: the Claude Code docs do not say whether `ask` still prompts in bypassPermissions mode. Section 5.7 step 0 tests it. If `ask` does not prompt, the fallback is this:
  1. The guard returns `deny`, with a reason that tells the agent to stop, set `status: waiting-user`, and ask the user.
  2. After the user approves in the session, the agent runs the same command again with the prefix `WSTACK_APPROVED=1`.
  3. The guard lets a command with that prefix through. The start-task skill says that the agent adds the prefix only after the user's yes in the same session.
- `scripts/guard.test.sh` feeds sample tool calls to the guard and checks each decision. Every test that runs a guarded command uses a fake `gh` and a fake `cf` on `PATH`, so that a guard that fails cannot merge or delete real data.

### 5.3 Preflight checks (new)

- `scripts/preflight.sh` checks tools, prints one line per missing tool with its install command, and exits with status 1 if a required tool is missing. It never installs anything. The install commands live only in this script, and the README points to it.
- Base check, in launch mode before any change: `git`, `gh` 2.99.0 or later, `node`, `jq`, Claude Code 2.1.51 or later, and the answer-me-with-html plugin enabled. A missing `herdr` gives a warning only.
- Plan check, in work mode right after the user approves the spec and before `status: executing`: the tools that the verification plan needs.

| The plan uses | Tools that the plan check needs |
|---|---|
| web page checks | `playwright-cli` |
| video evidence | `ffmpeg` with libx264 and libx265 |
| WebP screenshots | `cwebp`, or `playwright-cli` writing WebP directly |
| terminal evidence | `vhs` |
| R2 upload (`r2_bucket` is set and the repository is not in `local_evidence_only_repos`) | `cf`, a Node version that `cf` accepts, and `cf auth whoami` succeeds |
| any page in the Diagram section | `playwright-cli` (for the Excalidraw render) |

- The plan check runs at spec approval because that is the last moment that the user is surely at the Mac. If a tool is missing, the agent sets `status: waiting-user`, prints the install commands, and runs the check again after the user answers.

### 5.4 Excalidraw diagrams (changes spec sections 3.1, 10.4, and 18)

Review page:

- The worker writes `diagram.excalidraw` into the task folder. The file is JSON text, so it is allowed in the vault.
- `scripts/render-excalidraw.sh <in.excalidraw> <out.svg>` renders it to SVG with `playwright-cli run-code` and `exportToSvg` from `@excalidraw/utils`. Builder's call: whether the library bundle is a vendored file in the plugin or a pinned CDN URL.
- The review page inlines the SVG in the Diagram section with `width: 100%` and `height: auto`. The SVG file is a working file in `/tmp/wstack-evidence/<task_id>/`. Only the `.excalidraw` source stays in the vault, so that the user can edit it on excalidraw.com.
- The diagram types stay as spec section 10.4 says: an architecture delta (before and after) when the structure changed, and a sequence or a flowchart when only the logic changed.
- diagram-design is no longer a prerequisite. Remove it from spec sections 3.1 and 18 step 8, and from spec section 17 item 9.

Repository visuals:

- `docs/diagrams/` holds the `.excalidraw` source and an exported `.svg` for three diagrams: the pipeline (spec section 1), the herdr launcher flow (section 5.1), and the plugin layout (spec section 4 plus the new files).
- The README embeds the three SVGs.

### 5.5 Tools (changes spec sections 3.1, 12, and 17)

| Spec tool | Change |
|---|---|
| Playwright | Replaced by the Playwright CLI, npm package `@playwright/cli` 0.1.24, command `playwright-cli`, installed globally. Each task uses its own browser session: `playwright-cli -s <slug>`. It takes screenshots (`screenshot --filename=x.webp`), records video (`video-start x.webm`, `video-stop`), sets the 375 px width (`resize 375 800`), and runs page code (`eval`, `run-code`). |
| wrangler | Replaced by `cf` 1.0.0-rc.1, npm package `cf`, installed globally under Node 26. `evidence-upload.sh` uses `cf r2 objects put`. `evidence-delete.sh` uses `cf r2 objects bulk-delete`. The builder reads the exact flags from `cf r2 objects --help` and `cf schema r2 objects bulk-delete`. `cf` has its own login: `cf auth login`. |
| asciinema or VHS | VHS, installed with `brew install vhs`. |
| diagram-design | Removed (section 5.4). |
| answer-me-with-html | A plugin dependency: `plugin.json` has `"dependencies": ["answer-me-with-html@answer-me-with-html"]`, and `marketplace.json` has `"allowCrossMarketplaceDependenciesOn": ["answer-me-with-html"]`. The README tells the user to add the marketplace `QingYunA/answer-me-with-html` first, because the docs do not say that Claude Code adds it. |
| Node.js | 26 LTS. |

Other effects:

- Spec section 12.2: the video input changes from `.mov` to `.webm`. The ffmpeg commands stay the same.
- Spec section 12.5: `cf r2 objects bulk-delete` replaces the one-file-at-a-time loop if it takes a key list or a prefix. If it does not, the script loops.
- Spec section 5: "wrangler and gh keep their own credentials" becomes "cf and gh keep their own credentials".
- Spec section 17 item 6: `cf r2 objects bulk-delete` exists. Its flags are not yet verified.
- Spec section 17 item 8: the docs name plugin skills `/plugin-name:skill-name`. Keep `/wstack:start-task`. Test the bare form once in step 0.
- Spec section 17 item 9: answered. Cross-marketplace dependencies work with the allowlist above.

### 5.6 Testing (new)

- No test writes into `$HOME/Projects/LifeOS/`. Tests use a throwaway vault in a temporary directory, built from `tests/fixtures/`.
- No test touches the user's main herdr session. Tests that need herdr use a named session, for example `herdr --session wstack-test`.
- Scripts (`new-task-folder.sh`, `preflight.sh`, `guard.sh`, `compress-media.sh`, `render-excalidraw.sh`, `pr-attach.sh`, `evidence-upload.sh`, `evidence-delete.sh`) get shell test scripts with no extra test framework.
- Agent behavior (done checks for spec steps 3, 4, 5, 6, and 13, and the launcher) runs as `claude plugin eval` cases in `evals/`, or as scripted `claude -p --plugin-dir .` runs where an eval case does not fit. Builder's call.
- Spec step 9 (R2 and Access): the scripts get dry-run tests. The real done check waits until the user finishes the Cloudflare setup in spec section 18, steps 1 to 5.
- Spec step 10 (pull request attachments): the real done check uses a test pull request in the wStack repository. Creating that pull request needs the user's approval.

### 5.7 Build order (changes spec section 16)

| Step | Build | Done check |
|---|---|---|
| 0 | Spikes for every untested fact: the guard `ask` decision in bypassPermissions mode. `playwright-cli` with the cached Chromium, and with a `file://` page or a local HTTP server. `exportToSvg` through `run-code`. `cf r2 objects` flags (help and schema, no account needed). `herdr worktree create`, `herdr agent start --kind claude`, and `herdr agent prompt` in a test session. herdr panes after the terminal window closes. The bare `/start-task` form. Spec section 17 items 1, 2, and 3. | Each result is written in `docs/decisions.md`, with the command and its output. |
| 1 | Spec step 1, plus `marketplace.json` and the dependency fields | `claude plugin validate .` passes. `/wstack:start-task` appears in a `claude --plugin-dir .` session. |
| 2 | Spec step 2 | As spec step 2, in the throwaway vault. |
| 2a | `preflight.sh` | Its test passes with a tool hidden from `PATH`, and the output names that tool and its install command. |
| 2b | Launcher and resume (section 5.1) | In the test herdr session, `/wstack:start-task test idea` creates the task folder, a workspace labeled `test-idea`, and a live claude agent named `test-idea` that received the work prompt. Outside herdr, the same call runs in the current session. Resume focuses a live task and restarts a stopped one. |
| 3 | Spec step 3, plus the plan check | As spec step 3. A plan that needs a missing tool stops at `waiting-user` with the install command. |
| 3a | Guard hook (section 5.2) | `guard.test.sh` passes. In a bypassPermissions session with a fake `gh` on `PATH`, `gh pr merge 1` gives a prompt, or the `deny` fallback from section 5.2. |
| 4 to 6 | Spec steps 4 to 6 | As spec. |
| 7 | Spec step 7 with the Excalidraw Diagram section | As spec step 7, and the Diagram section shows an inline SVG rendered from `diagram.excalidraw`. |
| 8 | Spec step 8 with `playwright-cli` | As spec step 8. The UI check makes a WebM, and ffmpeg makes the H.265 copy. |
| 9 to 13 | Spec steps 9 to 13, with `cf` in step 9 | As spec, with the limits in section 5.6. |
| 14 | README and `docs/diagrams/` (section 5.4) | The README shows the three SVG diagrams and the install steps, and it points to `preflight.sh` for tool installs. |

## 6. Left to the builder

- The exact slug rules beyond section 5.1.
- The test layout and the eval case format.
- The source of the `@excalidraw/utils` bundle.
- The exact `cf` flags.
- How the guard reads the spec's "Non-undoable steps" list.
- How eval runs set the `userConfig` values for the throwaway vault.
- Whether `templates/mobile.css` is needed (spec section 17 item 3).

## 7. Risks

- `cf` is a release candidate. Some less-common API commands can still change. Pin `cf@1.0.0-rc.1`.
- `playwright-cli` is at version 0.1. Pin `@playwright/cli@0.1.24`.
- The guard `ask` decision in bypassPermissions mode is not documented. The `deny` fallback covers it.
- Global Node 26 changes Node for every project on the Mac that does not pin its own version.
