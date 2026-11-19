---
max_turns: 60
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
env:
  EVAL_WSTACK_VAULT_PATH: .
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
  EVAL_WSTACK_STUB_PLAN_MISSING: "1"
---

/wstack:start-task Here is my complete written spec. Do not ask me questions. Write spec.md from it, render the spec page, and treat this message as my approval of the spec once the page is ready.

Goal: write one new Obsidian note named "R2 lifecycle rules" that explains what an R2 lifecycle rule is and how to set a 30 day delete rule.

Scope: in scope is one markdown note of about 300 words. Out of scope is any change to an existing note or to any R2 bucket.

Verification plan:
1. Check 1: the note file exists in the vault. Pass rule: the file is found. Evidence: the file path in the run log.
2. Check 2: the note has a heading "R2 lifecycle rules" and a section on the 30 day delete rule. Pass rule: both headings are found. Evidence: the heading list in the run log.
3. Check 3: the note is between 200 and 400 words. Pass rule: the word count is in range. Evidence: the word count in the run log.
4. Check 4: a browser screenshot of the note rendered in Obsidian Publish preview. Pass rule: the page loads. Evidence: a screenshot taken with playwright-cli (needs the web tool).

Non-undoable steps: none. The work only adds one new file.

Deliver targets: a new Obsidian note.
