# wStack Contract Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before `Confirmation` writes a spec, make the service contract in the vault fresh. After a PR merges, write the task's contract changes back.

**Architecture:** Three bash scripts carry all logic that a test can pin: `contract-check.sh` finds drift, `contract-path.sh` finds the contract file, and `contract-edit.sh` changes the contract under a lock. One hook script prints a drift line at session start and after git commands. Two read-only agents read the contract and its history. The skills call the scripts and the agents at three points: the gate in `Confirmation`, the reviewer in `Verify`, and the write-back in `deliver-task`. A new work type `contract` writes the first contract.

**Tech Stack:** bash 3.2, git 2.31 or later, jq, gh, Claude Code plugin skills, agents, and hooks, `claude plugin eval`.

**Spec:** `docs/superpowers/specs/2026-11-21-contract-gate-design.md`, section 6 except 6.9 to 6.11, and step 3 and step 4 of section 7.

**Depends on:** `docs/superpowers/plans/2026-11-21-renames-and-handover-move.md` is merged. This plan uses `scripts/lib/repo.sh` (`main_checkout`), `scripts/handover/resolve-org.sh`, `scripts/handover/resolve-service.sh`, `scripts/handover/parse-mapping.sh`, and the skill name `deliver-task`.

## Global Constraints

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, runs on `/bin/bash` 3.2, and quotes every path variable.
- Frontmatter is one `key: value` per line. A list value is one-line JSON (see `scripts/lib/frontmatter.sh`). The contract follows this rule too, for example `tags: ["type/contract"]`.
- The contract body states only what is true now, in the present tense. `@` paths are relative to the repository root.
- The contract describes `origin/<base_branch>`, never the local `HEAD`.
- Hooks make no network call, finish within 10 seconds, never block, and print nothing unless the contract is stale.
- A hook reads the vault path from `WSTACK_VAULT_PATH`, then `CLAUDE_PLUGIN_OPTION_VAULT_PATH`. Skills and agents use `${user_config.vault_path}` as the Config section of `skills/start-task/SKILL.md` says.
- Only the main task session writes contract files. Each group of writes runs between `contract-edit.sh lock` and `contract-edit.sh unlock`.
- The two contract agents are read only. A plugin agent cannot enforce this, so each agent body states it as a rule.
- Tests never write into `$HOME/Projects/LifeOS/`. Run every `claude -p` and `claude plugin eval` with `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID`.
- Run `bash tests/run-all.sh` before every commit. Docs and skill text pass the simple-english lint hook.
- The plugin version after this plan is `0.3.0`.

## Review Focus

1. The local ref `origin/<base_branch>` does not exist, because nobody fetched it or the branch has a new name. The check exits 2 and names the ref. The hook prints nothing. The gate tells the user. Test: Task 1.
2. `verified_commit` is unknown after a force push or a new clone. The check marks every section stale and does not exit 2. Test: Task 1.
3. A changed file name holds a space. Glob matching and the unclaimed list still work. Test: Task 1.
4. A crashed session leaves `<contract>.lock` behind. The next writer waits, then exits 4 with the lock path in the message. It never writes without the lock. Test: Task 2.
5. A PR closes without a merge. The gate drops its pending item and its patch, and the contract text does not change. Test: Task 7.

---

### Task 1: The drift check

**Files:**
- Create: `scripts/contract-check.sh`
- Create: `tests/fixtures/contract/setup.sh` (builds a test world, used by tests and evals)
- Create: `tests/test_contract_check.sh`

**Interfaces:**
- Produces `contract-check.sh <repo_dir> <contract_file>`.
  - Exit codes: 0 fresh, 1 stale, 2 error (stderr names the cause), 3 the contract file does not exist.
  - On exit 0 and exit 1, stdout holds these lines, in this order:

    ```
    status: fresh
    base: origin/main
    behind: 0
    stale_sections: []
    stale_dependencies: []
    unclaimed_files: []
    unclaimed_count: 0
    pending: []
    ```

    Each list is one-line JSON. `unclaimed_files` holds at most 10 names. `unclaimed_count` holds the full count.
- Produces `tests/fixtures/contract/setup.sh <dir>`. It prints the path of a shell file that sets `ORIGIN`, `REPO`, `VAULT`, `CONTRACT`, `FIRST_COMMIT`, and `ORG_DIR`. The world:
  - `$dir/origin.git`, a bare repository with branch `main`, and `$REPO = $dir/ws/svc`, a clone of it.
  - Commit 1 adds `cmd/main.go`, `api/routes.go`, `docs/PRD.md`, and `tests/a_test.go`.
  - `$VAULT/01Project/Acme/handover_handler__initiation.md` maps `svc` to `$REPO`, at `Services/svc`. `workspace_root` is `$dir/ws`.
  - `$CONTRACT = $VAULT/01Project/Acme/Services/svc/svc.md` has `base_branch: main` and `verified_commit:` commit 1. It has the sections `Team docs` (`- @docs/PRD.md`), `Abilities` (`sources: cmd/**`), `Interfaces` (`sources: api/**`), and `Depends on`. It has `ignore: ["tests/**"]` and `pending: []`.

Algorithm, for the parts the spec does not fix:

- Glob match: replace `**` with `*`, then use `case "$file" in $glob)`. A `case` pattern `*` also matches `/`.
- Read the changed files with `git diff --name-only -z <verified_commit> origin/<base_branch>`, so a name with a space stays one name.
- If a file matches one of the `<!-- sources: a, b -->` globs of a section, that section claims the file. A `## ` section with no `sources` comment claims nothing and is never stale by itself.
- A `Depends on` line has the form `- <app> (mapped): ... commit <sha>`. Find that service in the initiation file of the same ORG folder with `parse-mapping.sh`. If its contract has a different `verified_commit`, or no contract exists, add `<app>` to `stale_dependencies` and add `Depends on` to `stale_sections`.

- [ ] **Step 1: Write `tests/fixtures/contract/setup.sh` and the failing test**

Each case runs `setup.sh` in a new temp folder, then changes the world.

| Label | Change | Expected |
| --- | --- | --- |
| fresh | none | exit 0, `status: fresh`, `behind: 0` |
| section stale | commit and push `api/new.go` | exit 1, `stale_sections: ["Interfaces"]`, `behind: 1` |
| team doc stale | commit and push a change to `docs/PRD.md` | exit 1, `stale_sections` holds `"Team docs"` |
| unclaimed | commit and push `README.md` | exit 1, `unclaimed_files: ["README.md"]`, `unclaimed_count: 1` |
| ignored | commit and push `tests/b_test.go` | exit 0 |
| space in a name | commit and push `api/my file.go` | exit 1, `stale_sections: ["Interfaces"]` |
| feature branch | commit `api/x.go` on a local branch, do not push, stay on that branch | exit 0 |
| unknown commit | set `verified_commit` to `0123456789abcdef0123456789abcdef01234567` | exit 1, `stale_sections: ["Team docs","Abilities","Interfaces"]` |
| pending listed | add a pending item `{"pr":12,"task":"t1"}` | exit 0, `pending: [{"pr":12,"task":"t1"}]` |
| dependency changed | add a second mapped service `dep` with a contract, record its commit in `Depends on`, then change that contract's `verified_commit` | exit 1, `stale_dependencies: ["dep"]` |
| missing contract | delete `$CONTRACT` | exit 3 |
| bad frontmatter | delete the `verified_commit` line | exit 2 |
| missing base ref | set `base_branch: release` | exit 2, stderr names `origin/release` |

- [ ] **Step 2: Run it and make sure that it fails**

Run: `bash tests/test_contract_check.sh`
Expected: errors that `contract-check.sh` does not exist.

- [ ] **Step 3: Write `scripts/contract-check.sh` as the Interfaces block says**

- [ ] **Step 4: Run the test and make sure that it passes**

Run: `bash tests/test_contract_check.sh`
Expected: `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add scripts/contract-check.sh tests/fixtures/contract tests/test_contract_check.sh
git commit -m "feat: add the contract drift check"
```

---

### Task 2: Locked contract edits

**Files:**
- Create: `scripts/contract-edit.sh`
- Create: `tests/test_contract_edit.sh`

**Interfaces:**
- Produces `contract-edit.sh <subcommand> ...`:

| Subcommand | Effect | Exit |
| --- | --- | --- |
| `lock <contract_file>` | `mkdir "<contract_file>.lock"`. Tries 10 times, 1 second apart. | 0 locked. 4 busy: stderr names the lock path. It also says: if no task runs, remove the lock folder. |
| `unlock <contract_file>` | `rmdir` of the lock folder | 0 |
| `apply <target_file> <patch_file> [--sections "A,B"]` | For each `## <Name>` block in the patch, or only the listed names, replace the section of the same name in the target. A section runs from its `## ` line to the next `## ` line or the end. If the target lacks the section, append it. The frontmatter and the `# ` title stay. The block `## Remove from plan` is never applied. Prints each applied name on its own line. | 0. 2 when the patch holds no section. |
| `delete-section <target_file> <heading>` | Remove the `## <heading>` section | 0. 1 when the section does not exist. |
| `pending-add <contract_file> <pr> <task_id>` | Append `{"pr":<pr>,"task":"<task_id>"}` to `pending` | 0 |
| `pending-remove <contract_file> <pr>` | Remove the items with that `pr` | 0 |
| `set-verified <contract_file> <commit>` | Set `verified_commit` and set `verified_at` to `date -u +%Y-%m-%dT%H:%M:%SZ` | 0 |
| `next-decision-id <decisions_dir>` | Print the next 4-digit id. For an empty or missing folder, print `0001`. | 0 |

- [ ] **Step 1: Write the failing test**

| Label | Expected |
| --- | --- |
| lock then busy | the first `lock` exits 0. A second `lock` exits 4 within 15 seconds, and stderr holds the lock path. |
| unlock frees | after `unlock`, `lock` exits 0 |
| apply replaces one section | a patch with `## Interfaces` changes only that section. The frontmatter, the title, and every other section stay byte for byte. |
| apply keeps subheadings | a `### ` line inside a patched section stays in the result |
| apply appends a new section | a patch with `## Consumers` on a contract without it appends the section |
| apply with --sections | a patch with two sections and `--sections "Abilities"` changes only `Abilities` |
| remove-from-plan block | a patch with `## Remove from plan` does not add that section to the target |
| empty patch | exit 2 |
| delete-section | removes `## P2 Redis cache` from a `plan.md`, and keeps `## P1` and `## P3` |
| pending add and remove | after two adds and one remove, `pending` is `[{"pr":15,"task":"t2"}]` |
| set-verified | `verified_commit` is the given value, and `verified_at` matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}T` |
| next-decision-id | `0001` for a missing folder. `0004` after files `0001-a.md` and `0003-b.md`. |

- [ ] **Step 2: Run it and make sure that it fails**

Run: `bash tests/test_contract_edit.sh`
Expected: errors that the script does not exist.

- [ ] **Step 3: Write `scripts/contract-edit.sh` as the Interfaces block says**

Use `fm_get`, `fm_set`, and `fm_append` from `scripts/lib/frontmatter.sh` for the frontmatter edits.

- [ ] **Step 4: Run the test and make sure that it passes**

Run: `bash tests/test_contract_edit.sh`
Expected: `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add scripts/contract-edit.sh tests/test_contract_edit.sh
git commit -m "feat: add locked contract edits"
```

---

### Task 3: Contract path and the drift hook

**Files:**
- Create: `scripts/contract-path.sh`, `scripts/contract-hook.sh`
- Modify: `hooks/hooks.json`
- Create: `tests/test_contract_path.sh`, `tests/test_contract_hook.sh`

**Interfaces:**
- Consumes: `main_checkout`, `resolve-org.sh`, and `resolve-service.sh` from the plan before this one. Consumes `contract-check.sh` and `tests/fixtures/contract/setup.sh` from Task 1.
- Produces `contract-path.sh --vault <vault> <cwd>`. It prints `<vault>/01Project/<org>/<lifeos_subpath>/<app_name>.md`. The file does not need to exist. Exit codes: 0 found, 1 not mapped, 2 error. It works from a herdr worktree.
- Produces `contract-hook.sh`. It reads the hook JSON on stdin: `.hook_event_name`, `.cwd`, and `.tool_input.command`.
  - It prints nothing and exits 0 in each of these cases:
    - No vault path is set.
    - The event is `PostToolUse`, and the command does not match the git pattern below.
    - `contract-path.sh` exits non-zero.
    - `contract-check.sh` exits with a code other than 1.
  - The git pattern: `(^|[;&|[:space:]])(git (pull|merge|rebase|switch|checkout|reset)|gh pr checkout)([[:space:]]|$)`.
  - When the check exits 1, it prints one line of JSON: `{"hookSpecificOutput":{"hookEventName":"<event>","additionalContext":"wStack: <app> contract is <behind> commits behind <base>. Stale: <sections joined with \", \">. A new spec runs the contract gate first."}}`.
- `hooks/hooks.json` gets two entries next to the guard. `SessionStart` with matcher `startup|resume`, and `PostToolUse` with matcher `Bash`. Both run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/contract-hook.sh"` with `timeout` 10.

- [ ] **Step 1: Write the failing tests**

`tests/test_contract_path.sh`, built on `setup.sh`: prints `$CONTRACT` for `$REPO`. Prints `$CONTRACT` for a worktree of `$REPO` under `$dir/.herdr/worktrees/svc/feat`. Exits 1 for an unmapped repository.

`tests/test_contract_hook.sh` sets `WSTACK_VAULT_PATH="$VAULT"` and pipes JSON to the hook:

| Label | Input | Expected |
| --- | --- | --- |
| session start, stale | `SessionStart`, cwd `$REPO`, after a pushed `api/` change | one line. `jq -r .hookSpecificOutput.additionalContext` holds `1 commits behind origin/main` and `Stale: Interfaces`. |
| session start, fresh | `SessionStart`, cwd `$REPO` | no output, exit 0 |
| after git pull | `PostToolUse`, command `git pull --ff-only`, stale | one line, `hookEventName` is `PostToolUse` |
| other command | `PostToolUse`, command `ls -la`, stale | no output |
| unmapped | `SessionStart`, cwd an unmapped repository | no output |
| no vault | `WSTACK_VAULT_PATH` and `CLAUDE_PLUGIN_OPTION_VAULT_PATH` unset | no output |
| plugin option | only `CLAUDE_PLUGIN_OPTION_VAULT_PATH` set, stale | one line |

- [ ] **Step 2: Run them and make sure that they fail**

Run: `bash tests/test_contract_path.sh; bash tests/test_contract_hook.sh`
Expected: errors that the scripts do not exist.

- [ ] **Step 3: Write the two scripts and the two `hooks/hooks.json` entries**

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `bash tests/test_contract_path.sh && bash tests/test_contract_hook.sh && bash tests/test_manifest.sh`
Expected: `Failed: 0` three times. `test_manifest.sh` runs `claude plugin validate`.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add scripts/contract-path.sh scripts/contract-hook.sh hooks/hooks.json tests/test_contract_path.sh tests/test_contract_hook.sh
git commit -m "feat: add the contract drift hook"
```

---

### Task 4: Contract templates and the two new spec sections

**Files:**
- Create: `templates/contract.md`, `templates/plan.md`, and `templates/decision.md`. They use the formats of spec sections 6.1 to 6.3.
- Placeholders: `{{app_name}}`, `{{repo}}`, `{{base_branch}}`, `{{org_kebab}}`, `{{id}}`, `{{date}}`, `{{task_id}}`, `{{title}}`.
- Modify: `templates/spec.md`: add `## Contract changes` and then `## Decisions` after `## Deliver targets`.
- Modify: `skills/start-task/references/confirmation.md` (line 3 "all five sections", and step 4, which lists the headings). Add two bullets to step 4:
  - `## Contract changes`: the planned contract changes, or `None`.
  - `## Decisions`: each choice between named options, with the options and the reason, or `None`.
- Modify: `evals/confirm-written-spec/graders/spec-sections.md` (the list of headings).
- Modify: `tests/test_new_task_folder.sh`

**Interfaces:**
- Produces the seven spec headings, in this order: `Goal`, `Scope`, `Verification plan`, `Non-undoable steps`, `Deliver targets`, `Contract changes`, `Decisions`.
- Produces `templates/contract.md` with every section of spec 6.2 and `pending: []`, `ignore: []`, `tags: ["type/contract", "project/{{org_kebab}}/{{app_name}}"]`.

- [ ] **Step 1: Add the failing assertions to `tests/test_new_task_folder.sh`**

```bash
headings="$(grep '^## ' "$folder/spec.md" | tr '\n' '|')"
assert "spec has seven sections in order" '[ "$headings" = "## Goal|## Scope|## Verification plan|## Non-undoable steps|## Deliver targets|## Contract changes|## Decisions|" ]'
assert "contract template frontmatter" 'grep -qx "pending: \[\]" "$repo_root/templates/contract.md" && grep -qx "base_branch: {{base_branch}}" "$repo_root/templates/contract.md"'
assert "plan template" '[ -f "$repo_root/templates/plan.md" ]'
assert "decision template" 'grep -qx "status: accepted" "$repo_root/templates/decision.md"'
```

Use the folder variable that the test already has.

- [ ] **Step 2: Run it and make sure that it fails**

Run: `bash tests/test_new_task_folder.sh`
Expected: `FAIL` on the four new assertions.

- [ ] **Step 3: Write the templates and edit the files in the Files list**

- [ ] **Step 4: Run the test and make sure that it passes**

Run: `bash tests/test_new_task_folder.sh`
Expected: `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add templates tests/test_new_task_folder.sh skills/start-task/references/confirmation.md evals/confirm-written-spec
git commit -m "feat: add contract templates and the contract spec sections"
```

---

### Task 5: The two contract agents and the reviewer kind

**Files:**
- Create: `agents/contract-reader.md`, `agents/contract-historian.md`
- Modify: `agents/reviewer.md` (the kinds table at lines 40 to 48, and its inputs)
- Create: `tests/test_agents.sh`

**Interfaces:**
- `contract-reader`: frontmatter `name: contract-reader`, `model: sonnet`, `tools: Read, Grep, Glob, Bash`. The description says it reads one service contract for a task or a question. The prompt gives it the repository folder, the contract path, the input text, and the check output. If the prompt holds no check output, it runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/contract-check.sh"` itself. The body states these rules:
  - It never writes a file, and it never reads `decisions/`.
  - A patch never copies text from a team doc. It points at the doc with `@` instead.
  - Each unclaimed file gets an owner in the patch. The patch adds a glob for it to the `sources` comment of the section that describes it. If no section fits, the patch lists the file under `Open questions`. Its reply has this exact form:

  ```
  ### Brief
  <facts that bear on the input, each with its source: a contract section, a team doc path, or file:line>
  ### Freshness
  <status, behind, base, and stale sections from the check>
  ### Plan items
  <items from plan.md that bear on the input, marked "planned, not built", or None>
  === PATCH ===
  <## <Section> blocks with the full new text of each stale section, then an optional ## Remove from plan block with one "- <heading>" line for each built plan item, or the word None>
  ```

- `contract-historian`: frontmatter `name: contract-historian`, `model: sonnet`, `tools: Read, Grep, Glob, Bash`. The description makes Claude send "why is X like this?" questions about a mapped service to it, in any session. It lists the decision file names in `<contract folder>/decisions/` and the team ADR names in `docs/adr/` of the repository. It opens only the ones that bear on the question, and reads the related `git log` and linked task folders. It returns the reason with links. The body states that it never writes a file.
- `reviewer`: add the row `| \`contract-mismatch\` | yes |`. Add the rule: if the work contradicts the contract, and the spec's `## Contract changes` does not list that change, report a `contract-mismatch` finding. The reviewer prompt gains the contract path. If no contract exists, the reviewer skips this kind.

- [ ] **Step 1: Write the failing test `tests/test_agents.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
for agent_file in "$repo_root"/agents/*.md; do
  agent="$(basename "$agent_file" .md)"
  assert "$agent: name matches file" '[ "$(sed -n "s/^name: //p" "$agent_file")" = "$agent" ]'
  assert "$agent: model sonnet" 'grep -qx "model: sonnet" "$agent_file"'
done
reader="$repo_root/agents/contract-reader.md"
assert "reader names the check" 'grep -q "scripts/contract-check.sh" "$reader"'
assert "reader has the patch marker" 'grep -qx "=== PATCH ===" "$reader"'
assert "reader never reads decisions" 'grep -q "never reads \`decisions/\`" "$reader"'
assert "historian reads team ADRs" 'grep -q "docs/adr/" "$repo_root/agents/contract-historian.md"'
assert "reviewer has contract-mismatch" 'grep -q "| \`contract-mismatch\` | yes |" "$repo_root/agents/reviewer.md"'
finish
```

- [ ] **Step 2: Run it and make sure that it fails**

Run: `bash tests/test_agents.sh`
Expected: `FAIL` on the reader, historian, and reviewer assertions.

- [ ] **Step 3: Write the two agents and edit `agents/reviewer.md`**

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `bash tests/test_agents.sh && bash tests/test_skills.sh`
Expected: `Failed: 0` twice. `test_skills.sh` also checks each `${CLAUDE_PLUGIN_ROOT}` path in the agents.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add agents tests/test_agents.sh
git commit -m "feat: add the contract reader and historian agents"
```

---

### Task 6: The contract gate in Confirmation

**Files:**
- Modify: `skills/start-task/references/confirmation.md`: add `## Contract gate` before `## Write the spec`, and change steps 5 and 9.
- Modify: `skills/start-task/references/verify.md` step 3: pass the contract path to the reviewer.
- Create: `evals/confirm-stale-contract/prompt.md` and `evals/confirm-stale-contract/graders/gate-before-spec.md`

**Interfaces:**
- Consumes: `contract-path.sh`, `contract-check.sh`, `contract-edit.sh`, `contract-reader`, and `tests/fixtures/contract/setup.sh`.
- Produces these files in the task folder:
  - `contract-brief.md`: the reader reply before the marker.
  - `contract.gate-patch.md`: the part after the marker. The gate writes it only for a reply with a patch.
  - `contract.before.md`: a full copy of the contract before the first write of this task.

The `## Contract gate` steps, in this order:

1. If `work_type` is not `code` or `ops`, skip the gate.
2. Run `bash "$scripts/contract-path.sh" --vault "$vault" "<repository folder>"`.
   - Exit 1: write `Contract: not mapped` as a `step` line in `run-log.md`, and go on to "Write the spec".
   - Exit 2: stop with a stop item, as "Stop items" in `SKILL.md` says.
3. Read `base_branch` with `fm_get`. Run `git -C "<repository folder>" fetch origin "<base_branch>"`. If the fetch fails, go on with the local ref and say so in the brief.
4. Resolve pending items, as `deliver-task` "Pending items" says (Task 7).
5. Run `contract-check.sh`.
   - Exit 3: ask the user one question: set up the contract first (a `contract` task), or go on without a contract. End the reply and wait.
   - Exit 2: tell the user the stderr text. Ask the same question. End the reply and wait.
   - Exit 0 or 1: dispatch `wstack:contract-reader` with the repository folder, the contract path, the Goal text, and the check output. Write the reply before `=== PATCH ===` to `contract-brief.md`. If the part after the marker is not `None`, write it to `contract.gate-patch.md`.
6. "Write the spec" reads `contract-brief.md` together with the vault notes.

Change step 5 ("Show the spec"): if `contract.gate-patch.md` exists, put its text first in the draft, under the heading `# Contract changes from the gate`.

Change step 9 ("After approval"): if the check in step 5 exited 1, run these commands in order. If `contract.gate-patch.md` does not exist, skip the `cp` and `apply` lines. Then set `approved_at`.

```bash
bash "$scripts/contract-edit.sh" lock "$contract_file"
[ -f "$task_dir/contract.before.md" ] || cp "$contract_file" "$task_dir/contract.before.md"
bash "$scripts/contract-edit.sh" apply "$contract_file" "$task_dir/contract.gate-patch.md"
bash "$scripts/contract-edit.sh" set-verified "$contract_file" "$(git -C "<repository folder>" rev-parse "origin/<base_branch>")"
bash "$scripts/contract-edit.sh" unlock "$contract_file"
```

If `lock` exits 4, stop with a stop item that holds its stderr text.

- [ ] **Step 1: Write the eval**

The prompt does these steps:

1. Run `bash "__FIXTURES__/contract/setup.sh" "$PWD/world"`.
2. Push a change to `api/`.
3. Set `EVAL_WSTACK_VAULT_PATH` to the world vault.
4. Run `/wstack:start-task` in `$REPO` with a code idea about the API.
 The grader has `type: llm` and `focus: trace`. To pass, the trace shows all of these, in this order:
- `contract-check.sh` exits 1 with `Interfaces` stale.
- The session dispatches `contract-reader`.
- The spec page draft starts with `# Contract changes from the gate`.
- The session asks for approval.

Before approval, the session must not change the contract file. If it does, the grader fails.

- [ ] **Step 2: Run the eval and make sure that it fails**

Run: `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID bash tests/run-evals.sh --case confirm-stale-contract`
Expected: the grader fails, because no gate exists yet.

- [ ] **Step 3: Edit `confirmation.md` and `verify.md` as this task says**

- [ ] **Step 4: Run the eval and the existing `confirm-*` evals, and make sure that they pass**

Run: the same command with `--case 'confirm-*'`.
Expected: every grader passes. The other `confirm-*` cases have no mapped repository, so the gate writes `Contract: not mapped` and goes on.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add skills/start-task/references evals/confirm-stale-contract
git commit -m "feat: run the contract gate before the spec"
```

---

### Task 7: The write-back after the merge

**Files:**
- Modify: `skills/deliver-task/SKILL.md`: add `## Contract write-back` after the pull request target, and add `## Pending items`.
- Create: `evals/deliver-contract-pending/prompt.md` and `evals/deliver-contract-pending/graders/patch-and-pending.md`

**Interfaces:**
- Consumes: `contract-edit.sh`, `contract-reader`, `templates/decision.md`.
- Produces in the task folder: `contract.patch.md`, which holds `## <Section>` blocks and an optional `## Remove from plan` block.
- Produces a `report.md` target: `{"target":"contract write-back","url":"<contract_file>","undo":"bash <scripts>/contract-edit.sh pending-remove <contract_file> <pr>, and delete <decision files>"}`.

`## Contract write-back` runs for a `code` or `ops` task that has a contract file:

1. Dispatch `wstack:contract-reader` with the input "propose contract edits for the diff `origin/<base_branch>...wstack/<slug>` and the spec's `## Contract changes`". Write the part after `=== PATCH ===` to `contract.patch.md`. If it is `None`, skip steps 2 and 3.
2. Under the lock, run `contract-edit.sh pending-add "$contract_file" <pr> <task_id>`.
3. For each item in the spec's `## Decisions` that is not `None`: take the id from `contract-edit.sh next-decision-id "<contract folder>/decisions"`, and write `decisions/<id>-<slug>.md` from `templates/decision.md`. If the PR adds a file under `docs/adr/`, the decision file links that path and copies no text from it.
4. Record the target in `report.md`.

`## Pending items` runs from the gate (Task 6, step 4). For each item in `pending`, run `gh pr view <pr> --json state -q .state`:
- `MERGED`: take the lock. If `<tasks folder>/<task>/contract.before.md` does not exist, copy the contract there. Run `apply` with that task's `contract.patch.md`. For each `- <heading>` line under `## Remove from plan`, run `delete-section` on `plan.md`. Run `pending-remove`. Unlock. In that task's `report.md`, set the undo to `bash <scripts>/contract-edit.sh apply --sections "<applied names>" <contract_file> <task folder>/contract.before.md`.
- `CLOSED`: run `pending-remove` under the lock. Do not change the contract text.
- `OPEN`, or `gh` fails: keep the item.

`verified_commit` does not move here. The gate's own check finds what the merged change touched, and the reader compares those sections with the code.

- [ ] **Step 1: Write the eval**

The prompt does these steps:

1. Build the world with `setup.sh`.
2. Make a task folder with `status: verifying` in the spec, `result: pass` in `review.md`, and one `## Decisions` item in the spec.
3. Put a `gh` stub first on `PATH`. It prints a PR URL for `gh pr create` and `MERGED` for `gh pr view`.
4. Run `/wstack:start-task --task <id>`.
 To pass, the trace shows all of these:
- The session writes `contract.patch.md`.
- `pending` gains `{"pr":<n>,"task":"<id>"}`.
- The session writes `decisions/0001-<slug>.md`.
- `report.md` holds the `contract write-back` target.

The contract body stays unchanged in this run.

- [ ] **Step 2: Run the eval and make sure that it fails**

Run: `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID bash tests/run-evals.sh --case deliver-contract-pending`
Expected: the grader fails.

- [ ] **Step 3: Edit `skills/deliver-task/SKILL.md` as this task says**

- [ ] **Step 4: Run the eval and make sure that it passes**

Run: the same command.
Expected: the grader passes.

- [ ] **Step 5: Add a closed-PR case to `tests/test_contract_edit.sh`, then commit**

The case: a contract with one pending item. Run `pending-remove`. `pending` is `[]`, and the body is byte for byte the same as before.

```bash
bash tests/run-all.sh
git add skills/deliver-task evals/deliver-contract-pending tests/test_contract_edit.sh
git commit -m "feat: write contract changes back after the merge"
```

---

### Task 8: The `contract` work type

**Files:**
- Modify: `scripts/new-task-folder.sh:3,33` (accept `contract`), `tests/test_new_task_folder.sh`
- Modify: `skills/start-task/SKILL.md` launch steps 2, 5, and 8: `contract` is a work type, and it takes a repository like `code`.
- Modify: `skills/start-task/references/execute.md`: add `## Contract work` after `## Thinking and ops work`.
- Modify: `skills/start-task/references/verify.md`: for `contract` work, the reviewer checks each claim against the code and gives a `file:line` reference.
- Modify: `skills/deliver-task/SKILL.md`: add `### Contract files` to the targets that need no approval.
- Create: `evals/contract-absorb-existing/prompt.md`, its grader, and a fixture service folder `tests/fixtures/contract/vault-docs/` with a `PRD.md` (one built feature, one planned milestone) and a `DECISIONS.md` (two decisions).

**Interfaces:**
- `## Contract work` in `execute.md` writes drafts only, in the task folder: `contract.draft.md` (from `templates/contract.md`, with a `sources` comment on each section), `plan.draft.md`, and `decisions.draft/<id>-<slug>.md`. Absorb rules come from spec section 6.7: true facts go to the contract, planned items go to the plan, each decision gets one file, and contradicted facts go under `Open questions`. The `base_branch` comes from the spec, which the user approved.
- If `origin/<base_branch>` has no source files outside the team docs, the project is new. Then `Confirmation` asks the user one question at a time until each section has content, and every `sources` glob is a planned path.
- `### Contract files` in `deliver-task`: take the lock. If a contract exists, copy it to `contract.before.md`. Move every other file in the contract folder, except `handover/`, `decisions/`, and `_archive/`, to `_archive/`. Copy the drafts into place. Run `set-verified` with `origin/<base_branch>`. Unlock. The undo: move the files back from `_archive/`, delete the new files, and restore `contract.before.md`.

- [ ] **Step 1: Add the failing test cases and write the eval**

`tests/test_new_task_folder.sh`: `--work-type contract` exits 0 and writes `work_type: contract`. `--work-type contracts` exits non-zero.

The eval copies `vault-docs/` into the contract folder of the `setup.sh` world, deletes the contract file, and runs `/wstack:start-task set up the contract` in `$REPO`. To pass, the trace shows all of these:
- `contract.draft.md` has a `sources` comment on `Abilities` and on `Interfaces`.
- `plan.draft.md` holds the planned milestone.
- `decisions.draft/` holds two files.
- No file moves to `_archive/` before `Deliver`.

- [ ] **Step 2: Run them and make sure that they fail**

Run: `bash tests/test_new_task_folder.sh`, then `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID bash tests/run-evals.sh --case contract-absorb-existing`
Expected: the new test case fails, and the grader fails.

- [ ] **Step 3: Edit the files in the Files list**

- [ ] **Step 4: Run them and make sure that they pass**

Run: the same two commands.
Expected: `Failed: 0`, and the grader passes.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add scripts/new-task-folder.sh tests skills evals/contract-absorb-existing
git commit -m "feat: add the contract work type"
```

---

### Task 9: Docs and version 0.3.0

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `tests/test_manifest.sh` (version `0.3.0`)
- Modify: `CHANGELOG.md` (`## 0.3.0 - <date>`), `README.md` (a "Service contract" section: the vault files, the gate, the hooks, and how to set up a contract)
- Modify these parts of `docs/spec.md`:
  - section 2: the terms contract, drift, and base branch
  - section 4: the layout
  - section 6: the new task folder files
  - section 7.2: the gate
  - section 8: the two agents
  - section 9: the `contract` row
  - section 14: the write-back approval rule

- [ ] **Step 1: Change the version assertion in `tests/test_manifest.sh` to `0.3.0`, and run it**

Run: `bash tests/test_manifest.sh`
Expected: `FAIL` on the version assertion.

- [ ] **Step 2: Edit the files in the Files list**

- [ ] **Step 3: Run the tests and make sure that they pass**

Run: `bash tests/run-all.sh`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin tests/test_manifest.sh CHANGELOG.md README.md docs/spec.md
git commit -m "docs: document the contract gate for 0.3.0"
```

---

### Task 10: Ship, then write the first contract for wStack

Every step here changes something outside the branch or writes into the real vault. Ask the user before each one.

- [ ] **Step 1: Ask the user for approval, then push the branch and create the pull request**

- [ ] **Step 2: Ask the user for approval, then merge with `gh pr merge <number> --merge`, and update the installed plugin**

Run: `claude plugin marketplace update <wStack marketplace name> && claude plugin update wstack@<wStack marketplace name>`
Expected: `claude plugin list` shows `wstack` at `0.3.0`.

- [ ] **Step 3: Ask the user for approval, then run a `contract` task on wStack**

In a new session in `/Users/william.hung/Projects/breakincode/wStack`, run `/wstack:start-task set up the contract`. The user approves the spec with `base_branch: main`.

- [ ] **Step 4: Make sure that the first contract works**

Run: `bash scripts/contract-check.sh /Users/william.hung/Projects/breakincode/wStack /Users/william.hung/Projects/LifeOS/01Project/BreakinCode/Services/wstack/wstack.md`
Expected: exit 0 and `status: fresh`. The old `wstack.md` is in `Services/wstack/_archive/`. A new session in the wStack repository prints no drift line.
