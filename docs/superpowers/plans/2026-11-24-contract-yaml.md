# Contract as YAML Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `<app_name>.contract.yaml` the one source of a service contract. Generate a vault note and an HTML page from it. Check every ref and the schema by script. Fold in media-center fix items 1, 2, 4, and 5. Ship as wStack 0.8.0.

**Architecture:** `yq` (mikefarah v4) converts the YAML to JSON for reads (`yq -o=json`), and `jq` keeps doing the logic, as the scripts do today. Writes go only through `contract-edit.sh`, with `yq -i` and `strenv()`. A Python 3.9 standard-library renderer reads `yq -o=json` output and writes both views. The Deliver "Contract files" block moves into `contract-deliver.sh write|undo|rehearse`, and a wrapper runs the four scripted draft checks.

**Tech Stack:** Bash 3.2, Python 3.9 standard library, `jq`, `yq` v4 (mikefarah), git.

**Spec:** `docs/superpowers/specs/2026-11-24-contract-yaml-design.md`. Read it first: the schema, the rules, and the 9 calls after the builder check bind every task.

## Global Constraints

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, runs on `/bin/bash` 3.2, and quotes every path variable.
- Python uses only the standard library and runs on Python 3.9.
- `yq` means mikefarah `yq` version 4. `yq --version` must print `mikefarah` and ` v4.`.
- The fixed section keys, in this order: `team_docs`, `abilities`, `interfaces`, `depends_on`, `consumers`, `gotchas`, `open_questions`. All seven keys are required in every contract file. `items` can be empty.
- `sources` is required for `team_docs`, `abilities`, `interfaces`, and `depends_on`.
- A ref is `path:lines` (lines = `N`, `N-M`, or a comma list), or cross-repository `<owner>/<repo>@<commit>:path:lines`, which matches `^[^/@:]+/[^/@:]+@[0-9a-f]+:`.
- `verified_commit` is always a quoted YAML string. A SHA such as `1234567` or `12e4567` must not turn into a number.
- Lock folder: `<app_name>.contract.yaml.lock`.
- Views: vault note `<contract folder>/<app_name>.md`, HTML page `$HOME/.wstack/pages/contracts/<app_name>.html`.
- `contract-check.sh` keeps its exit codes 0, 1, 2, 3 and its eight output lines in order. The lines are `status`, `base`, `behind`, `stale_sections`, `stale_dependencies`, `unclaimed_files`, `unclaimed_count`, and `pending`. Stale section names are the section keys.
- Tests never write into `$HOME/Projects/LifeOS/`. A test that renders sets `HOME` to a temp folder.
- All text follows simple English (`rules/communication.md`). Examples use placeholder service names.
- Before each commit, run `bash tests/run-all.sh` under the bash 3.2 shim (`PATH="<shim dir>:$PATH"`, where the shim dir holds a `bash` link to `/bin/bash`). The format switch spans Tasks 2 to 8, so suites that a later task owns can fail in between. Name each failing suite and its owner task in the commit body. Task 9 must end with a full green run.
- Commit trailer:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B8rWuiKdYsPRks5MF6KFFP
  ```

## Review Focus

1. A SHA such as `1234567` or `12e4567` stays a string in `verified_commit` and `mapped_commit`. This holds through `set-verified`, `apply`, the check, and the render. Test in Task 4.
2. Claim text can hold YAML and HTML special characters: `: `, `#`, `"`, `{"errors": [...]}`, and `<script>`. Such text survives a write, and it renders escaped in the HTML and safe in Markdown. Test in Task 3.
3. A patch section that lost `sources` is refused, and the contract stays byte-for-byte unchanged. Test in Task 4.
4. A dependency whose contract is still the old `<app>.md` reads its `verified_commit` from that file. A dependency with no contract at all is not stale. Test in Task 2.
5. A rebuild keeps `<app_name>.facts.md` in place. Today the archive loop moves it into `_archive/`. Test in Task 6.

---

### Task 1: Schema, template, validator, and preflight

**Files:**
- Create: `templates/contract.yaml`, `scripts/contract-validate.sh`, `tests/test_contract_validate.sh`
- Modify: `scripts/preflight.sh` (`check_base`) and the preflight test file

**Interfaces:**
- Produces: `contract-validate.sh <contract.yaml>`. Exit 0 means valid. Exit 1 means a broken rule, with one `contract-validate.sh: <rule>: <where>` line per break on stderr. Exit 2 means a missing file, unreadable YAML, or a missing or wrong `yq`. A word count over 25 prints `warning: <section>[<index>] has <n> words` and does not change the exit code.
- Produces: `templates/contract.yaml` with the placeholders `{{app_name}}`, `{{repo}}`, `{{base_branch}}`, `{{org_kebab}}`, all seven section keys, `planned: []`, and `verified_commit: ""`.

- [ ] **Step 1: Write the failing tests** in `tests/test_contract_validate.sh`. Build each case from one valid inline YAML file and change one thing. Assertions:
  - `"valid file exits 0"`
  - `"missing summary exits 1"` and stderr names `summary`
  - `"missing open_questions key exits 1"`
  - `"unknown section key exits 1"` (for example `extras`)
  - `"abilities without sources exits 1"`
  - `"item without refs exits 1"`
  - `"planned id not kebab case exits 1"` (`Video_Ack`)
  - `"gotcha planned link to a missing id warns and exits 0"` (Ruling 3)
  - `"numeric verified_commit exits 1"` (unquoted `1234567`, which `yq` reads as a number)
  - `"bad ref form exits 1"` (`app/x.py` with no lines)
  - `"cross-repo ref form is accepted"` (`acme-org/web@ca3a273:src/a.ts:22`)
  - `"26-word item warns and exits 0"`
  - `"template with placeholders filled is valid except empty verified_commit"`: fill the placeholders and set `summary`. `verified_commit: ""` is allowed by the validator, because a draft gets it in Execute.
- [ ] **Step 2: Run** `bash tests/test_contract_validate.sh`. Expected: FAIL, the script does not exist.
- [ ] **Step 3: Implement `scripts/contract-validate.sh`.** Convert once with `yq -o=json`, then check every rule with one `jq` program that prints one line per break.
- [ ] **Step 4: Add `yq` to `check_base` in `scripts/preflight.sh`.** The check passes only for a version line with `mikefarah` and ` v4.`. The install line is `brew install yq`. Add a test case for a fake `yq` on `PATH` that prints a Python-style version.
- [ ] **Step 5: Run** the two test files. Expected: PASS.
- [ ] **Step 6: Commit** `feat: add the contract YAML schema check and template`.

### Task 2: Path, check, and the readers of the contract path

**Files:**
- Modify: `scripts/contract-path.sh`, `scripts/contract-check.sh`, `scripts/contract-hook.sh`, `scripts/facts-add.sh`, `scripts/collect-week.sh:44-45`, `scripts/handover/check-mapping.sh:57`, `tests/fixtures/contract/setup.sh`
- Test: `tests/test_contract_path.sh`, `tests/test_contract_check.sh`, `tests/test_contract_hook.sh`, `tests/test_facts_add.sh`, `tests/test_collect_week.sh`, `tests/test_check_mapping.sh`

**Interfaces:**
- Consumes: the schema of Task 1.
- Produces: `contract-path.sh` prints `<vault>/01Project/<org>/<lifeos_subpath>/<app_name>.contract.yaml`.
- Produces: `contract-check.sh <repo_dir> <contract.yaml> [--coverage]`. `--coverage` compares the empty tree (`git hash-object -t tree /dev/null`) with `origin/<base_branch>`, so every tracked file counts as changed. Use it to prove that the globs claim every file (`unclaimed_count: 0`).
- Produces: the fixture `setup.sh` writes `CONTRACT="$ORG_DIR/Services/svc/svc.contract.yaml"` with `team_docs.sources: [docs/PRD.md]`, `abilities.sources: [cmd/**]`, `interfaces.sources: [api/**]`, `depends_on.sources: []`, and `ignore: ["tests/**"]`. `world.env` keeps the same variable names.

- [ ] **Step 1: Switch the fixture to YAML.** Then update the assertions of the six test files to the new names. Keep every existing case. Changed values:
  - `contract-check` stale names: `"[\"interfaces\"]"`, `"[\"team_docs\"]"`, `"[\"depends_on\"]"`.
  - A dependency case uses a `depends_on` item with `app: dep` and `mapped_commit: "<sha>"`, not a `(mapped)` line.
- [ ] **Step 2: Add the new cases:**
  - `contract-check`: `"--coverage counts every tracked file"`. With `ignore: []` and no glob for `README.md`, `unclaimed_count` equals the number of unclaimed tracked files.
  - `contract-check`: `"dependency on an old .md contract reads its frontmatter"`. The dependency has only `dep.md` with `verified_commit: <sha>`, and `mapped_commit` matches, so it is not stale.
  - `contract-check`: `"dependency with no contract is not stale"`.
  - `contract-check`: `"broken YAML exits 2"`.
  - `contract-path`: prints the `.contract.yaml` path.
  - `facts-add`: the lock folder is `svc.contract.yaml.lock`.
- [ ] **Step 3: Run** the six test files. Expected: FAIL.
- [ ] **Step 4: Implement.** In `contract-check.sh`, keep the per-file loop. Replace the `awk` body parse with one `yq -o=json` call and one `jq` program that prints the same `S`/`G`/`D` lines. `team_docs` globs become an ordinary section glob, so the `A` path list goes away. A `D` line carries `app` and `mapped_commit`. `contract-hook.sh` takes the app name with `basename "$contract" .contract.yaml`. `facts-add.sh` and `collect-week.sh` derive `<app>.facts.md` from `<app>.contract.yaml`. `check-mapping.sh` builds the `.contract.yaml` path.
- [ ] **Step 5: Run** the six test files. Expected: PASS.
- [ ] **Step 6: Commit** `feat: read the contract from YAML in the path, check, and hook scripts`.

### Task 3: Renderer

**Files:**
- Create: `scripts/contract_render.py`, `scripts/contract-render.sh`, `tests/test_contract_render.sh`

**Interfaces:**
- Produces: `contract-render.sh <contract.yaml>`. It writes `<folder>/<app_name>.md` and `$HOME/.wstack/pages/contracts/<app_name>.html`, and creates the pages folder. It prints both paths, one per line. Exit 0 written, 2 bad input or a write failure (stderr names the cause). The shell script runs `yq -o=json` and pipes the JSON into `python3 contract_render.py <note path> <html path>`.

- [ ] **Step 1: Write the failing tests** in `tests/test_contract_render.sh`, with `HOME` set to a temp folder. Assertions:
  - `"note starts with the generated notice"`: the first body line names `svc.contract.yaml` and says that edits are lost.
  - `"note keeps the tags"`: the frontmatter holds the `tags` list.
  - `"note section order"`: the headings follow the spec order (Summary text, Gotchas, Abilities, Interfaces, Depends on, Consumers, Planned, Open questions, Team docs).
  - `"refs fold in a callout"`: the line `> [!quote]- refs (2)` follows a two-ref item.
  - `"ref links to GitHub at verified_commit"`: `https://github.com/acme-org/svc/blob/<sha>/api/routes.go#L3-L5` for `api/routes.go:3-5`.
  - `"cross-repo ref links to its own repo and commit"`.
  - `"gotcha links its plan item"`, and `"link to a removed plan item says plan item removed"`.
  - `"html escapes text"`: item text `<script>alert(1)</script> {"errors": [...]}` shows as `&lt;script&gt;` in the HTML and holds no raw `<script>` tag.
  - `"html has the summary card counts"`: for example `5 gotchas`.
  - `"html refs sit in details"`.
  - `"render twice gives the same bytes"`.
  - `"html fits 375 px"`: run `scripts/check-page-width.sh` on the page. If it exits 2 because `playwright-cli` is missing, print `SKIP` with the reason.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** both files. The markup is the builder's call within the spec's "Generated views".
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: render the contract YAML as a vault note and an HTML page`.

### Task 4: Contract edit on YAML

**Files:**
- Modify: `scripts/contract-edit.sh`
- Test: `tests/test_contract_edit.sh`

**Interfaces:**
- Consumes: `contract-validate.sh` (Task 1), `contract-render.sh` (Task 3).
- Produces:
  - `apply <contract.yaml> <patch.yaml> [--sections "a,b"] [--section "a"]... [--planned "id,id"]`. The patch holds `sections:` and optional `remove_planned: [ids]`. A full contract file also works as a patch (for undo). `--planned` restores the named plan items from the patch's `planned` list, replacing an item with the same id or appending it. It prints the applied section keys, then one `planned restored: <id>` line per restored item, then one `planned removed: <id>` line per removed item. If the patch names an unknown section key, or the result fails `contract-validate.sh`, it exits 2 and leaves the target unchanged.
  - `remove-planned <contract.yaml> <id>`: exit 0 removed, 1 no such id, 2 write failure.
  - `pending-add`, `pending-remove`, `set-verified`, `lock`, `unlock`, `next-decision-id`: same arguments and exits as today.
  - `delete-section` goes away.
  - After every successful write, it runs `contract-render.sh`. A render failure prints `contract-edit.sh: warning: render failed: <stderr>` and keeps exit 0.

- [ ] **Step 1: Rewrite `tests/test_contract_edit.sh`** for the YAML fixture. Keep the lock cases. Add:
  - `"apply replaces whole sections"`
  - `"apply --sections limits the keys"`
  - `"apply unknown key exits 2 and leaves the file unchanged"` (compare with `cksum`)
  - `"apply of a section without sources exits 2 and leaves the file unchanged"`
  - `"apply remove_planned removes items and prints them"`
  - `"undo: apply a snapshot with --sections and --planned restores the old state"`
  - `"remove-planned missing id exits 1"`
  - `"set-verified keeps 1234567 and 12e4567 as strings"`: read back with `yq -o=json` and `jq -r 'type'`, which gives `string`.
  - `"pending-add twice adds one item"`
  - `"a write renders the note"`
  - `"render failure warns and exits 0"`: make the pages folder a file.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Stage every write in a temp copy. Run `contract-validate.sh` on the copy. Move it in place under the lock. Keep the `fm_replace`-style atomic swap.
- [ ] **Step 4: Run** `tests/test_contract_edit.sh` and `tests/test_contract_validate.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: edit the contract YAML and render after every write`.

### Task 5: Ref check

**Files:**
- Create: `scripts/contract-refs.sh`, `tests/test_contract_refs.sh`

**Interfaces:**
- Produces: `contract-refs.sh <repo_dir> <contract.yaml>`. It checks every ref in all sections and in `planned`. A local ref is checked at `verified_commit`, and a cross-repository ref at its own commit in the local clone of that repository. It finds the clone through the Service Mapping: the `handover_handler__initiation.md` file up the folder tree, read with `parse-mapping.sh`. The row whose `repo_path` remote is `<owner>/<repo>` names the clone. With no such row, it tries `<workspace_root>/<repo>`. Output: one line per ref that is not ok, `bad: <ref>: <reason>` or `unchecked: <ref>: <reason>`, then `refs: <n> checked, <b> bad, <u> unchecked`. Exit 0 no bad ref, 1 a bad ref, 2 error.

- [ ] **Step 1: Write the failing tests:**
  - `"all refs hold exits 0"`
  - `"missing file is bad"`
  - `"line past the end is bad"`
  - `"N-M with M past the end is bad"`
  - `"comma list checks every number"`
  - `"cross-repo ref with no local clone is unchecked and exits 0"`
  - `"cross-repo ref with an unknown commit is unchecked"`
  - `"cross-repo ref that holds is counted as checked"`
  - `"planned refs are checked"`
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Count lines with `git show <commit>:<path> | wc -l`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: check that every contract ref exists at its commit`.

### Task 6: Deliver script, undo, rehearsal, and the draft-check wrapper

**Files:**
- Create: `scripts/contract-deliver.sh`, `scripts/contract-verify-draft.sh`, `tests/test_contract_deliver.sh`

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: `contract-deliver.sh write <task_dir> <contract_file> <task_id>`. It does what the "Contract files" block does today, on the YAML file:
  - It checks the decision ids, takes the lock, and archives the old root files into `_archive/<task_id>/` with the `.archived` marker.
  - The archive step skips `handover`, `decisions`, `_archive`, `*.lock`, and `*.facts.md`.
  - It copies `contract.draft.yaml` to the contract path and copies `decisions.draft/*`. It records `decisions.copied.txt` and runs `set-verified` (which renders).
  - It prints one line per file: `new: <path>`, `replaced: <path> (old copy: <path>)`, `moved: <old> -> <new>`, or `unchanged: <path>` for a root entry that it left in place.
  - Exit 0 done, 4 lock busy, 1 a decision id clash or a failed step. A second run after a failure is safe, as today.
- Produces: `contract-deliver.sh undo <task_dir> <contract_file> <task_id>`. It deletes the contract file, the generated note and HTML page, and the copied decisions. It moves the archived files back, deletes `_archive/<task_id>/`, and removes the empty `_archive/` and `decisions/`. Exit 0 or 1.
- Produces: `contract-deliver.sh rehearse <task_dir> <contract_file> <task_id>`. It works on copies in a temp folder with `HOME` set to a temp folder. It runs `write` and then `undo`, then `diff -r` against a clean copy. It prints the diff. Exit 0 means an empty diff, and 1 means a diff.
- Produces: `contract-verify-draft.sh <repo_dir> <task_dir> <contract_file> <task_id> <evidence_dir>`. It runs four checks on `<task_dir>/contract.draft.yaml` and writes one evidence file per check:
  - `check-contract-check.txt`: `contract-check.sh` and then `--coverage`. Pass: exit 0, and `unclaimed_count: 0` on both.
  - `check-contract-validate.txt`: `contract-validate.sh`. Pass: exit 0.
  - `check-contract-refs.txt`: `contract-refs.sh`. Pass: exit 0.
  - `check-undo-rehearsal.txt`: `contract-deliver.sh rehearse`. Pass: exit 0.
  It prints `PASS <check>` or `FAIL <check>` per check. Exit 0 means all pass, 1 means a check failed, and 2 means bad input.

- [ ] **Step 1: Write the failing tests** in `tests/test_contract_deliver.sh`, with the Task 2 fixture plus a task folder holding `contract.draft.yaml` and two drafts in `decisions.draft/`:
  - `"write on a new folder prints new lines"`
  - `"write keeps handover and facts in place"` (Review Focus 5)
  - `"write moves an old md contract and plan.md to the archive"`
  - `"write twice is safe"`
  - `"decision id clash exits 1 before any change"`
  - `"undo restores the folder"` (`diff -r` against a copy taken before `write`)
  - `"undo removes the html page"`
  - `"rehearse exits 0 and leaves the real folders unchanged"`
  - `"verify-draft writes four evidence files and exits 0"`
  - `"verify-draft fails the refs check on a bad ref"`
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** both scripts.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: move contract delivery into a script with undo and a rehearsal`.

### Task 7: Start-task text and the two agents

**Files:**
- Modify: `skills/start-task/references/confirmation.md`, `skills/start-task/references/execute.md`, `skills/start-task/references/verify.md`, `agents/contract-reader.md`, `agents/reviewer.md`, `templates/report.md`
- Delete: `templates/contract.md`, `templates/plan.md`
- Test: `tests/test_contract_skills.sh`, `tests/test_contract_blocks.sh` (the step 9 block), `tests/test_agents.sh`, `tests/test_skills.sh`

**Interfaces:**
- Consumes: the scripts of Tasks 1 to 6, by the names in their Interfaces blocks.

- [ ] **Step 1: Change the tests first.** In `test_contract_blocks.sh`, run the step 9 block on the YAML fixture. Add these text assertions:
  - `"execute writes contract.draft.yaml from templates/contract.yaml"`
  - `"execute links repo ADRs as a team_docs glob and makes no decision file for them"`
  - `"execute puts wStack settings in YAML fields, not decision files"`
  - `"execute writes disagreements.md"`
  - `"execute fetches another repo before it cites it"`: the text names `git -C` and `fetch origin` and the `<owner>/<repo>@<commit>` form.
  - `"confirmation names contract-verify-draft.sh in a contract verification plan"`
  - `"verify runs contract-verify-draft.sh for a contract task"`
  - `"verify re-reviews an edit after the last review with the diff only"`
  - `"the gate patch is YAML with a sections map"`
  - `"step 9 undo uses apply with --sections and --planned"`
  - `"reader writes a YAML patch that carries sources"`
  - `"reviewer judges whether each ref shows its claim"`
- [ ] **Step 2: Run** the four test files. Expected: FAIL.
- [ ] **Step 3: Edit the text:**
  - `confirmation.md`: G5 and step 9 read and write YAML. The `still_stale` line reads the patch keys with `yq`. The snapshot is `contract.before.yaml`. The undo is `apply <contract> <before> --sections <keys> --planned <ids>`, plus the commit command. The new-section commands go away. "Write the spec" step 2 of a `contract` task writes this `## Verification plan`: check 1 `contract-verify-draft.sh` (four evidence files), check 2 the claim review.
  - `execute.md`, "Contract work":
    - Steps 5 to 8 write `contract.draft.yaml`, `decisions.draft/`, and `disagreements.md` by the rules in the spec's "Skills and agents".
    - Item 5: before it cites another repository, run `git -C <clone> fetch origin <default branch>`, and cite `<owner>/<repo>@<origin commit>:path:lines`. If the fetch fails, cite the local commit.
  - `verify.md`:
    - Step 1 runs `contract-verify-draft.sh` for a `contract` task.
    - Step 4 tells the reviewer that `contract-refs.sh` already proved the refs exist, so it judges whether each ref shows its claim.
    - Item 4, a new rule: any edit after the last review reruns the scripted checks. Then the reviewer reads only the diff of that edit (`diff -u` against the copy of the draft saved before the fix).
  - `contract-reader.md`: reads the YAML and the `team_docs` globs. The patch is YAML with a `sections:` map, carries whole sections with `sources`, and uses `remove_planned`.
  - `reviewer.md`: add a Contract list. For each item, does its ref show the claim? A wrong claim is `spec-mismatch`, which is blocking.
  - `templates/report.md`: `## Where` says that it holds the file tree, the repositories that did not change, and the open commands.
- [ ] **Step 4: Run** the four test files. Expected: PASS.
- [ ] **Step 5: Commit** `feat: write and verify contract drafts as YAML in start-task`.

### Task 8: Deliver, retro, and init-service text

**Files:**
- Modify: `skills/deliver-task/SKILL.md`, `skills/run-retro/SKILL.md` (D2 to D7), `skills/init-service/SKILL.md` (Phase 8)
- Test: `tests/test_contract_blocks.sh`, `tests/test_contract_skills.sh`, `tests/test_skills.sh`

**Interfaces:**
- Consumes: `contract-deliver.sh write|undo` (Task 6), `contract-edit.sh apply ... --planned` and `remove_planned` (Task 4).

- [ ] **Step 1: Change the tests first.** The `files` block of `test_contract_blocks.sh` becomes a check that "Contract files" calls `contract-deliver.sh write` and records `contract-deliver.sh undo` as the undo. Its behavior tests moved to `test_contract_deliver.sh` in Task 6. Run the `merged`, `closed`, `pending-add`, and `decisions` blocks on the YAML fixture. Add:
  - `"Finish step 8 gives the file tree, unchanged repos, and open commands"`
  - `"report Where holds the tree"`
  - `"MERGED undo uses apply with --sections and --planned"`
  - `"retro D6 snapshot is contract-before.yaml"`
  - `"init-service names the contract.yaml path"`
- [ ] **Step 2: Run** the three test files. Expected: FAIL.
- [ ] **Step 3: Edit the text:**
  - `deliver-task`:
    - "Contract files" calls the script and records `{"target":"write the contract files","url":"<contract file>","undo":"bash <scripts>/contract-deliver.sh undo '<task folder>' '<contract file>' <task_id>"}`. It also copies `disagreements.md` into `report.md` under `## Doc and code disagree`.
    - The write-back and "Pending items" blocks use `remove_planned`, the `.yaml` snapshots, and the `--planned` undo.
    - Finish step 1 and step 8 (item 1): build the tree from the `new:`, `replaced:`, `moved:`, and `unchanged:` lines, or from the target list for other work types. Name each repository that did not change. Give `open '<review.html>'`, and for a contract `open '<contract page>'` and the note name for Obsidian. Give the reading order from `## Guided diff`.
  - `run-retro`: D5 to D7 use the YAML patch, `contract-before.yaml`, and the new undo.
  - `init-service` Phase 8: the path is `.contract.yaml`.
- [ ] **Step 4: Run** the three test files. Expected: PASS.
- [ ] **Step 5: Commit** `feat: deliver and refresh YAML contracts in deliver-task and run-retro`.

### Task 9: Docs, evals, and the 0.8.0 release commit

**Files:**
- Modify: `docs/spec.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `tests/test_manifest.sh`.
- Modify: the evals that name `contract.md`, `plan.md`, or a `## Section` patch. They are `evals/confirm-stale-contract`, `evals/contract-absorb-existing`, `evals/gate-applies-merged-patch`, `evals/deliver-contract-pending`, and `evals/verify-contract-mismatch`.

- [ ] **Step 1: Update `docs/spec.md`:**
  - the tree lines (new scripts, `templates/contract.yaml`, no `plan.md`)
  - the task files (`contract.draft.yaml`, `disagreements.md`, `contract.before.yaml`)
  - the contract row of the work-type table
  - the frontmatter list rule, which no longer applies to the contract
  - the `yq` requirement.
- [ ] **Step 2: Update `README.md`** (requirements: `yq` v4) **and `CHANGELOG.md`** with a `0.8.0 - <date>` entry:
  - feat: the YAML contract, the views, the ref check, the validator, the deliver script, the draft checks
  - change: plan items live in the contract, and repo ADRs are links
  - fix: a rebuild keeps the facts file
  - the migration note: rebuild each contract with a `contract` task.
- [ ] **Step 3: Update the evals** to the YAML names.
- [ ] **Step 4: Bump the version** 0.7.0 to 0.8.0 in `plugin.json`, `marketplace.json`, and `tests/test_manifest.sh` (replace every occurrence).
- [ ] **Step 5: Run** `bash tests/run-all.sh` under the bash 3.2 shim. Expected: exit 0 and `Failed: 0` in every file.
- [ ] **Step 6: Commit** `chore: release 0.8.0`.
