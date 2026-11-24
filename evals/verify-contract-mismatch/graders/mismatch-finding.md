---
type: llm
focus: trace
---

The trace shows all of these. First, the session dispatches the reviewer agent with the contract path. Second, review.md in the task folder holds a finding block whose heading names the kind contract-mismatch and blocking:yes. Third, that finding points to api/routes.go and names the interfaces claim that every route checks a bearer token. Fourth, blocking_findings in the review.md frontmatter is 1 or more. If review.md holds no contract-mismatch finding, the grader fails.
