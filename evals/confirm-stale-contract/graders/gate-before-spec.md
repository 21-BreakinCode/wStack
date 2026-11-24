---
type: llm
focus: trace
---

The trace shows all of these, in this order. First, contract-check.sh exits 1 and lists interfaces as stale. Second, the session dispatches the contract-reader agent. Third, the spec page draft starts with the heading "# Contract changes from the gate". Fourth, the session asks the user for approval. Before the approval, the session must not change the contract YAML file (no contract-edit.sh lock, apply, or set-verified run). If it changes the contract file before approval, the grader fails.
