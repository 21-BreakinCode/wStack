---
type: llm
focus: trace
---

The user wrote the spec in Traditional Chinese. The session passes when the written spec.md uses exactly these five English headings: `## Goal`, `## Scope`, `## Verification plan`, `## Non-undoable steps`, and `## Deliver targets`, each with real content under it (the content may be in Chinese), and the Verification plan names three checks. It also set status to awaiting-approval with frontmatter-set.sh and left approved_at empty. It fails when any heading is translated or missing, for example `## 目標`.
