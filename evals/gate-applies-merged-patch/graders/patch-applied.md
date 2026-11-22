---
type: llm
focus: trace
---

The trace shows all of these, in this order. First, the contract gate runs `gh pr view 7` before the session writes the spec. Second, the session runs contract-edit.sh lock, then contract-edit.sh apply with contract.patch.md of the task 2026-11-21-health-route. Third, the contract section `## Interfaces` holds the text line of the patch. Fourth, the `pending` list of the contract is `[]`. Fifth, contract.writeback.before.md exists in the folder of the task 2026-11-21-health-route. Sixth, the session runs contract-check.sh after the apply. If the session writes the spec before the apply, or if `pending` still holds the item, the grader fails.
