---
task_id: 2026-11-18-add-is-adult
work_type: code
repo: demo
mobile: false
status: verifying
workspace_cwd:
approved_at: 2026-11-18T00:00:00Z
created_at: 2026-11-18T00:00:00Z
---

## Goal
Add `is_adult(age)` in `age.sh`. It returns true for age 18 and above.

## Scope
In: `age.sh`. Out: anything else.

## Verification plan
Check: `is_adult 30` succeeds. Pass rule: exit code 0. Evidence: the exit code.

## Non-undoable steps
None.

## Deliver targets
- pull request
