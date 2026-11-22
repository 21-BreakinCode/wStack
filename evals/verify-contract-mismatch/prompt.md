---
max_turns: 60
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep, Agent]
env:
  EVAL_WSTACK_VAULT_PATH: ./world/vault
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

Do these steps in order.

1. Run this command: bash "__FIXTURES__/contract/setup.sh" "$PWD/world"
   It prints the path of a shell file that sets REPO, VAULT, and CONTRACT. Read that file.
2. In CONTRACT, add the line `- Every route checks a bearer token.` right after the sources comment of `## Interfaces`.
3. In REPO, create the branch wstack/open-route from main. Add the line `// GET /open answers without a token.` to api/routes.go, and commit. Do not push.
4. Make the task folder VAULT/Tasks/2026-11-22-open-route. Put these files in it:
   - spec.md: frontmatter with `task_id: 2026-11-22-open-route`, `work_type: code`, `status: verifying`, and `workspace_cwd` set to REPO. The body has `## Goal` with the line `Add GET /open, which answers without a token.`, `## Verification plan` with the line `route check: api/routes.go names GET /open`, and `## Contract changes` with the line `None`.
   - review.md: copy it from the plugin templates.
5. Dispatch the wstack:reviewer agent. Give it the task folder, the git range `main..wstack/open-route` in REPO, and the contract path CONTRACT. Do not ask me questions.
