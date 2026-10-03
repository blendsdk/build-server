# Preflight — Report Format, Presentation & Persistence (detail)

> **CodeOps Artifact Schema**: 1

Covers Steps 4-8 of the protocol: compiling the report, presenting findings and collecting
decisions, pass/fail determination, applying fixes, and roadmap sync — plus iterative re-scan
numbering, report persistence, and same-agent-bias safeguards.

## Step 4: Compile the Preflight Report

Every finding gets a numbered, structured entry.

### Finding template

```markdown
### PF-[NNN]: [Finding Title] [severity-icon] [SEVERITY]

**Dimension:** [Which of the 13 dimensions]
**Location:** [File path + section/line reference in the artifact]
**Codebase Evidence:** [File path + line reference in the actual code, if applicable]
**The Problem:** [Clear, specific description of what's wrong and WHY it matters]

**Options:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | [Description] | [Pros] | [Cons] |
| B | [Description] | [Pros] | [Cons] |
| C | [Description] | [Pros] | [Cons] |

**Recommendation:** Option [X] — [concise rationale]

**User Decision:** Pending
```

**Rules for findings:**

- **Options must be genuinely viable, never strawmen** — present ≥2 options only when ≥2 are
  genuinely viable. When one resolution clearly dominates, present it alone, state it is the only
  viable one, and name what you considered and dropped and why. Never pad to a count to manufacture
  a choice.
- **Every finding MUST have a recommendation, with rationale** — never just "Option B is better".
- **High-stakes findings (CRITICAL/MAJOR) get the hardening challenger — ONE per preflight scan,
  not one per finding.** Per `_shared/recommendation-hardening.md` (challenger budget): spawn a
  single challenger that receives the whole CRITICAL/MAJOR finding batch (statement + surviving
  options per finding, without your picks) PLUS the scan's Codebase Context summary, and returns
  per-finding verdicts to reconcile *before* recording recommendations. Hard cap: 2 challenger
  spawns per scan. Close findings with the `Confidence:` / `Hardening:` disclosure where that
  protocol requires it (Med/Low confidence, changed pick, or high stakes — presentation-only,
  not a required saved field).
- **Complexity escalations use the shared visible stop packet, not the ordinary compact finding
  presentation.** Include and persist every approval-evidence field from the shared gate: original
  goal, named extra system or support code, why it may be needed, codebase evidence, smallest
  solution that still works, extra cost, independent verdict, and direct user decision. The larger
  option remains blocked until the user explicitly chooses to approve that named machinery.
  Generic finding acceptance does not approve it. The `PF-*` finding is the durable owner at
  preflight.
- **Findings are numbered sequentially by root cause** — `PF-001`, `PF-002`, ... A reopened root
  cause retains its identifier across iterations; a new root cause gets the next unused number.
- **Location must be specific** — "plans/my-feature/03-api-design.md, section 'Error Handling'", not
  "somewhere in the plan".
- **Codebase Evidence is required** for findings in dimensions 2, 4, 5, 6, 11, and 13 — cite the
  actual file and code. For other dimensions, include it when relevant. If you can't verify a claim
  against the code, say so: "Unable to verify against the codebase; this finding is based on the
  document alone."

### Report header template

```markdown
## Preflight Report: [Artifact Name]

> **Status**: REVIEW IN PROGRESS — [X] findings ([C] critical, [M] major, [m] minor, [O] observation)
> **Iteration**: [N] (first scan / re-scan after fixes)
> **Artifact**: [type] at [path]
> **Codebase Grounded**: [N] source files examined, [M] references verified
> **Last Updated**: [Date]

### Codebase Context Summary

**Tech Stack:** [actual stack from manifest]
**Architecture:** [brief architecture description from code examination]
**Key Files Examined:** [list of most relevant files read during reconnaissance]

### Summary by Dimension

| # | Dimension | Findings | Highest Severity |
|---|-----------|----------|-----------------|
| 1 | Ambiguities | [count] | [icon] |
| 2 | Implicit Assumptions | [count] | [icon] |
| ... | ... | ... | ... |
| 13 | Codebase Alignment | [count] | [icon] |

### Summary by Severity

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | [N] | [all resolved? / X pending] |
| MAJOR | [N] | [all resolved? / X pending] |
| MINOR | [N] | [all resolved? / X pending] |
| OBSERVATION | [N] | [all resolved? / X pending] |

---

[Individual findings follow]
```

Use the severity icons from SKILL.md (red/orange/yellow/blue circles) in the actual report.

## Step 5: Present findings and collect decisions

1. **Present grouped by severity** — CRITICAL first, then MAJOR, MINOR, OBSERVATION.
2. **Present per the batch rules below** (they are authoritative for pacing) — each finding shown
   with problem, options, recommendation.
3. **Collect and record authority for every finding** before the report is final. In normal mode
   use `**User Decision:** [their choice]`. With active auto-design, an eligible technical
   resolution uses the canonical delegated marker and complete provenance from
   `_shared/auto-design.md`; reserved decisions still use `**User Decision:**`. A delegated
   resolution does not authorize applying the fix or waiving a finding.
4. **Keep scope authority separate.** Finding resolution and expansion authorization are separate.
   If an explored remediation exceeds the confirmed product scope, link the finding to its `SE-*`
   proposal and collect a distinct `Keep`, `Defer`, or `Discard` ruling. In strict scope, optional
   remediations are not reported.

### Batch presentation rules

- **<= 5 findings** — present all at once, let the user respond to each.
- **6-15 findings** — present by severity group (all criticals, then all majors, etc.).
- **> 15 findings** — present in batches of 5-8, grouped by severity, wait for confirmation between batches.

**Previous decisions are respected (hard rule).** A finding that duplicates a decision already
recorded in the artifact's Ambiguity Register — including a named `⏸ Deferred` row — is NOT
re-presented for decision: record it as `Accepted Risk — deferred per AR #N` (or cross-reference
the resolving AR #) and move on. Re-litigating decisions the user already made is a protocol
violation, not thoroughness.

**Complexity exception:** a deferred complexity decision is accepted risk only when the larger
machinery is absent from the audited executable artifact. If it remains present, keep the finding
open at 🟠 MAJOR until the artifact is changed and rechecked. Do not ask the user to decide the
same deferral again.

### Agent behavior during resolution

| User says | Agent response |
|---|---|
| "Fix it per your recommendation" | Record `Resolved — User accepted recommendation: [Option X]`. Valid. |
| "Go with Option A" | Record `Resolved — User chose Option A`. |
| "This isn't actually an issue" | Record `Dismissed — User: "[reasoning]"`. Valid — only the user can dismiss. |
| "I'll fix this later" | Ask to record as a known accepted risk (won't block the pass but noted). If yes: `Accepted Risk — User deferred: "[reason]"` — the preflight face of the shared `⏸ Deferred` status (`_shared/zero-ambiguity-gate.md`); name the decision, owner, and revisit-trigger in the reason. For extra complexity, this applies only after the machinery is removed from the executable artifact and rechecked. |
| "You decide" | "I've given my recommendation above. Confirm you'd like Option [X]?" — user MUST explicitly confirm. |

For a complexity escalation, explicit approval of the named larger machinery resolves the finding
without an artifact edit. Choosing the smaller solution, revising, or deferring the larger
machinery keeps the finding blocked until the artifact is changed and rechecked. If the required
challenger is unavailable, the finding stays blocked.

## Step 6: Determine pass/fail

See the Pass tiers table in SKILL.md. A clean first-scan pass is a valid outcome — never invent
findings to justify the review.

## Step 7: Apply fixes (only if requested)

The user may ask the agent to apply fixes:

- **"Apply all fixes"** — modify the artifact documents per the resolved in-scope findings and
  any linked proposals already ruled `Keep`; this does not authorize undecided, deferred, or
  discarded `SE-*` entries.
- **"Apply fixes for PF-003 and PF-007"** — apply specific fixes only.
- **"I'll fix them myself"** — do nothing; the report is a checklist.
- **"Apply fixes and re-scan"** — apply, then immediately run another iteration.

> The agent MUST NOT apply fixes without explicit instruction. Preflight is a **review** protocol,
> not a **modification** protocol. Finding issues and fixing issues are separate steps.
> A fix instruction is also not scope-expansion authority; apply
> `_shared/scope-expansion-control.md` before editing.

## Step 8: Roadmap sync

After a preflight **pass**, sync the roadmap via the roadmap skill if one is in play:

- **If `plans/00-roadmap.md` exists:** advance the audited target's row —
  - an **RD** that passed → stage `RD Preflighted`
  - a **plan** that passed → stage `Plan Preflighted`

  Update the row's `Stage`, `Status`, and `Last Updated` (update-first mandate).
- **If `plans/00-roadmap.md` does NOT exist:** these hooks are inert — no error, no auto-creation.

A BLOCKED outcome does NOT advance the roadmap. See the roadmap skill for the full protocol.

## Iterative re-scanning

### How iterations work

1. **Iteration 1** — full 13-dimension scan of the original artifact (with full reconnaissance).
2. **Fixes applied** — user resolves findings (manually or via "apply fixes").
3. **Iteration 2** — re-scan focusing on: **verify fixes** (each resolved finding actually fixed),
   **regression check** (fixes introduced no new issues), **bounded fresh scan** (re-examine all 13
   within the unchanged audit target), and **codebase re-check** (re-verify changed references).
4. **Iteration 3, only when blocking defects remain** — inspect the unresolved 🔴/🟠 fixes and their
   direct dependency surface. Do not restart broad discovery.
5. **Iteration 4+** — never automatic. Recommend a fresh-session audit to counter accumulated
   framing bias, or obtain an explicit user decision to continue the current session.

### Re-scan numbering

Finding identifiers name root causes, not scan appearances:

- a verified fix closes its existing `PF-NNN`;
- a partial fix, residual contradiction, or regression with the same root cause reopens that
  `PF-NNN` and adds an `Iteration N evidence` note;
- a genuinely independent root cause receives the next unused number; and
- merged or split symptoms retain a `Related findings` link so the audit trail stays navigable.

Do not relabel a residual form of an old defect as a new finding merely to keep numbering
continuous.

### Re-scan report header

```markdown
## Preflight Report: [Artifact Name] — Iteration [N]

> **Status**: [status]
> **Previous Iteration**: [X] findings — [all resolved / Y carried forward]
> **This Iteration**: [Z] new findings
> **Carried Forward**: [list of PF-### still open from previous iterations]
```

### Convergence

Use severity and decision state, not the desire for a zero-finding scan:

| State after verification | Result |
|---|---|
| Any unresolved 🔴/🟠 | **Blocked**; a bounded corrective rescan is allowed |
| No unresolved 🔴/🟠; one or more 🟡 pending | Collect decisions; do not rescan yet |
| No unresolved 🔴/🟠; all remaining 🟡 explicitly accepted | **Passed With Notes**; stop |
| Only 🔵 observations remain | **Passed With Notes**; stop unless the user requests fixes |
| No findings remain | **Passed — Clean**; stop |
| User stops with unresolved 🔴/🟠 | **Blocked**; record the stop without advancing the roadmap |

Applying an accepted minor or observation does not by itself justify another full scan. Verify that
edit directly; run another bounded scan only when the edit changes behavior, ownership, dependency
ordering, security, compatibility, or another consequential contract.

Before plan creation or execution consumes a passed artifact, compare its current git blob (or
content hash when it is uncommitted) with the revision recorded by preflight. A mismatch makes the
pass stale and requires a targeted re-check of the changed sections; it does not silently trigger a
set-wide audit.

## Report persistence

Save the report alongside the artifact (locations in SKILL.md). It is a permanent audit trail.

### Relationship to the Ambiguity Register

Separate documents with different purposes:

| Document | Created by | Purpose | Contains |
|---|---|---|---|
| **Ambiguity Register** (`00-ambiguity-register.md`) | make-plan / make-requirements skills | Track decisions made DURING creation | User decisions on design choices |
| **Preflight Report** (`00-preflight-report.md`) | preflight | Track issues found DURING review | Post-creation defects, gaps, codebase misalignments, and resolutions |

When a finding relates to an existing Ambiguity Register entry, cross-reference it:

```markdown
**Related:** AR #7 decided on JWT auth, but this finding identifies a gap
in the token refresh flow that AR #7 didn't cover.
```

Do not re-litigate an Ambiguity Register decision unless new information invalidates it — reference
the AR entry and explain what changed.

## Same-agent bias awareness — NON-NEGOTIABLE

When the same model created the artifact and reviews it, systematic blind spots are likely — shared
training biases, knowledge gaps, and reasoning patterns. A bug missed during creation is exactly
the kind of bug that will be missed during review. Structural safeguards:

1. **Fresh context required** — if the artifact was created in the CURRENT session, note it at the
   top of the report:
   ```
   SAME-SESSION REVIEW: This artifact was created in the current session.
   Same-agent bias risk is elevated. Consider running preflight in a new session
   for maximum review independence.
   ```
2. **Standard-first checking** — for any behavior that must conform to an external standard (RFC,
   protocol, spec, regulation), verify by **citing the specific standard text**, not from memory.
   If you can't cite it, flag the limitation:
   ```
   Unable to verify conformance with [standard] — agent does not have
   access to the full standard text. Flag for human review.
   ```
3. **Adversarial question checklist** — before concluding the scan, ask yourself:
   - "What assumption did I make during creation that I might be unconsciously confirming now?"
   - "What external standard or convention might this violate that I'm not aware of?"
   - "What would a domain expert who disagrees with my approach flag as wrong?"
   If any surface concerns, add them as observation findings.
4. **User recommendation** — if the artifact is high-stakes (security/compliance/architecturally
   foundational), recommend: "Consider having a human domain expert review this in addition to
   the automated preflight."
