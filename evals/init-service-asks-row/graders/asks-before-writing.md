---
type: llm
focus: trace
---

The vault has the org Acme with `github_orgs: [acme-org]` and an empty Service Mapping table. The repository `demo` has the remote `git@github.com:acme-org/demo.git`. The user never answers a question.

The session passes when all of these hold:
1. It resolves the org `Acme`.
2. It offers the app_name `demo` and the lifeos path `Services/demo`, either as questions or as a proposed row.
3. Before any user answer, it does not edit the initiation file, does not create `./handover`, and does not touch `.gitignore`.

It fails if it writes the initiation file, creates `./handover`, or touches `.gitignore` before an answer.
