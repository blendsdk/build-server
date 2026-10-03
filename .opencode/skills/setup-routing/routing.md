# Routing policy

CodeOps routing lives under the optional `routing` and `quality` fields in `codeops/codeops.json`.

```json
{
  "schema": 1,
  "mode": "strict",
  "artifacts": {"layout": "nested", "root": "codeops"},
  "quality": {
    "independentReview": true,
    "minimumReviewers": 1,
    "stopOnMajorFinding": true
  },
  "routing": {
    "maxConcurrentAgents": 4,
    "roles": {
      "explorer": {"effort": "medium"},
      "executor": {"effort": "high"},
      "correctness-reviewer": {"effort": "high", "sandbox": "read-only"},
      "security-auditor": {"effort": "high", "sandbox": "read-only"}
    }
  },
  "metrics": {"enabled": false}
}
```

Allowed effort values follow the active OpenCode release. Prefer `medium` for bounded reconnaissance, `high` for correctness/security review, and higher supported levels only for genuinely demanding semantic or architectural work.

Model pins are optional per role. When omitted, OpenCode resolves the model from the explicit spawn, project defaults, and parent session. A missing pin must never block the workflow.

Reviewer selection is driven by risk tags:

| Tag | Required role |
|---|---|
| `security` | security auditor |
| `financial-integrity` | financial-integrity auditor |
| `concurrency` | concurrency auditor |
| `performance-critical` | performance auditor |
| `compiler-semantics` | semantics reviewer |
| `migration` | migration/data-integrity reviewer |
| all non-trivial phases | correctness reviewer |

Multiple applicable tags produce a review team. Combine closely related lenses into one agent only when independence is not lost and the packet remains bounded.
