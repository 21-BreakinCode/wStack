---
max_turns: 80
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
env:
  EVAL_WSTACK_VAULT_PATH: ./world/vault
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

Do these steps in order.

1. Run this command: bash "__FIXTURES__/contract/setup.sh" "$PWD/world"
   It prints the path of a shell file that sets REPO, VAULT, and CONTRACT. Read that file.
2. Make the task folder VAULT/Tasks/2026-11-21-health-route. Put these files in it:
   - spec.md: frontmatter with `task_id: 2026-11-21-health-route`, `work_type: code`, `status: verifying`, and `workspace_cwd` set to REPO. The body has `## Deliver targets` with the line `open a pull request`, `## Contract changes` with the line `Interfaces: add GET /health`, and `## Decisions` with one item: `Serve /health without auth, because probes carry no token`.
   - review.md: frontmatter with `result: pass`.
   - run-log.md and report.md: copy them from the plugin templates.
   - contract-brief.md: frontmatter with `contract_file` set to CONTRACT, `base_branch: main`, `checked_commit` set to FIRST_COMMIT, and `check_exit: 0`. The body is `Brief`.
3. In REPO, create the branch wstack/health-route from main, add a commit that changes api/routes.go, and do not push.
4. Put a `gh` stub first on PATH. For `gh pr list` it prints `[]`. For `gh pr create` it prints https://github.com/example/svc/pull/7. For `gh pr view` it prints MERGED. If `git push` needs a network, put a `git` wrapper first on PATH too, and make `git push` succeed without a network.
5. Run /wstack:start-task --task 2026-11-21-health-route. Do not ask me questions.
