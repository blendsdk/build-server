# Phase 8B: Bug-or-Feature Triage Gate — 🚨 NON-NEGOTIABLE HARD GATE 🚨

> **This gate MUST be passed before Phase 9 (Synthesis). There are NO
> exceptions.** It is the structural safeguard against the code-as-truth
> tautology — the single most dangerous pattern in reverse requirements
> engineering.

## Why This Gate Exists

When an agent reads code and writes requirements from it, **every bug becomes a
requirement**. The agent has no way to distinguish intentional behavior from
accidental behavior — it can only observe what the code does. Without this gate,
bugs are faithfully documented as features, passed through the make-requirements
skill, planned via the make-plan skill, implemented, and tested with spec tests
that validate the buggy behavior. The entire forward pipeline passes clean, and
the bugs are reproduced with full confidence.

**This gate breaks the tautology** by forcing every uncertain or suspicious
behavior to be presented to the user — the only entity with external domain
knowledge able to distinguish bugs from features.

---

## 8B.1 Compile the Triage Register

After Phases 4–8 are complete, compile a **Triage Register**: a formal inventory
of ALL items that are NOT ✅ Confirmed (every 🔴 Suspicious and ⚠️ Inferred item
from the Phase 4 behavior catalog and Phase 5 business rules).

Save it to disk **before** presenting to the user (see 8B.4 Persistence).

```markdown
# Bug-or-Feature Triage Register: [Project Name]

> Status: ❌ GATE BLOCKED — [X] items unresolved
> Last Updated: [Date]

## 🔴 Suspicious Items (MANDATORY — must be resolved before synthesis)

| # | Source | Item | What the Code Does | Why It's Suspicious | User Decision | Status |
|---|--------|------|--------------------|---------------------|---------------|--------|
| T-001 | Phase 4: [CAT]-03 | [Feature title] | [Observed behavior] | [Why this might be a bug] | — | ❌ Open |
| T-002 | Phase 5: BR-DOM-02 | [Rule title] | [What the rule enforces] | [Why this might be wrong] | — | ❌ Open |

## ⚠️ Inferred Items (RECOMMENDED — user should confirm or flag)

| # | Source | Item | What the Code Does | Confidence Notes | User Decision | Status |
|---|--------|------|--------------------|------------------|---------------|--------|
| T-010 | Phase 4: [CAT]-07 | [Feature title] | [Observed behavior] | [Why confidence is only Inferred] | — | ❌ Open |
```

---

## 8B.2 Present to User for Triage

**🔴 Suspicious items** — present each one with:

1. **What the code does** — a factual description of the observed behavior.
2. **Why it's suspicious** — the standard, convention, or domain expectation it
   appears to violate.
3. **Options:**
   - **(A) It's a bug** — do NOT include in the reconstruction brief; add it to
     `08-gaps-and-debt.md` → "Known Bugs" instead.
   - **(B) It's intentional** — include in the brief as a confirmed requirement;
     record the user's explanation.
   - **(C) I'm not sure** — include in the brief with a prominent ⚠️ flag AND add
     it to "Open Questions for Discovery" so the make-requirements skill
     re-examines it.

**⚠️ Inferred items** — present in batches (5–10 at a time) for quicker
confirmation:

- *"These behaviors appear intentional but have no test coverage or
  documentation. Please scan and flag any that look wrong."*
- The user can confirm the batch ("all look fine") or flag individual items for
  deeper review.

Record each decision in the register's **User Decision** column and update each
row's **Status** to ✅ Resolved.

---

## 8B.3 Gate Rules

**🚫 ABSOLUTELY PROHIBITED while the gate is blocked:**

- ❌ Write the reconstruction brief (`09-reconstruction-brief.md`)
- ❌ Proceed to Phase 9
- ❌ Include any 🔴 Suspicious item as a confirmed requirement
- ❌ Assume a suspicious behavior is intentional because the code is "clean"

**✅ The gate opens ONLY when ALL of these are met:**

1. ✅ Every 🔴 Suspicious item has a user decision (A, B, or C).
2. ✅ All ⚠️ Inferred items have been presented (batch confirmation is fine).
3. ✅ Items decided **(A) Bug** have been moved to `08-gaps-and-debt.md` →
   "Known Bugs".
4. ✅ Items decided **(C) Unsure** are flagged in the brief AND added to Open
   Questions.
5. ✅ The register header has been updated to `✅ GATE PASSED`.

---

## 8B.4 Register Persistence

The Triage Register is a permanent artifact:

- **Location:** `<resolved _retro dir>/08b-triage-register.md` (resolution rule in SKILL.md)
- **Purpose:** audit trail — every behavior classification is traceable to a user
  decision.
- **Survives interruptions:** written to disk before the user is asked anything,
  and updated after each decision.

---

## 8B.5 Worked Example

```
T-003 | Phase 6: Auth | OIDC Discovery Endpoint

What the code does:
  The OIDC discovery endpoint returns { issuer: "https://example.com" }
  without including the organization path segment.

Why it's suspicious:
  RFC 8414 §2 requires the issuer value to exactly match the URL the client
  used to retrieve the discovery document. If clients access the endpoint at
  https://example.com/org-slug/.well-known/openid-configuration, the issuer
  MUST be https://example.com/org-slug — not the bare base URL.

Options:
  (A) Bug         — omit from requirements, add to gaps
  (B) Intentional — single-tenant deployment, no org path needed
  (C) Unsure      — flag for make-requirements discovery
```
