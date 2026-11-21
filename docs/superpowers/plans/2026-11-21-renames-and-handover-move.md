# wStack Renames and Handover Move Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename four wStack skills to `<verb>-<object>` names, and move the obsidian-kit handover commands into wStack, so that wStack no longer needs obsidian-kit.

**Architecture:** The renames are folder moves plus reference edits, pinned by a new skills test. The handover shell scripts move to `scripts/handover/` with two fixes: herdr worktrees and block-list `github_orgs`. One new script writes the ignore entry to the local git exclude file. The Python helpers move with a short copy of the Obsidian CLI runner. The four commands become wStack skills that read the vault path from wStack config.

**Tech Stack:** bash 3.2, Python 3.9 standard library, git 2.31 or later, jq, Claude Code plugin skills, `claude plugin validate`, `claude plugin eval`.

**Spec:** `docs/superpowers/specs/2026-11-21-contract-gate-design.md`, sections 6.9, 6.10, and steps 1 and 2 of section 7.

## Global Constraints

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, runs on `/bin/bash` 3.2, and quotes every path variable.
- Python scripts use only the standard library and run on Python 3.9 (`/usr/bin/python3` is 3.9.6).
- Skills use `<verb>-<object>` names. Agents keep role names.
- User commands set `disable-model-invocation: true`. Helper skills set `user-invocable: false`.
- Skills name bundled files only as `${CLAUDE_PLUGIN_ROOT}/...`.
- The ignore entry `handover` goes to the file from `git rev-parse --git-path info/exclude`. No step ever edits `.gitignore`.
- Tests never write into `$HOME/Projects/LifeOS/`. Tests that touch `~/.wstack` or `$HOME` paths set `HOME` to a temp directory.
- Run every `claude -p` and `claude plugin eval` with `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID`.
- Run `bash tests/run-all.sh` before every commit.
- Docs and skill text pass the simple-english lint hook.
- The plugin version after this plan is `0.2.0`.
- The moved code comes from `cc-plugins/obsidian-kit` at version 2.3.1, commit `c685c51`. Below, `$OK` means `/Users/william.hung/Projects/breakincode/cc-plugins/obsidian-kit`.

## Review Focus

1. A repository path or a vault path holds a space. Every resolver and the exclude script still work. Tests: Task 2 and Task 3.
2. A command runs inside a herdr worktree under `~/.herdr/worktrees/<repo>/<branch>`. The resolvers find the mapping row of the main checkout. Test: Task 2.
3. `github_orgs` is a block list (`- item` lines), as in the real Appier file. The org resolves from the git remote. Test: Task 2.
4. `.gitignore` or the global gitignore already ignores `handover`. The exclude script changes nothing and prints `already present`. Test: Task 3.
5. In a worktree, `.git` is a file and `info/` does not exist yet. The exclude script writes to the common git directory and creates `info/`. Test: Task 3.

---

### Task 1: Rename the four skills

**Files:**
- Move with `git mv`: `skills/retro` to `skills/run-retro`, `skills/review-page` to `skills/build-review-page`, `skills/evidence` to `skills/capture-evidence`, `skills/deliver` to `skills/deliver-task`. Set `name:` in each `SKILL.md` to the new folder name.
- Modify these references:
  - `skills/start-task/SKILL.md:85,105` ("the deliver skill")
  - `skills/start-task/references/verify.md:11,21,29` (the evidence, review-page, and deliver skills)
  - `tests/test_evidence_capture.sh:29` (a comment path)
  - `evals/retro-empty-week/prompt.md:12` and `evals/retro-proposal/prompt.md:12`
  - `agents/retro-analyst.md` (any `/wstack:retro`)
  - `CLAUDE.md:28-29`, `README.md:17`, and `docs/spec.md:27,37,98,106-109,160,164,488`
- Modify: `docs/diagrams/pipeline.excalidraw` (the 2 `/wstack:retro` label fields), then render `docs/diagrams/pipeline.svg` again with `scripts/render-excalidraw.sh`, the way `tests/test_docs.sh` does.
- Do not change: `CHANGELOG.md` entries before 0.2.0, `docs/decisions.md`, and `docs/superpowers/**`. They are dated records.
- Create: `tests/test_skills.sh`

**Interfaces:**
- Produces: skill names `run-retro`, `build-review-page`, `capture-evidence`, `deliver-task`. Produces `tests/test_skills.sh` with an `expected_skills` string that Task 5 extends.

- [ ] **Step 1: Write the failing test `tests/test_skills.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"

expected_skills="build-review-page capture-evidence deliver-task run-retro start-task"
actual_skills="$(ls "$repo_root/skills" | sort | tr '\n' ' ' | sed 's/ $//')"
assert "skill folders" '[ "$actual_skills" = "$expected_skills" ]'

for skill_dir in "$repo_root"/skills/*/; do
  skill="$(basename "$skill_dir")"
  assert "$skill: name matches folder" '[ "$(sed -n "s/^name: //p" "$skill_dir/SKILL.md")" = "$skill" ]'
done

missing_refs=0
for ref in $(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$repo_root/skills" "$repo_root/agents" | sort -u); do
  ref="${ref%.}"
  [ -e "$repo_root/${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}" ] || { echo "missing: $ref"; missing_refs=$((missing_refs + 1)); }
done
assert "every CLAUDE_PLUGIN_ROOT path exists" '[ "$missing_refs" -eq 0 ]'

old_names='/wstack:retro([^-a-z]|$)|the (deliver|evidence|review-page) skill|skills/(retro|evidence|deliver|review-page)/'
old_hits="$(grep -rlE "$old_names" "$repo_root" --exclude-dir=.git --exclude-dir=superpowers \
  --exclude=CHANGELOG.md --exclude=decisions.md --exclude=test_skills.sh || true)"
assert "no old skill names in current files" '[ -z "$old_hits" ]'
finish
```

- [ ] **Step 2: Run it and make sure that it fails**

Run: `bash tests/test_skills.sh`
Expected: `FAIL` on `skill folders` and on `no old skill names in current files`.

- [ ] **Step 3: Move the folders, set the names, and edit every reference in the Files list**

In prose, write the new skill name in a code span, for example "Run the `capture-evidence` skill".

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `bash tests/test_skills.sh && bash tests/test_docs.sh && bash tests/test_manifest.sh`
Expected: each prints `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add -A skills tests evals agents CLAUDE.md README.md docs/spec.md docs/diagrams
git commit -m "refactor: rename wStack skills to verb-object names"
```

---

### Task 2: Move the handover resolvers, with worktree and block-list support

**Files:**
- Create: `scripts/lib/repo.sh`
- Create by copy from `$OK/lib/`: `scripts/handover/parse-mapping.sh`, `scripts/handover/resolve-org.sh`, `scripts/handover/resolve-service.sh`, `scripts/handover/ensure-symlink.sh`. Copy `$OK/lib/initiation-template.md` to `templates/initiation.md`.
- Create by copy from `$OK/tests/handover/fixtures/`: `tests/fixtures/handover/initiation-appier.md`, `tests/fixtures/handover/initiation-empty.md`.
- Create: `tests/fixtures/handover/initiation-block.md` (Appier with a block-list `github_orgs`, as in the real vault file).
- Create: `tests/test_handover_resolve.sh`, `tests/test_ensure_symlink.sh`

**Interfaces:**
- Produces `main_checkout <dir>` in `scripts/lib/repo.sh` (sourced, not run). It prints the absolute path of the main working tree for any folder inside a repository or inside one of its worktrees. If `<dir>` is not in a git work tree, it returns 1. Method: `git -C "$dir" rev-parse --path-format=absolute --git-common-dir`, then the parent folder of that `.git` path.
- `resolve-org.sh`: reads `LIFEOS_ROOT` and `$PWD`. Prints `<org>`. Exit codes: 0 for a match, 1 for no match, 3 for a vault that is not reachable. Change: it uses `main_checkout "$PWD"` for the git remote and for the `workspace_root` match. It reads `github_orgs` in both forms: `github_orgs: [a, b]` and a `github_orgs:` line followed by `  - a` lines.
- `resolve-service.sh <cwd> <org>`: prints `<app_name>|<lifeos_subpath>`. Exit 0 match, 1 no match, 2 initiation file missing, 3 vault not reachable. Change: it compares `main_checkout "<cwd>"` with each expanded `repo_path`.
- `ensure-symlink.sh <link_path> <target> [force]` and `parse-mapping.sh <initiation_file>`: unchanged.

- [ ] **Step 1: Write the failing tests**

`tests/test_handover_resolve.sh` sets `HOME` to a temp directory, so `$HOME` in the fixtures expands inside it. It builds the vault at `"$HOME/My Vault"` with `01Project/Appier/` (from `initiation-block.md`) and `01Project/BreakinCode/` (inline `github_orgs: [21-BreakinCode]`). It exports `LIFEOS_ROOT`. Assertions:

| Label | Setup | Expected |
| --- | --- | --- |
| org from remote, block list | repository at `$HOME/elsewhere/svc`, remote `git@github.com:appier/svc.git` | `resolve-org.sh` prints `Appier` |
| org from remote, inline list | remote `https://github.com/21-BreakinCode/wStack.git` | prints `BreakinCode` |
| org from workspace_root | repository at `$HOME/Projects/Appier/x`, no remote | prints `Appier` |
| org inside a worktree | `git worktree add "$HOME/.herdr/worktrees/x/feat"` from that repository | prints `Appier` |
| org no match | repository at `$HOME/other/y`, no remote | exit 1 |
| service with a space | row `\| my-svc \| $HOME/Projects/Appier/my svc \| Services/my-svc \|` | `resolve-service.sh` prints `my-svc\|Services/my-svc` |
| service inside a worktree | a worktree of `my svc` | prints `my-svc\|Services/my-svc` |
| service not mapped | `$HOME/Projects/Appier/z` | exit 1 |
| initiation missing | org `Nope` | exit 2 |

`tests/test_ensure_symlink.sh` assertions: creates a new link (exit 0). A correct link exits 0. An empty folder at the link path is replaced (exit 0). A non-empty folder exits 1. A missing target exits 3. A link to another target exits 4, and with `force` exits 0 and points at the new target.

- [ ] **Step 2: Run them and make sure that they fail**

Run: `bash tests/test_handover_resolve.sh; bash tests/test_ensure_symlink.sh`
Expected: errors that the scripts do not exist.

- [ ] **Step 3: Copy the files, add `scripts/lib/repo.sh`, and change the two resolvers as the Interfaces block says**

In each copied file, change the header comments that name obsidian-kit, `common.vault`, or `resolve_via_handover`. The caller now sets `LIFEOS_ROOT` from wStack config.

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `bash tests/test_handover_resolve.sh && bash tests/test_ensure_symlink.sh`
Expected: `Failed: 0` twice.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add scripts/lib/repo.sh scripts/handover templates/initiation.md tests/fixtures/handover tests/test_handover_resolve.sh tests/test_ensure_symlink.sh
git commit -m "feat: move the handover resolvers into wStack"
```

---

### Task 3: Write the ignore entry to the local exclude file

**Files:**
- Create: `scripts/handover/ensure-exclude.sh`
- Create: `tests/test_ensure_exclude.sh`

**Interfaces:**
- Produces `ensure-exclude.sh <repo_dir>`. It prints `added` or `already present` and exits 0. If `<repo_dir>` is not in a git work tree, it exits 2.
- Rule:
  1. If `git -C "$repo_dir" check-ignore -q --no-index handover` succeeds, print `already present` and stop.
  2. Take the exclude path from `git -C "$repo_dir" rev-parse --path-format=absolute --git-path info/exclude`.
  3. Run `mkdir -p` on its folder.
  4. If the file does not end with a newline, add one.
  5. Append `handover`, and print `added`.

- [ ] **Step 1: Write the failing test**

Each case builds a temp repository under a path with a space. Each case records the checksum of `.gitignore` (or its absence) first, and asserts at the end that it did not change.

| Label | Setup | Expected |
| --- | --- | --- |
| fresh repository | no `.gitignore` | prints `added`. `git check-ignore -q handover` succeeds. `.gitignore` does not exist. |
| second run | run twice | second run prints `already present`. The exclude file holds one `handover` line. |
| team gitignore covers it | `.gitignore` holds `handover` | prints `already present`. The exclude file holds no `handover` line. |
| trailing slash does not count | `.gitignore` holds only `handover/`, and `handover` is a symlink | prints `added` |
| worktree | run inside a `git worktree add` folder | prints `added`. The common `info/exclude` holds `handover`. `git check-ignore -q handover` succeeds inside the worktree. |
| no info folder | delete `.git/info` first | prints `added`, and `.git/info/exclude` exists |
| not a repository | a plain folder | exit 2 |

- [ ] **Step 2: Run it and make sure that it fails**

Run: `bash tests/test_ensure_exclude.sh`
Expected: errors that the script does not exist.

- [ ] **Step 3: Write `scripts/handover/ensure-exclude.sh` as the Interfaces block says**

- [ ] **Step 4: Run the test and make sure that it passes**

Run: `bash tests/test_ensure_exclude.sh`
Expected: `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add scripts/handover/ensure-exclude.sh tests/test_ensure_exclude.sh
git commit -m "feat: write the handover ignore entry to the local exclude file"
```

---

### Task 4: Move the handover Python helpers

**Files:**
- Create: `scripts/handover/obsidian_cli.py` by copy of `CLI_TIMEOUT_SECONDS`, `CLI_ERROR_PREFIX`, `ObsidianCliError`, `parse_cli_output`, and `run_cli` from `$OK/scripts/common/obsidian_eval.py` (lines 1 to 31).
- Create: `scripts/handover/discover.py` by copy of `$OK/scripts/handover/discover.py`. Change the import to `from handover.obsidian_cli import run_cli`.
- Create: `scripts/handover/archive.py` by copy of `$OK/scripts/handover/archive.py`. Replace the `common.vault` import with the constant `ARCHIVE_ROOT = "04Archive"`.
- Create: `tests/handover/test_discover.py` and `tests/handover/test_archive.py` by copy of the `$OK` self-checks. Each inserts `Path(__file__).resolve().parents[2] / "scripts"` into `sys.path`.
- Create: `tests/test_handover_python.sh`

**Interfaces:**
- Produces `plan_archive(vault_relative_path: str, vault_root: str) -> dict` with the keys `source`, `org`, `destination`, `filename`, and `move_to`. The `config` parameter is gone.
- Produces `live_handovers(search=run_search) -> list` and `derive_org(vault_relative_path: str) -> str`, unchanged.

- [ ] **Step 1: Write the failing tests**

Copy the two self-checks. Change each `plan_archive` call to the two-argument form. Add this case to `tests/handover/test_archive.py`:

```python
plan = plan_archive("01Project/Appier/Services/x/handover/note.md", "/Users/first.last/Vault")
assert plan["destination"] == Path("/Users/first.last/Vault/04Archive/Appier")
assert plan["move_to"] == Path("04Archive/Appier/note.md")
```

If `/usr/bin/python3` exists, `tests/test_handover_python.sh` uses it. Otherwise it uses `python3`. It asserts that `"$python" -m py_compile` passes for each `scripts/handover/*.py` file, and that each `tests/handover/test_*.py` file exits 0.

- [ ] **Step 2: Run it and make sure that it fails**

Run: `bash tests/test_handover_python.sh`
Expected: `FAIL`, because the modules do not exist.

- [ ] **Step 3: Create the three modules as the Files list says**

- [ ] **Step 4: Run the test and make sure that it passes**

Run: `bash tests/test_handover_python.sh`
Expected: `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add scripts/handover/*.py tests/handover tests/test_handover_python.sh
git commit -m "feat: move the handover Python helpers into wStack"
```

---

### Task 5: Port the four handover commands as wStack skills

**Files:**
- Create: `skills/init-org/SKILL.md` from `$OK/commands/handover-init-org.md`
- Create: `skills/init-service/SKILL.md` from `$OK/commands/handover-init-service.md`
- Create: `skills/create-handover/SKILL.md` from `$OK/commands/handover-new.md`
- Create: `skills/wrap-up-handovers/SKILL.md` from `$OK/commands/handover-wrap-up.md`
- Modify: `tests/test_skills.sh`
- Create: `evals/init-service-asks-row/prompt.md`, `evals/init-service-asks-row/graders/asks-before-writing.md`, and a fixture vault `tests/fixtures/handover-vault/01Project/Acme/handover_handler__initiation.md` with an empty Service Mapping table.

**Interfaces:**
- Consumes: the scripts from Tasks 2, 3, and 4, and `templates/initiation.md`.
- Produces: the user commands `/wstack:init-org`, `/wstack:init-service`, `/wstack:create-handover`, `/wstack:wrap-up-handovers`.

Port rules. Apply all of them to each file:

| Old text | New text |
| --- | --- |
| Frontmatter of the command | `name: <new name>`, the same `description:` with the new names, `disable-model-invocation: true` |
| The "Phase 0: Locate the vault" block (`resolve_via_handover`, `OBSIDIAN_KIT_VAULT`, the `settings.local.json` write) | Resolve the vault path as the first bullet of "Config" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/SKILL.md` says. If it is not set, ask the user for it and stop. Then run `export LIFEOS_ROOT="$vault"`. |
| `${CLAUDE_PLUGIN_ROOT}/lib/<name>.sh` | `${CLAUDE_PLUGIN_ROOT}/scripts/handover/<name>.sh` |
| `${CLAUDE_PLUGIN_ROOT}/lib/initiation-template.md` | `${CLAUDE_PLUGIN_ROOT}/templates/initiation.md` |
| A Python call with `sys.path.insert(0, '.../scripts')` | `PYTHONPATH="${CLAUDE_PLUGIN_ROOT}/scripts" python3 ...`, importing from `handover.*` |
| `plan_archive(path, vault, config)` | `plan_archive(path, vault)` |
| `/obsidian-kit:handover-init-org`, `-init-service`, `-new`, `-wrap-up` | `/wstack:init-org`, `/wstack:init-service`, `/wstack:create-handover`, `/wstack:wrap-up-handovers` |
| init-service Phase 7 (the `.gitignore` step) | Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/handover/ensure-exclude.sh" "$PWD"`. Report its output. |
| init-service Phase 8 line `.gitignore: handover (added \| already present)` | `Local exclude: handover (added \| already present)` |
| init-service rule about the `.gitignore` edit | The command never edits `.gitignore`. It writes `handover` to the local exclude file, which git never commits. |

- [ ] **Step 1: Extend `tests/test_skills.sh` and write the eval**

Set `expected_skills` to `build-review-page capture-evidence create-handover deliver-task init-org init-service run-retro start-task wrap-up-handovers`. Add these assertions:

```bash
for skill in create-handover init-org init-service run-retro start-task wrap-up-handovers; do
  assert "$skill is user-invoked" 'grep -qx "disable-model-invocation: true" "$repo_root/skills/$skill/SKILL.md"'
done
for skill in build-review-page capture-evidence deliver-task; do
  assert "$skill is a helper" 'grep -qx "user-invocable: false" "$repo_root/skills/$skill/SKILL.md"'
done
assert "no obsidian-kit names in skills" '! grep -rqE "obsidian-kit:|OBSIDIAN_KIT_|resolve_via_handover" "$repo_root/skills"'
assert "init-service uses the exclude script" 'grep -q "scripts/handover/ensure-exclude.sh" "$repo_root/skills/init-service/SKILL.md"'
```

The eval prompt does these steps:

1. Copy the fixture vault into the sandbox, and set `EVAL_WSTACK_VAULT_PATH` to it.
2. Make a git repository `demo` under the `workspace_root` of `Acme`.
3. Run `/wstack:init-service` in `demo`.

The grader has `type: llm` and `focus: trace`. To pass, the session resolves the org `Acme`, proposes the row `| demo | <repo path> | Services/demo |`, and asks before it writes. Before an answer, the session must not edit the initiation file, create `./handover`, or touch `.gitignore`. If it does, the grader fails.

- [ ] **Step 2: Run the test and make sure that it fails**

Run: `bash tests/test_skills.sh`
Expected: `FAIL` on `skill folders`.

- [ ] **Step 3: Write the four skills with the port rules**

- [ ] **Step 4: Run the tests and the eval, and make sure that they pass**

Run: `bash tests/test_skills.sh && bash tests/test_manifest.sh`
Expected: `Failed: 0` twice.
Run: `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID bash tests/run-evals.sh --case init-service-asks-row`
Expected: the grader passes.

- [ ] **Step 5: Commit**

```bash
bash tests/run-all.sh
git add skills tests/test_skills.sh evals/init-service-asks-row tests/fixtures/handover-vault
git commit -m "feat: add the handover commands to wStack"
```

---

### Task 6: Docs and version 0.2.0

**Files:**
- Modify: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (version `0.2.0`), `tests/test_manifest.sh` (the version assertion).
- Modify: `CHANGELOG.md`: add `## 0.2.0 - 2026-11-21` with the four renames (old name, then new name) and the four handover commands.
- Modify: `README.md`: list the six user commands. Add a "Handover" section with the content of the handover parts of `$OK/README.md`, changed to the new names and the local exclude file.
- Modify: `docs/spec.md` section 4 (plugin layout: the new skills, `scripts/handover/`, `templates/initiation.md`) and section 1.1.
- Modify: `CLAUDE.md`: the skill rules list all user commands and helpers. Add the script rule: Python scripts use only the standard library and run on Python 3.9.

- [ ] **Step 1: Change the version assertion in `tests/test_manifest.sh` to `0.2.0`, and run it**

Run: `bash tests/test_manifest.sh`
Expected: `FAIL` on `version is 0.2.0 in both`.

- [ ] **Step 2: Edit the files in the Files list**

- [ ] **Step 3: Run the tests and make sure that they pass**

Run: `bash tests/run-all.sh`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin tests/test_manifest.sh CHANGELOG.md README.md docs/spec.md CLAUDE.md
git commit -m "docs: document the renames and the handover commands for 0.2.0"
```

---

### Task 7: Pull request, merge, and install on this Mac

Every step here changes something outside the branch. Ask the user before each one.

- [ ] **Step 1: Ask the user for approval, then push the branch and create the pull request**

Write the body from `git diff main...HEAD` with a test plan, as `rules/git-workflow.md` says.

- [ ] **Step 2: Ask the user for approval, then merge**

Run: `gh pr merge <number> --merge`

- [ ] **Step 3: Ask the user for approval, then install wStack from its own marketplace**

Run: `claude plugin list` and make sure that `answer-me-with-html` is installed and enabled. Then run `claude plugin marketplace add /Users/william.hung/Projects/breakincode/wStack` and `claude plugin install wstack@<the name in .claude-plugin/marketplace.json>`. When Claude Code asks for `vault_path`, set it to `/Users/william.hung/Projects/LifeOS`.

- [ ] **Step 4: Make sure that the install works**

Run: `claude plugin list`
Expected: `wstack` at `0.2.0`, enabled. In a new session in the wStack repository, `/wstack:init-service` resolves `BreakinCode` and finds the mapped row `wstack`.
