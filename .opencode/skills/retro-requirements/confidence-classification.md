# Confidence Classification — NON-NEGOTIABLE

Every feature extracted in Phase 4 and every rule extracted in Phase 5 MUST be
classified with a confidence level. This is a structural safeguard against the
**code-as-truth tautology** — the risk that bugs in the original code are
documented as intended behavior and faithfully reproduced in a rebuild.

The classification produced here is what feeds the Phase 8B Bug-or-Feature Triage
Gate (`triage-gate.md`): every item that is not ✅ Confirmed becomes a triage
register entry.

## The Three Levels

| Confidence | Icon | Meaning | Evidence Required |
|------------|------|---------|-------------------|
| **Confirmed** | ✅ | Behavior is clearly intentional | Tests assert this behavior, OR documentation/comments describe it, OR it follows an obvious domain convention |
| **Inferred** | ⚠️ | Behavior appears intentional but has no supporting evidence | No tests, no comments, no documentation — but the code is well-structured and the behavior is plausible |
| **Suspicious** | 🔴 | Behavior may be a bug masquerading as a feature | Code has error-handling gaps, TODOs near it, inconsistency with other parts, violates common patterns/standards, or produces results that seem wrong for the domain |

## Rules for Classification

1. **Default is ⚠️ Inferred** — a feature starts as Inferred unless evidence
   promotes it to ✅ Confirmed or red flags demote it to 🔴 Suspicious.
2. **Tests promote confidence** — if a test explicitly asserts the behavior, it
   is ✅ Confirmed (the original developer intended it).
3. **Missing tests do NOT confirm** — untested behavior is NEVER ✅ Confirmed,
   no matter how clean the code looks.
4. **Domain violations flag suspicion** — if the behavior violates a well-known
   standard (RFC, industry convention, common protocol) or your project's
   coding/testing standards (AGENTS.md), it is 🔴 Suspicious even if the code is
   clean.
5. **Every 🔴 Suspicious item becomes a mandatory user question** at Phase 8B.
   Every ⚠️ Inferred item is presented for batch confirmation. Only ✅ Confirmed
   items bypass triage.

## How Confidence Flows Through the Pipeline

- **Phase 4 / 5:** annotate each feature and rule with `Confidence: ✅ / ⚠️ / 🔴`
  plus a one-line justification (what evidence promoted it, or what red flag
  demoted it).
- **Phase 8B:** all non-✅ items are compiled into the Triage Register and
  resolved with the user (A = bug/exclude, B = feature/include, C = unsure/flag).
- **Phase 9:** the Feature Catalog and Business Rules tables in the reconstruction
  brief MUST carry the Confidence column so the make-requirements skill inherits
  the same calibration.
