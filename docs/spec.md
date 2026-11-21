# wStack: build specification

Version: 1.0 (2026-11-18)
Status: ready to build
Source: the confirmed decisions in `claude/2027-workflow-review.md` (Life Manager project). If this spec and that log disagree, this spec wins.

> Changes after version 1.0 live in `docs/superpowers/specs/2026-11-18-wstack-design.md`. If that design and this spec disagree, the design wins.

## 0. How to read this spec

- This spec is for the agent that builds wStack. It is also the reference for the user.
- Rules marked **(confirmed)** come from the user. Do not change them without asking the user.
- Rules marked **ASSUME** are defaults that the spec author chose to fill a gap. If you find a better way, you can change an ASSUME rule. Write the change in `docs/decisions.md`.
- Section 17 lists facts that nobody tested. Before you build a part that depends on one of them, test that fact.
- Section 16 gives the build order and the done check for each part.

## 1. Goal

wStack is a Claude Code plugin. It runs one fixed pipeline for most of the user's development and editing work. AI agents do the work. The user starts a task, confirms the spec, and approves the steps that cannot be undone. Agents do the rest, often while the user sleeps.

```
/wstack:start-task ─► Confirmation ─► Execute ─► Verify ─► Deliver
                          ▲              ▲          │
                          │              └─ fail ───┤  (fix, max 3 tries)
                          └──── spec wrong ─────────┘

/wstack:run-retro (weekly) ─► reads last week's task folders ─► proposals to improve wStack
```

### 1.1 In scope (version 1)

- One entry command: `/wstack:start-task` **(confirmed)**.
- The five pipeline steps: Trigger point, Confirmation, Execute, Verify, Deliver **(confirmed)**.
- The task folder in the Obsidian vault **(confirmed)**.
- A reviewer agent and a review page **(confirmed)**.
- Evidence capture, compression, upload to Cloudflare R2, and pull request attachments **(confirmed)**.
- The weekly `/wstack:run-retro` command **(confirmed)**.
- The handover commands `/wstack:init-org`, `/wstack:init-service`, `/wstack:create-handover`, and `/wstack:wrap-up-handovers`, moved from obsidian-kit 2.3.1.

### 1.2 Out of scope (version 1)

- Schedule triggers and event triggers (time of day, new Jira ticket, new email, new file). The user starts every task by hand **(confirmed)**.
- Any task that runs without the user's Mac.

## 2. Terms

| Term | Meaning |
|---|---|
| Task | One unit of work that goes through the pipeline once. One `/wstack:start-task` call starts one task. |
| Work type | The kind of task: code, ops, thinking, blog, or video. Section 9 defines them. |
| Spec | The approved description of a task: what to do, and how the result will be checked. Stored in `spec.md`. |
| Task folder | The folder that holds all text files for one task. Section 6 defines it. |
| Slug | A short kebab-case name for a task, for example `fix-login-timeout`. |
| Undoable step | A step that the agent can reverse fully, before anyone else is affected. Example: open a pull request. |
| Non-undoable step | A step that the agent cannot reverse, or that other people can see before a reverse. Examples: merge, deploy, publish, upload, send a message, delete a file. |
| Worker agent | The Claude Code session that runs the task. |
| Reviewer agent | A separate subagent with a fresh context. It did not write the work. It checks the work in Verify. |
| Evidence | Proof that a check passed or failed: API logs, screenshots, videos, terminal recordings. |
| Review page | The HTML page that shows findings, decisions, evidence, a diagram, and a guided diff. |
| Guided diff | Code changes grouped by purpose. Each group has a one-line reason. |
| Mobile mode | The user asks for mobile access. Pages are then also published as Claude artifacts. |

## 3. Runtime environment (confirmed)

- All agents run as Claude Code sessions in the terminal on the user's Mac.
- The phone connects to a running session through Claude Code Remote Control.
- The Claude desktop app is not needed.
- The Mac must stay awake while a task runs. If the Mac sleeps, the session stops.
- Obsidian must stay open on the Mac, so that Obsidian Sync pulls notes that the user edits on the phone. (Not verified. See section 17.)
- Log in to Claude Code with the Claude subscription, not with an API key. Remote Control does not support API keys.
- Start sessions with `claude remote-control` or `claude --remote-control`. Or set "Enable Remote Control for all sessions" in `/config`. One remote session per Claude Code instance.
- A closed terminal or a long network outage ends the session. The failure path in section 7.6 covers this.

### 3.1 Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Claude Code | must support Remote Control (v2.1.51 or later) | runs all agents |
| gh (GitHub CLI) | v2.99.0 or later | pull requests, `--attach` for evidence |
| Node.js | 20 or later | answer-me-with-html CLI |
| ffmpeg | any recent version with libx265 and libx264 | video compression |
| cwebp or ffmpeg | any recent version | WebP screenshots |
| wrangler | any recent version | upload to and delete from Cloudflare R2 |
| Playwright | any recent version | browser screenshots and videos |
| asciinema or VHS | any recent version | terminal recordings |
| answer-me-with-html plugin | latest | builds review pages |
| diagram-design plugin | latest | draws diagrams in review pages |

## 4. Plugin layout

Plugin facts from the Claude Code plugin reference:

- `name` is the only required manifest field. Use kebab-case. Every component is namespaced under it.
- `displayName` is the name shown in the UI. It can have any casing.
- Put the manifest at `.claude-plugin/plugin.json`. Put every other file at the plugin root.
- Prefer `skills/` over `commands/` for new plugins.
- `${CLAUDE_PLUGIN_ROOT}` is the plugin's install path. Each plugin update changes this path. Do not write state there.

So the plugin `name` is `wstack` and the `displayName` is `wStack`. The commands appear as `/wstack:start-task` and `/wstack:run-retro`.

```
wstack/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── start-task/SKILL.md        user command: /wstack:start-task
│   ├── run-retro/SKILL.md         user command: /wstack:run-retro
│   ├── init-org/SKILL.md          user command: /wstack:init-org
│   ├── init-service/SKILL.md      user command: /wstack:init-service
│   ├── create-handover/SKILL.md   user command: /wstack:create-handover
│   ├── wrap-up-handovers/SKILL.md user command: /wstack:wrap-up-handovers
│   ├── build-review-page/SKILL.md helper: build review.html
│   ├── capture-evidence/SKILL.md  helper: capture, compress, upload evidence
│   └── deliver-task/SKILL.md      helper: deliver rules and approval gate
├── agents/
│   ├── reviewer.md                reviewer agent (fresh context)
│   └── retro-analyst.md           reads task folders for /wstack:run-retro
├── templates/
│   ├── spec.md
│   ├── run-log.md
│   ├── review.md
│   ├── report.md
│   ├── initiation.md              handover initiation file for an org
│   └── mobile.css                 CSS override for the narrow layout
├── scripts/
│   ├── new-task-folder.sh         creates the task folder from templates
│   ├── compress-media.sh          WebP, H.265, JPEG, H.264 conversion
│   ├── evidence-upload.sh         uploads a folder to R2
│   ├── evidence-delete.sh         deletes a task's evidence from R2
│   ├── pr-attach.sh               makes GitHub copies and calls gh --attach
│   ├── lib/repo.sh                main_checkout: finds the main checkout from a worktree
│   └── handover/                  resolvers, exclude and symlink scripts, Python helpers
├── docs/
│   └── decisions.md               changes to ASSUME rules, with reasons
└── README.md
```

## 5. Configuration

Put these values in `userConfig` in `plugin.json`. When the user enables the plugin, Claude Code asks for them.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `vault_path` | directory | none, required | Absolute path of the Obsidian vault. |
| `tasks_dir` | string | `Workflow/Tasks` | Task folder root, relative to `vault_path`. |
| `retry_limit` | number | `3` | Maximum fix-and-verify loops before the task waits for the user. **(confirmed as a placeholder. The user can change it.)** |
| `r2_bucket` | string | none | R2 bucket name for evidence. Empty means local-only evidence. |
| `evidence_domain` | string | none | Custom domain protected by Cloudflare Access, for example `evidence.example.com`. |
| `evidence_retention_days` | number | `30` | Days before the R2 lifecycle rule deletes evidence. **(confirmed)** |
| `local_evidence_only_repos` | string, multiple | empty | Repository names (owner/repo) whose evidence must never leave the Mac. ASSUME: added for company-policy cases (section 15). |
| `pr_media_max_mb` | number | `10` | Size limit for each pull request attachment. |

Mark no value as `sensitive`, because wrangler and gh keep their own credentials.

## 6. Task folder (confirmed)

One folder per task in the Obsidian vault. It holds text only. Media never goes into the vault, because the user's Obsidian Sync plan has a 1 GB limit.

```
<vault_path>/<tasks_dir>/<YYYY-MM-DD>-<slug>/
  spec.md       Confirmation: the approved spec and how the work will be checked
  run-log.md    Execute: steps taken, retries, where it stopped and why, tokens used
  review.md     Verify: check results, evidence list with pass/fail, reviewer findings
  review.html   Verify: the review page
  report.md     Deliver: what shipped, where, and how to undo it
```

Each agent reads the files from the steps before it. `/wstack:run-retro` reads every folder from the past week.

### 6.1 File frontmatter

ASSUME: every file starts with YAML frontmatter, so that `/wstack:run-retro` can read fields without parsing prose.

`spec.md`:

```yaml
---
task_id: 2026-11-18-fix-login-timeout
work_type: code            # code | ops | thinking | blog | video
repo: owner/repo           # code and ops tasks only
mobile: false              # true when the user asked for mobile mode
status: awaiting-approval  # see 6.2
approved_at:               # ISO 8601 time, set when the user approves
created_at: 2026-11-18T22:10:00+08:00
---
```

`run-log.md`:

```yaml
---
task_id: 2026-11-18-fix-login-timeout
started_at:
ended_at:
retries: 0
stopped_for_user: []       # stop items, shape in skills/start-task/SKILL.md
tokens_used:               # see section 17, item 1
---
```

`review.md`:

```yaml
---
task_id: 2026-11-18-fix-login-timeout
result: pass               # pass | fail | waiting
blocking_findings: 0
non_blocking_findings: 0
evidence_location: r2      # r2 | local
---
```

`report.md`:

```yaml
---
task_id: 2026-11-18-fix-login-timeout
delivered_at:
targets: []                # list of {target, url, undo}
approval_needed: false
approved_at:
---
```

### 6.2 Task status values

ASSUME: `spec.md` holds the current status. The worker agent updates it at each step.

| Status | Meaning |
|---|---|
| `drafting` | Confirmation: the spec is being written. |
| `awaiting-approval` | Confirmation: the spec waits for the user's approval. |
| `executing` | Execute: the agent works. |
| `waiting-user` | The agent stopped and waits for the user: a non-undoable step during Execute, the retry limit, or a wrong spec. |
| `verifying` | Verify: checks, evidence, and review run. |
| `awaiting-deliver-approval` | Deliver: a non-undoable target waits for the user's approval. |
| `delivered` | All targets are done. |
| `cancelled` | The user stopped the task. |

## 7. Pipeline

### 7.1 Trigger point (confirmed)

- The user types `/wstack:start-task <rough idea>` in the terminal or in the Claude app through Remote Control.
- The worker agent works out the work type (section 9) and the steps. The user does not choose a type.
- Mobile mode: if the user asks for mobile, the task runs in mobile mode. ASSUME: the user writes `--mobile` anywhere in the arguments, or uses the word "mobile" in the request. The agent sets `mobile: true` in `spec.md`.
- The agent creates the task folder with `scripts/new-task-folder.sh`.
- Repeating jobs ("fixed workflows") also start by hand with `/wstack:start-task`.

### 7.2 Confirmation (confirmed)

Purpose: turn the rough idea into one clear spec that the user approves.

1. The agent writes `spec.md` in one of two ways:
   - The user gives a rough idea. The agent asks questions, one at a time, and writes the spec.
   - The user gives a written spec. The agent finds the unclear parts and asks about them.
2. The spec must hold these sections:
   - Goal: what the result must do.
   - Scope: what is in and what is out.
   - Verification plan: how the work will be checked. Name each check, its pass rule, and the evidence it will produce.
   - Non-undoable steps: every step that will need the user's approval.
   - Deliver targets: where the result goes (section 11).
3. When the user's Obsidian notes are relevant, the agent reads them as context. The vault is the ground truth.
4. The agent sets `status: awaiting-approval` and waits. After the user approves, the agent sets `approved_at` and `status: executing`.
5. Pages follow the layout rules in section 10.1. The default is a local HTML file on the Mac. In mobile mode, the agent also publishes the page as a Claude artifact.

Done when: `spec.md` has all five sections and `approved_at` is set.

### 7.3 Execute (confirmed)

Purpose: do the work without the user.

- The agent works and iterates on its own. It does not stop for questions that the spec already answers.
- The agent stops only before a non-undoable step. It sets `status: waiting-user`, writes the reason in `run-log.md`, and asks the user.
- The agent writes each step, each retry, and each stop into `run-log.md`.
- ASSUME: for code tasks, the agent works on a new branch named `wstack/<slug>`. It never commits to the default branch.

Done when: the agent believes the spec is met and `run-log.md` lists every step.

### 7.4 Verify (confirmed)

Purpose: prove that the result works, prove that it can be undone, and review it.

Order:

1. Behavior check: run each check from the spec's verification plan. Record evidence for each check (section 12).
2. Rollback check: confirm that a working way to undo the result exists. Write the undo steps in `review.md`.
3. Final review: start the reviewer agent (section 8.2). It writes findings into `review.md`.
4. Build the review page (section 10).

Findings:

| Finding | Kinds | Action |
|---|---|---|
| Blocking | spec mismatch, correctness, security | Back to Execute. Counts toward `retry_limit`. |
| Non-blocking | design, test coverage | The result goes on to Deliver. Findings appear at the top of the review page for the user to decide later. |

Done when: every check has a pass result with evidence, the undo steps exist, and no blocking finding is open.

### 7.5 Deliver (confirmed)

- If every target is undoable, the agent delivers without asking.
- If a target is non-undoable, the agent sends a short report to the user and waits. After the user approves, the agent performs the action itself.
- Merge always waits for the user's approval.
- The agent writes `report.md`: what shipped, where, the URLs, and how to undo each target.
- After a merge, the agent deletes the task's evidence from R2 (section 12.5).

Section 11 lists the targets.

### 7.6 Failure path (confirmed)

```
Verify fails
  ├─ spec right, work wrong ──► back to Execute
  │     fix and verify again, up to retry_limit tries
  │     still failing ──► report to the user, status: waiting-user
  └─ spec wrong or unclear ──► back to Confirmation
        the agent asks the user
```

If the session ends (closed terminal, Mac asleep, network outage), the task stays in its last status.

ASSUME: the user can resume a task in a new session. To do this, the user runs `/wstack:start-task` with no arguments. The agent then lists the tasks that are not `delivered` or `cancelled`.

## 8. Agents

### 8.1 Worker agent

The main Claude Code session. It runs the `start-task` skill, owns the task folder, and performs every action, including approved non-undoable actions.

### 8.2 Reviewer agent (confirmed)

File: `agents/reviewer.md`. It runs as a subagent with a fresh context. It did not write the work.

Inputs: `spec.md`, the change (diff, draft, or rendered file), `review.md` check results, and the evidence list.

It checks, for code:

1. Spec match: the change does what the spec says, and nothing more.
2. Correctness: bugs, missed edge cases, wrong error handling.
3. Security: secrets in code, unsafe input handling, permission mistakes.
4. Design: code that is hard to change later, duplicate logic, code that does not follow the repository's existing patterns.
5. Tests: whether the tests cover the change, not only whether they pass.

For blog posts: facts, tone, and links against the spec.
For videos: cuts, audio, and length against the spec.
For thinking work: the result answers the question in the spec, every claim links to a source, and guesses are marked as guesses.

Output: a findings list in `review.md`. Each finding has: id, kind, blocking (yes or no), file and line or timestamp, problem, and suggested fix.

### 8.3 Retro analyst agent

File: `agents/retro-analyst.md`. Used by `/wstack:run-retro` (section 13).

## 9. Work types (confirmed)

The list is not complete. The worker agent picks the closest type. If no type fits, it uses the closest type and says so in `spec.md`.

| Work type | Examples | Verify "Behavior" | Undo method |
|---|---|---|---|
| code | Appier tasks, side projects, bug fixes, refactors, dependency upgrades, writing tests, reviewing other people's pull requests, READMEs | tests pass, the app runs, API checks pass | close the pull request, revert, or delete the branch |
| ops | log and incident analysis, incident write-ups | findings link to log lines, timeline is complete | delete the new note |
| thinking | research, analysis, learning input and output | answers the spec question, every claim has a source, guesses are marked | delete the new note |
| blog | blog posts | facts, tone, and links checked | delete the draft |
| video | video editing | cuts, audio, length, plays correctly | delete the rendered file |

### 9.1 Thinking work (confirmed)

- The agent always writes a new note in the Obsidian vault. It never overwrites an existing note.
- Undo means: delete that note.
- Deliver: always undoable, so the agent saves the note and sends a short summary without asking.

### 9.2 Learning (confirmed)

- Input: the agent finds and prepares material for the user to read, watch, or study.
- Output: the agent helps the user make notes, a blog post, or a talk. It also tests what the user learned with quizzes, flashcards, or an "explain it back" exercise.

## 10. Review page (confirmed)

### 10.1 Layout rules

- One narrow column. No wide presentation.
- A sticky navbar at the top. No sidebar.
- The same page works on a phone and on a laptop.
- ASSUME: maximum content width 760 px, body text at least 16 px, tap targets at least 44 px high.

### 10.2 Where the page opens

- Default: a local HTML file in the task folder, opened on the Mac.
- Mobile mode: the agent also publishes the page as a Claude artifact, so the user can open it on the phone.

### 10.3 Page sections, in order

```
┌──────────────────────────────────────────┐
│ Findings | Decisions | Evidence | Diagram | Diff │  sticky top navbar
├──────────────────────────────────────────┤
│ 1. Findings      blocking first, then non-blocking
│ 2. Decisions     approve or reject per item, "copy reply" pastes back
│ 3. Evidence      one item per Verify check: check → evidence link → pass/fail
│ 4. Diagram       architecture delta, or sequence/flowchart
│ 5. Guided diff   groups by purpose, one-line reason, tap a group to open its code
└──────────────────────────────────────────┘
```

For blog posts and videos, section 5 is a before-and-after view instead of a guided diff.

### 10.4 Build method

- answer-me-with-html builds the page. The reviewer agent writes `review.md`, and the answer-me-with-html CLI turns it into HTML. Its comment and decision panels are the approve and reject controls. The "copy reply" text goes back into the Claude Code session.
- answer-me-with-html saves pages to `~/.answer-me-with-html/pages/` by default. The agent copies the page into the task folder as `review.html`.
- diagram-design draws the diagram section:
  - Default for code changes: the "architecture delta" type (before and after).
  - When the logic changed but the structure did not: sequence or flowchart.
- If the default answer-me-with-html layout breaks the rules in 10.1, apply `templates/mobile.css`. (Not tested. See section 17.)

## 11. Deliver targets (confirmed)

The agent always performs the action. "Needs approval" means the agent waits for the user's approval first.

| Work type | Target | Undo | Needs approval |
|---|---|---|---|
| code | open a pull request (not merged) | yes | no |
| code | merge | treated as no | yes, always |
| code | deploy | no | yes |
| thinking, ops | new Obsidian note | yes | no |
| blog | draft on the blog platform | yes | no |
| blog | publish | no | yes |
| video | rendered file in a folder | yes | no |
| video | upload to a platform | no | yes |

A merge can be reverted, but other people can see it before the revert. That is why it counts as non-undoable.

## 12. Evidence (confirmed)

### 12.1 What to record

The agent records evidence during Verify, one set per check in the spec's verification plan.

| Kind | Tool | Format |
|---|---|---|
| API behavior | `curl -v` or a script that saves each request and response with status, headers, and body | text |
| Web pages | Playwright screenshots and video | images, video |
| Terminal output | asciinema or VHS | recording |
| Any screen | macOS `screencapture` | image |

For API behavior, the text log is the main evidence, because the user can read the exact data and compare it with the expected result.

### 12.2 Compression

| Use | Screenshots | Videos | Logs |
|---|---|---|---|
| R2 (and local working copy) | WebP | H.265: `ffmpeg -i in.mov -c:v libx265 -preset veryfast -crf 28 -tag:v hvc1 out.mp4` | text |
| Pull request attachment | JPEG | H.264 MP4: `ffmpeg -i in.mov -c:v libx264 -preset veryfast -crf 28 -movflags +faststart out.mp4` | text in the PR body |

Reasons, from GitHub's documentation:

- GitHub accepts PNG, GIF, JPEG, SVG, and video (.mp4, .mov, .webm). It does not list WebP.
- Video codec support depends on the browser. GitHub recommends H.264.
- Size limit: 10 MB for images. 10 MB for videos on a free plan, 100 MB on a paid plan.

If a pull request file is larger than `pr_media_max_mb`, the agent shortens the video or lowers its resolution until it fits.

### 12.3 Storage

- Working folder: `/tmp/wstack-evidence/<task_id>/`. Used only during capture and upload.
- Permanent storage: the private R2 bucket `r2_bucket`, under `evidence/<task_id>/`.
- Never in the Obsidian vault.
- `review.md` lists each evidence file by name with its check and its pass or fail result.

If the repository is in `local_evidence_only_repos`, or if `r2_bucket` is empty, evidence stays in `/tmp/wstack-evidence/<task_id>/`. macOS can delete files in `/tmp` after a restart, so `review.md` notes "local only".

### 12.4 Viewing

- Review pages link to `https://<evidence_domain>/evidence/<task_id>/<file>`.
- Cloudflare Access protects the domain. Only allowed emails can view the files. Login uses a one-time PIN sent by email, or a Google login.
- Do not use presigned URLs. A presigned URL works for anyone who has the link.

### 12.5 Deletion

- An R2 lifecycle rule deletes objects under `evidence/` after `evidence_retention_days` days.
- After the agent merges a pull request, it deletes `evidence/<task_id>/` with `scripts/evidence-delete.sh`. Wrangler deletes one object at a time, so the script loops over the files.

### 12.6 Pull request attachments

For code tasks, the agent attaches the GitHub copies to the pull request description:

```bash
gh pr create --title "<title>" --body-file /tmp/wstack-evidence/<task_id>/pr-body.md \
  --attach /tmp/wstack-evidence/<task_id>/gh/check-1.jpg \
  --attach /tmp/wstack-evidence/<task_id>/gh/flow.mp4
```

If an upload fails, the agent keeps the R2 copy and writes the failure in `review.md`.

## 13. /wstack:run-retro (confirmed)

- The user runs it by hand, once a week.
- The retro analyst agent reads every task folder from the past 7 days.
- It looks for:
  - repeated agent steps that can become a tool or a script
  - tasks that the user started by hand several times and that can become a fixed workflow
  - tasks that used more tokens than needed
  - retries and blocking findings that point to weak spots in specs or checks
  - other improvements it finds
- Output: a list of proposals. Each proposal has the evidence (task ids and numbers), the change, and the expected gain. The page follows the layout rules in 10.1.
- The user chooses which proposals to apply. The agent applies only the chosen ones.
- ASSUME: the agent saves the retro to `<vault_path>/<tasks_dir>/../Retros/<YYYY-Www>.md`.

The name is `retro`, not `review`, because "review" already means the final review inside Verify.

## 14. Approval rules, in one place

The agent asks the user before these actions, and never otherwise:

1. Approving the spec (Confirmation).
2. A non-undoable step during Execute.
3. A non-undoable deliver target (section 11). Merge always.
4. After `retry_limit` failed tries.
5. When the spec is wrong or unclear.

The user approves in the Claude Code session, in the terminal or in the Claude app. The review page "copy reply" text is one way to give that answer.

## 15. Security and privacy

- The R2 bucket stays private. Keep the r2.dev development URL turned off. Access controls do not work on the r2.dev URL.
- Create the Cloudflare Access application before you connect the custom domain to the bucket. A custom domain makes the bucket public until Access protects it.
- Company work: the user must check company policy before Appier evidence goes to a personal Cloudflare account. Until then, add Appier repositories to `local_evidence_only_repos`.
- GitHub Enterprise Server: its docs say uploaded attachment URLs can be viewed without authentication, even for private repositories. If a repository is on GitHub Enterprise Server, do not attach evidence to its pull requests until the user approves.
- Never put secrets, tokens, or personal data in evidence. Before upload, the agent removes `Authorization` headers, cookies, and API keys from API logs.

## 16. Build order and done checks

Build in this order. Each step must pass its done check before the next step starts.

| Step | Build | Done check |
|---|---|---|
| 1 | Plugin skeleton: `plugin.json` (name `wstack`, displayName `wStack`, userConfig), empty skills | `claude plugin validate ./wstack` passes. `/wstack:start-task` appears in Claude Code. |
| 2 | Task folder and templates | `/wstack:start-task test idea` creates `<tasks_dir>/<date>-test-idea/` with the four `.md` files and frontmatter. |
| 3 | Confirmation | For a rough idea, the agent asks questions one at a time, writes a `spec.md` with all five sections, and stops at `awaiting-approval`. |
| 4 | Execute | After approval, the agent works on branch `wstack/<slug>`, logs steps in `run-log.md`, and stops before a non-undoable step. |
| 5 | Verify checks and failure path | A failing check sends the task back to Execute. After `retry_limit` failures, the status is `waiting-user`. |
| 6 | Reviewer agent | On a sample change with one planted bug, the reviewer agent reports it as a blocking finding. |
| 7 | Review page | `review.html` has the five sections in order, a sticky top navbar, and no horizontal scroll at 375 px width. |
| 8 | Evidence capture and compression | One API check produces a text log. One UI check produces a WebP screenshot and an H.265 video. |
| 9 | R2 upload, Access links, deletion | Files appear under `evidence/<task_id>/`. A link opens only after an allowed-email login. `evidence-delete.sh` removes the folder. |
| 10 | Pull request attachments | `gh pr create --attach` shows a JPEG and an H.264 video inline in the PR description, each under 10 MB. |
| 11 | Deliver | Undoable targets ship without asking. Merge waits for approval, then the agent merges and deletes evidence. `report.md` lists undo steps. |
| 12 | Mobile mode | With `--mobile`, the confirmation and review pages are also published as Claude artifacts. |
| 13 | `/wstack:run-retro` | On a week of sample task folders, it lists at least one proposal with task ids and numbers. |

## 17. Check first (not verified)

| # | Item | Why it matters | How to check |
|---|---|---|---|
| 1 | How an agent reads the session token count and writes it into `run-log.md` | `/wstack:run-retro` needs it to find token savings | Check Claude Code docs for usage output, hooks data, or OpenTelemetry. |
| 2 | Whether answer-me-with-html can save to a chosen path (`am config`) | Copy step in 10.4 | Run `am config` and read its options. |
| 3 | Whether answer-me-with-html pages work at phone width | Layout rules in 10.1 | Open a sample page at 375 px. If the layout breaks, write `templates/mobile.css`. |
| 4 | Whether Obsidian Sync runs only while Obsidian is open | Phone edits reaching the Mac | Edit a note on the phone with Obsidian closed on the Mac, then check the file on disk. |
| 5 | Whether the phone can open a local HTML file through Remote Control | Mobile mode design | Assumed no. Test once. |
| 6 | One-command prefix delete in R2 | `evidence-delete.sh` | Read the wrangler docs. If none exists, loop over the files. |
| 7 | Cloudflare Zero Trust free plan user limit | Granting access to other people | Check Cloudflare's pricing page. |
| 8 | Whether a plugin skill can run as `/start-task` without the `wstack:` prefix | Command name the user types | Install the plugin and test. If not, use `/wstack:start-task`. |
| 9 | Whether `plugin.json` `dependencies` can require plugins from other marketplaces | Installing answer-me-with-html and diagram-design | Check the Claude Code dependencies docs. If not, list them as manual prerequisites in the README. |

## 18. Setup to-dos for the user

1. Get a domain on Cloudflare. Cloudflare Access needs it for the evidence subdomain.
2. Create the R2 bucket.
3. Add the lifecycle rule: prefix `evidence/`, delete after 30 days.
4. Create the Cloudflare Access application and an Allow policy with your email.
5. Connect the custom domain to the bucket. Do this after step 4.
6. Check company policy for Appier evidence. Until then, list Appier repositories in `local_evidence_only_repos`.
7. Update gh to v2.99.0 or later.
8. Install answer-me-with-html and diagram-design.
9. Install wStack and fill in the `userConfig` values.

## 19. Later (not in version 1)

- Schedule triggers and event triggers (time of day, new Jira ticket, new email, new file).
- A different value for `retry_limit` after real use.

## Sources

- Claude Code plugin manifest reference: https://code.claude.com/docs/en/plugins-reference
- Claude Code Remote Control: https://code.claude.com/docs/en/remote-control.md
- answer-me-with-html: https://github.com/QingYunA/answer-me-with-html
- diagram-design: https://github.com/cathrynlavery/diagram-design
- GitHub CLI `--attach`: https://github.blog/changelog/2026-09-01-github-cli-media-in-issues-pull-requests-and-comments
- GitHub attachment types and limits: https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files
- Cloudflare R2 object lifecycles: https://developers.cloudflare.com/r2/buckets/object-lifecycles
- Protect an R2 bucket with Cloudflare Access: https://developers.cloudflare.com/r2/tutorials/cloudflare-access/
