---
name: retro-requirements
description: >-
  Reverse-engineer an existing codebase into structured requirements. Use for
  "retro-requirements", "reverse requirements", "reconstruct requirements from
  code", "requirements archaeology", or "reverse-engineer this codebase". Trigger
  when the user wants to reconstruct requirements from an existing, undocumented,
  or legacy codebase — for documentation, migration, or a from-scratch rebuild —
  e.g. "document what this app does", "extract requirements from this code",
  "reverse-engineer this service into a spec". Analyzes any language/framework
  through a 9-phase archaeology pipeline and produces a reconstruction brief
  that feeds the make-requirements skill. Extracts WHAT the system does (not HOW),
  classifies every behavior by confidence (✅/⚠️/🔴), and enforces a hard
  Bug-or-Feature Triage Gate so bugs are never silently documented as features.
  Supports --scope PATH to analyze one module/package and --continue to resume
  an interrupted session.
---

# Reverse Requirements Engineering

> **CodeOps Artifact Schema**: 1

Analyze an existing codebase — any language, any framework — and produce a
structured **reconstruction brief** that can be fed to the make-requirements
skill to generate formal requirement documents capable of rebuilding the entire
application from scratch.

> **Resolve output paths layout-aware — ONCE, here.** Everything this skill writes lives in
> **the resolved `_retro/` dir**:
>
> - **Flat layout** (no marker): `requirements/_retro/`
> - **Nested layout** (marker present): `codeops/features/<f>/requirements/_retro/` — ask which
>   feature the reconstruction targets (create it lazily); never guess.
>
> Detection per **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)**.
> Every mention of the `_retro/` dir in this skill and its reference docs (`phases.md`,
> `triage-gate.md`) means THIS resolved path — including `_progress.md`, the triage register,
> and the reconstruction brief. `--continue` reads `_progress.md` from the same resolved
> location.

This skill is the **inverse** of the make-requirements skill and **upstream** of
the full forward pipeline:

```
Existing Codebase
   → retro-requirements              (THIS skill — reverse-engineer the code)
   → <resolved _retro dir>/09-reconstruction-brief.md
   → the make-requirements skill     (enrich, validate, formalize into RDs)
   → the make-plan skill             (implementation pipeline → rebuild)
```

## Core Principle: Requirements Archaeologist

You are a **systematic code archaeologist** who:

1. **Surveys** — maps the entire codebase structure before reading any implementation
2. **Excavates** — reads source methodically, layer by layer, extracting what the system does
3. **Reconstructs** — transforms code-level observations into requirement-level statements
4. **Catalogs** — organizes findings into structured documents with clear categories
5. **Synthesizes** — produces a reconstruction brief the make-requirements skill can consume

The output is NEVER a code summary or architecture diagram. It is a
**requirements-level description** of what the system does — written as if the
code didn't exist yet and someone needed to describe what to build.

**Implementation-agnostic (WHAT, not HOW).** A developer reading the brief must
be able to rebuild the same behavior in a completely different tech stack.

```
✅ "Registered users can reset their password by providing their email. The
    system sends a time-limited reset link (expires in 1 hour), usable once."
❌ "The resetPassword function in auth.service.ts calls sendEmail with a JWT
    token that has a 3600s expiry encoded using HS256."
```

---

## Step 0: Detect the Mode

| Signal | Action |
|--------|--------|
| `retro-requirements` (or "reverse-engineer this codebase") | Fresh start — full codebase. Begin at Phase 0. |
| `retro-requirements --scope <path>` | Fresh start, scoped to one module/package. See **Scope Control** below. |
| `retro-requirements --continue` | Resume an interrupted session. See **Session Management** below. |

At the start of any session, read the project's AGENTS.md (or detected project
conventions) for project-specific context before analyzing.

---

## The 9-Phase Pipeline

Full per-phase instructions and the output-document templates live in
**`phases.md`** — read it before executing each phase.

| Phase | Goal | Output file |
|-------|------|-------------|
| **0. Reconnaissance** | Establish what the project IS before reading source — manifests, deps, directory tree, project type | `00-project-profile.md` |
| **1. Structural Analysis** | Architecture — layers, modules, entry points, dependency direction, patterns | `01-architecture-analysis.md` |
| **2. Data Model** | Reconstruct entities, fields, relationships, constraints, lifecycle, enums, invariants | `02-domain-model.md` |
| **3. API Surface** | Every external interface — HTTP endpoints, CLI commands, public API, events | `03-api-surface.md` |
| **4. Behavior Catalog** | Translate code into requirement-level feature statements; classify each by confidence (✅/⚠️/🔴) | `04-behavior-catalog.md` |
| **5. Business Rules** | Extract domain/validation/authorization/lifecycle/temporal rules encoded in code | `05-business-rules.md` |
| **6. Cross-Cutting** | System-wide concerns — auth, errors, logging, caching, config, security, observability | `06-cross-cutting.md` |
| **7. Integrations** | Every external system the code talks to — DBs, APIs, queues, storage, providers | `07-integrations.md` |
| **8. Gaps & Debt** | What's missing, broken, or incomplete — TODOs, untested code, security gaps, debt | `08-gaps-and-debt.md` |
| **8B. 🚨 Triage Gate** | **HARD GATE** — resolve every non-Confirmed behavior with the user before synthesis | `08b-triage-register.md` |
| **9. Synthesis** | Combine all outputs into THE handoff file for the make-requirements skill | `09-reconstruction-brief.md` |

All output is written to the resolved `_retro/` dir. Session state lives in
`<resolved _retro dir>/_progress.md`. The **`09-reconstruction-brief.md`** is the
crown jewel — written specifically as make-requirements input; all other files
are intermediate analysis that feed it.

### Confidence Classification (Phase 4 onward) — NON-NEGOTIABLE

Every extracted feature and rule MUST carry a confidence level. This is the
structural safeguard against the **code-as-truth tautology** (treating bugs as
intended behavior).

| Confidence | Meaning |
|------------|---------|
| ✅ **Confirmed** | Clearly intentional — tests assert it, docs/comments describe it, or it follows an obvious domain convention |
| ⚠️ **Inferred** | Plausible and well-structured, but NO supporting evidence (the default) |
| 🔴 **Suspicious** | May be a bug masquerading as a feature — gaps, nearby TODOs, inconsistency, or violates a known standard |

The default is ⚠️ Inferred. Tests promote to ✅; missing tests NEVER confirm;
domain/standard violations flag 🔴 even when the code is clean. Every 🔴 item
becomes a mandatory user question at Phase 8B. Full rules in
**`confidence-classification.md`**.

---

## Phase 8B: Bug-or-Feature Triage Gate (summary)

**🚨 This gate is hard and non-negotiable. It MUST be passed before Phase 9. No
exceptions.** It breaks the code-as-truth tautology: without it, every bug
becomes a requirement, flows through the forward pipeline, and is faithfully
reproduced. Only the user has the external domain knowledge to tell bugs from
features.

**The flow (full protocol, register format, and example in `triage-gate.md`):**

1. After Phases 4–8, compile the **Triage Register** at
   `<resolved _retro dir>/08b-triage-register.md` — a formal inventory of ALL
   items that are NOT ✅ Confirmed (every 🔴 Suspicious and ⚠️ Inferred item),
   saved to disk before presenting to the user.
2. Present each 🔴 **Suspicious** item with *what the code does* and *why it's
   suspicious*, then ask the user to decide:
   - **(A) It's a bug** → exclude from the brief; move to `08-gaps-and-debt.md` "Known Bugs".
   - **(B) It's intentional** → include as a confirmed requirement; record the user's explanation.
   - **(C) I'm not sure** → include with a prominent ⚠️ flag AND add to "Open Questions for Discovery" so the make-requirements skill re-examines it.
3. Present ⚠️ **Inferred** items in batches (5–10) for quick confirm-or-flag.

**The gate opens ONLY when:** every 🔴 item has a decision (A/B/C); all ⚠️ items
have been presented; (A)-Bug items are moved to gaps; (C)-Unsure items are
flagged and added to Open Questions; and the register header reads
`✅ GATE PASSED`. While blocked, you MUST NOT write the brief, proceed to Phase 9,
or assume a suspicious behavior is intentional because the code is "clean".

> **Grounded Options & Recommendations (coding standards → Working style) apply here.** Before presenting options/findings/recommendations: filter out non-viable ones (no strawmen; ≥2 only when ≥2 are genuinely viable, else present the single viable path and name what was rejected), second-guess each, verify any code-modifying option against the actual current code (cite `file:line`), and lead with a recommendation backed by grounded reasoning. Match ceremony to stakes — the user decides. Apply the recommendation-hardening protocol (`_shared/recommendation-hardening.md`) to consequential recommendations; escalate to an independent challenger only when the decision is genuinely high-stakes.

---

## Scope Control: `--scope <path>`

For large codebases or monorepos, analyze a specific module
(e.g. `--scope src/auth`, `--scope packages/api`):

- Phase 0 still reads the root manifests (for global context).
- Phase 1 focuses on the scoped directory's structure.
- Phases 2–8 analyze only the scoped code.
- Phase 9 produces a scoped reconstruction brief.
- Cross-references to other modules are noted but not analyzed.

---

## Session Management (long analyses)

Analyzing a full codebase will span multiple turns or sessions. Work
incrementally and survive interruptions:

1. **Persist after each phase** — save the phase output to the resolved `_retro/` dir
   before moving on; never hold analysis only in conversation memory.
2. **Read selectively** — don't read every file. Read entry points, then follow
   imports into key modules. Summarize as you go; extract requirements, don't
   copy code.
3. **Track progress** — maintain `<resolved _retro dir>/_progress.md` (phase status
   + module coverage; template in `phases.md`).

**Save progress and resume natively:** if the session gets long or the user wants
to pause, save the current phase output (even if incomplete) plus the next-step
state to `<resolved _retro dir>/_progress.md`, note which module/file was
interrupted, and report what's done and what remains. The user resumes later with
`retro-requirements --continue`: read `_progress.md` and completed phase outputs,
summarize where you left off, then continue from the next incomplete phase.

A natural cadence: Session 1 = Phases 0–1; middle sessions = Phases 2–7 (one or
more per session by size); final session = Phases 8, 8B, 9.

---

## Adapting to Project Type

Tailor the analysis focus to the detected type: API/backend → Phases 2–5 heavy;
library/SDK or CLI → Phase 3 heavy (public surface, commands, exit codes); mobile
→ Phase 4 heavy (navigation, offline, push); microservices → Phase 7 heavy
(boundaries, inter-service comms, data ownership); monorepo → run per-package;
data pipeline → Phases 5 & 7 heavy; infrastructure → Phases 0 & 7 heavy. The full
mapping is in **`phases.md`**.

---

## Related Skills

- the make-requirements skill — consumes `09-reconstruction-brief.md` to produce formal RDs (downstream; this brief is its input)
- the make-plan skill — turns RDs into implementation plans (rebuild pipeline)
- your project's coding/testing standards (AGENTS.md) — code-quality and test patterns to reference while analyzing
