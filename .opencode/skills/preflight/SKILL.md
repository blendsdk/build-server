---
name: preflight
description: >-
  Runs a rigorous multi-dimensional quality audit of a plan, requirements, or any artifact,
  grounded in the actual codebase. Use for "preflight", "quality audit", "review gate",
  "audit this plan", "audit these requirements", or "review my plan/requirements before I build it".
  An adversarial review gate that hunts for every ambiguity, contradiction, gap, and risk, verifies
  every claim against the real code, scores findings on a 13-dimension scan, and presents each one
  with options and a recommendation for the user to decide — it never fixes silently. Takes an
  artifact target (e.g. requirements, requirements RD-03, a feature name, a feature design document,
  or a file/dir path) plus optional --continue to resume an interrupted session.
---

# preflight — Multi-Dimensional, Codebase-Grounded Quality Audit

> **CodeOps Artifact Schema**: 1

## Auto-design option

If `$ARGUMENTS` contains exactly one exact standalone `--auto-design` token before the first `--` sentinel, remove it before resolving targets, paths, or modes; zero occurrences means normal mode, more than one is invalid, and tokens at or after the sentinel are target content; announce `Auto-design active — eligible technical decisions are
delegated and recorded`; then read and apply
[../../_shared/auto-design.md](../../_shared/auto-design.md). Select the strongest eligible
remediation under that policy, but apply it only when the user already authorized fixes; never
auto-waive risk or dismiss a critical/major finding. Propagate only to explicitly invoked supported
children; an unsupported child fails closed. This mode does not grant action permission or scope
expansion. **Normal mode:** without the exact token, every material ruling still requires an
explicit user decision; historical delegated records must not infer delegated authority.

## Scope exploration option

If `$ARGUMENTS` contains exactly one exact standalone `--explore-scope` token before the first `--` sentinel, remove it before resolving targets, paths, or modes; zero occurrences means strict scope, more than one is invalid, and tokens at or after the sentinel are target content; announce `Scope exploration active — optional additions will be proposed for your decision`; then read and apply
[../../_shared/scope-expansion-control.md](../../_shared/scope-expansion-control.md). Strict scope is the default:
do not report optional additions as findings or suggestions. Exploration records them
as separate `SE-*` proposals; finding resolution never chooses `Keep`.

Run a rigorous quality audit of the artifact named in `$ARGUMENTS`, **grounded in the actual
codebase**. Find every issue, ambiguity, contradiction, gap, and risk; verify every claim and
assumption against the real code; present each finding with options + a recommendation; iterate
until the artifact passes clean.

Begin with direct artifact checks: resolve the exact artifact named by the user, confirm required
documents and links exist, confirm material ambiguities are closed, and for a plan confirm its
specification-first ordering. Related artifacts may supply review context, but the declared target
is the modification set: a sibling issue is contextual unless the user explicitly expands that
set. Report structural failures alongside, but never as substitutes for, the semantic audit.
Deterministic checks own identifiers, links, statuses, and coverage shape; reviewers own truth,
completeness, consistency, feasibility, and risk. A pass still requires every critical/major
finding resolved and every remaining minor finding explicitly accepted.

Read [../../references/domains/selection.md](../../references/domains/selection.md), verify the artifact selected all applicable domain lenses, and add one audit cluster per selected lens. A generic security or feasibility pass does not substitute for compiler semantics, financial integrity, concurrency, or migration analysis.

> **Resolve artifact paths layout-aware.** A requirements set or plan named in `$ARGUMENTS` lives at
> a flat path (`requirements/`, `plans/<feature>/`) or, in a nested-layout repo, under
> `codeops/features/<f>/…` — resolve it via **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)**.
> If the target feature is ambiguous in a nested repo, ask; never guess.

`preflight --continue` resumes an interrupted session (see [Session resume](#session-resume)).

## Artifact reference formats

| User types | What gets reviewed |
|---|---|
| `preflight requirements` | All requirement docs in `requirements/` |
| `preflight requirements RD-03` | A specific requirement doc |
| `preflight <feature-name>` | All plan docs in `plans/<feature-name>/` |
| `preflight <feature-name> 03-api-design` | A specific plan doc |
| `preflight <path>` | Any ad-hoc file or directory |

## Audit scope contract

Preflight distinguishes the **audit target** from the material read to understand it:

| Term | Meaning |
|---|---|
| **Audit target** | The exact file or directory selected by the user. Findings and the pass verdict apply only to this artifact. |
| **Context document** | A related artifact read to verify dependencies, ownership, terminology, or consistency. Reading it does not add it to the audit target. |
| **Modification set** | The files the user has explicitly authorized preflight to change after accepting findings. |

At the start of the report and every dispatch packet, record the audit target and list any context
documents separately. For a single-document audit:

- scan all 13 dimensions against the selected document;
- read directly related documents when needed to test its claims;
- locate findings in the selected document, citing context documents as evidence;
- do not report unrelated defects found only in context documents; offer a separate audit instead;
- do not treat a context document as passed or advance its roadmap row; and
- do not modify a context document unless the accepted resolution requires it **and** the user
  confirms the exact expanded modification set.

If resolving a finding would turn a single-document audit into a set-wide redesign, pause before
applying fixes and offer either a target-local resolution or an explicit set-level audit. Never
expand the audit target merely because the user said "apply fixes and re-scan."

Freeze the authorized product-scope baseline as well as the audit target. Existing out-of-scope
content in the target is still a scope-creep defect. A newly imagined optional remediation is
silent in strict scope or a separate `SE-*` proposal in exploration mode; it never affects the
finding count or verdict until the user keeps it.

## Core directive

> **You are a senior technical reviewer performing a formal quality audit GROUNDED IN THE ACTUAL
> CODEBASE. Find every defect, gap, ambiguity, contradiction, and risk in this artifact — and
> verify every claim, reference, and assumption against the real code. Be thorough, systematic,
> relentless. For every issue, analyze the options and present your recommended resolution. Never
> fix anything silently. In normal mode, every finding must be presented to the user for
> decision. With active auto-design, eligible technical resolutions are selected and recorded
> under the shared policy while reserved decisions are presented to the user.**

You are NOT a rubber stamp. You are actively trying to **break** the artifact — and to **reality-
check** it against the codebase it targets. Assume it has issues until proven otherwise.

> **Without codebase grounding, preflight is nothing but a document-correction exercise.** The
> entire value depends on holding the artifact accountable to the real files, architecture,
> patterns, and dependencies.

The creation-time gates inside the make-plan skill (its Phase 1C gate) and the make-requirements
skill (its Phase 2B gate) catch issues during authoring. Preflight is the **post-creation safety
net** — fresh eyes that catch what those gates missed and what evolved since.

## The 8-step protocol (overview)

1. **Load & identify artifact type** — read the complete artifact; classify it as a requirements
   set, implementation plan, or ad-hoc document. Load the project's AGENTS.md (or detected project
   conventions) and any Ambiguity Register (`00-ambiguity-register.md`).
2. **🚨 Codebase Reconnaissance — NON-NEGOTIABLE.** Build a real understanding of the code the
   artifact targets, map every document reference to actual code, then present a **Codebase Context
   Summary**. This is what separates a real preflight from a document-correction exercise. Full
   what/why/how table, recon depth by artifact type, and the summary template are in
   [dimensions.md](dimensions.md).
3. **13-dimension scan** — review the artifact across all 13 dimensions (below), every check
   informed by Step 2. Depth adapts by artifact type. Full detail in [dimensions.md](dimensions.md).
   Classify newly suggested work under the shared scope-expansion protocol before it can become a
   finding or remediation. Apply the shared Complexity Escalation Gate to disproportionate support
   machinery; an unapproved escalation is at least a 🟠 MAJOR finding and cannot pass.
4. **Compile the Preflight Report** — every finding gets a numbered `PF-NNN` entry with severity.
   Templates and report header in [report-format.md](report-format.md).
5. **Present findings & collect decisions** — grouped by severity and paced by the authoritative
   batch rules in [report-format.md](report-format.md). In normal mode, record the user's decision
   on every finding. With active auto-design, record the strongest eligible technical resolution
   with complete delegated provenance; reserved decisions still require the user. This selects a
   resolution only and does not authorize applying a fix.
   A finding ruling also does not authorize a linked `SE-*` proposal.
6. **Determine pass/fail** — Clean / Passed / Passed With Notes / Blocked (see [Pass tiers](#pass-tiers)).
7. **Apply fixes (only if requested)** — preflight is a review protocol, not a modification one.
   Never apply fixes without explicit instruction.
8. **Roadmap sync** — after a pass, advance the target's row via the roadmap skill if a roadmap exists.

## The 13 dimensions (names only — detail in [dimensions.md](dimensions.md))

1. Ambiguities
2. Implicit Assumptions
3. Logical Contradictions
4. Completeness Gaps
5. Dependency Issues
6. Feasibility Concerns
7. Testability
8. Security Blind Spots
9. Edge Cases
10. Scope Creep Indicators
11. Ordering & Sequencing
12. Consistency
13. **Codebase Alignment** — the master reality check (10 sub-checks; entirely codebase-grounded)

Scan all 13 every time. Depth adapts (🔥 Deep / Standard / Light) by artifact type — see the
dimension-depth-by-artifact-type table in [dimensions.md](dimensions.md). Dimension 13 and its
10 sub-checks (Phantom References, Stale Assumptions, Architecture Mismatch, Impact Blindness,
Redundancy, Test Impact, Dependency Reality, Convention Violations, Scope vs. Reality, Migration &
Compatibility) are the heart of the audit — read that section before scanning a plan.

## Severity scale

| Severity | Icon | Meaning | Must fix? |
|---|---|---|---|
| **CRITICAL** | 🔴 | Will cause implementation failure, data loss, security breach, or fundamental design flaw | YES — blocks execution |
| **MAJOR** | 🟠 | Will cause significant rework, incorrect behavior, user-facing bugs, or architectural problems | YES — strongly recommended |
| **MINOR** | 🟡 | Friction, tech debt, minor inconsistencies, suboptimal patterns | Recommended, not blocking |
| **OBSERVATION** | 🔵 | Suggestion / style preference / optimization — not a defect | Optional |

Calibrate honestly — never inflate to get attention, never deflate to avoid conflict.

## Pass tiers

| Tier | Criteria | Header |
|---|---|---|
| **✅ PASSED — Clean** | Zero findings across all 13 dimensions | `✅ PREFLIGHT PASSED — clean scan, 0 findings` |
| **✅ PASSED** | All 🔴/🟠 resolved; zero 🟡/🔵 remaining | `✅ PREFLIGHT PASSED — all [X] findings resolved` |
| **✅ PASSED WITH NOTES** | All 🔴/🟠 resolved; some 🟡/🔵 explicitly accepted | `✅ PREFLIGHT PASSED WITH NOTES — [X] resolved, [Y] accepted` |
| **❌ BLOCKED** | Any 🔴/🟠 still unresolved | `❌ PREFLIGHT BLOCKED — [X] critical/major unresolved` |

A clean first-scan pass is cause for celebration, not suspicion. **Never invent findings** to
justify the review — if the artifact is solid, say so.
Optional additions omitted in strict scope, or deferred/discarded exploration proposals, do not
prevent a clean or passing verdict. A necessary correction or blocking uncertainty may still block
because the requested behavior itself is not yet proven correct, safe, and feasible.

## Report persistence

Save the report as a permanent file alongside the artifact:

| Artifact type | Report location |
|---|---|
| Full requirements set | `requirements/00-preflight-report.md` |
| Single requirement | `requirements/00-preflight-report-RD-NN.md` |
| Full implementation plan | `plans/<feature-name>/00-preflight-report.md` |
| Single plan document | `plans/<feature-name>/00-preflight-report-<document-stem>.md` |
| Ad-hoc | `<artifact-directory>/preflight-report.md` |

The report header must record the exact audit target and its git blob or content hash. Per-document
report names prevent a narrow pass from masquerading as a set-wide pass or overwriting another
document's evidence. The report is separate from the Ambiguity Register (decisions made during
creation) — see [report-format.md](report-format.md) for the relationship and cross-referencing.

## Parallelizing the scan (clustered fan-out)

When the session supports subagents, the 13-dimension scan fans out as **~5 parallel
preflight-auditor dispatches** — one per dimension cluster, an exact partition defined in
**[../../_shared/quality-profile.md](../../_shared/quality-profile.md)** (① document soundness ·
② grounding · ③ delivery · ④ risk · ⑤ fit). Each dispatch carries the header + packet from that
doc (the artifact, ONE cluster, and the codebase context its dimensions need). `--thorough`
expands the fan-out to one dispatch per dimension. Recon reads may still go to read-only explore
agents, and the codebase-scout may ground individual claim-checks (≤3 scout dispatches per run).

The lead context always merges the returned PA-NNN findings into the single `PF-NNN` sequence
(dedupe across clusters, renumber, keep severities honest), runs the verdict synthesis, and owns
every user interaction — auditors never talk to the user. Sequential scanning remains correct
when subagents are unavailable.

When opt-in outcome metrics are enabled, record only enumerated review results and rework counts
through `codeops_outcomes.py`. Finding content and user decisions remain solely in project
artifacts and never enter the metrics store.

## Iterative re-scanning

Iteration 2 verifies prior fixes, checks their direct consequences, and re-scans all 13 dimensions
within the unchanged audit target. A third iteration is allowed only when iteration 2 leaves or
introduces a 🔴/🟠 finding; scope it to those fixes and their direct dependency surface. Do not
automatically begin iteration 4: require a fresh-session audit or an explicit user decision to
continue.

Preserve finding identity across iterations. A partial fix, refined wording, or regression with the
same root cause reopens the original `PF-NNN` and appends iteration evidence. Allocate a new number
only for a genuinely independent root cause.

Stop with **Passed With Notes** when every 🔴/🟠 finding is resolved and every remaining 🟡 finding
is explicitly accepted. 🔵 observations do not require another fix/rescan cycle. Full convergence,
rescan, and numbering rules live in [report-format.md](report-format.md).

## Session resume (save-as-you-go)

Continuity notes are written **as you go, not on interruption** — a hard crash must lose at most
one dimension of work:

- **Checkpoint cadence:** update `_preflight-notes.md` (in the artifact directory, next to where
  the report will be saved) after the recon step completes and after EACH dimension finishes —
  never only when a session "feels long".
- **Schema (minimal):** the artifact path + its git ref (or mtime) at scan start; completed
  dimensions; findings so far (numbers + one-liners); pending dimensions; user decisions
  collected; recon notes (key files examined, references mapped).
- **On `preflight --continue`:** read the notes, then run the **staleness check** — if the
  artifact changed since the recorded ref/mtime, say so and re-scan the affected dimensions
  rather than trusting stale findings. Summarize where you left off and resume from the next
  unscanned dimension. **Do NOT repeat reconnaissance** — reuse the notes; re-read specific
  files only when a finding needs deeper inspection.
- **On completion:** delete `_preflight-notes.md` — a stale notes file must never be picked up
  by a later scan of a different artifact (the schema's artifact reference is the second guard:
  a mismatch is treated as stale and reported).

## Same-agent bias awareness — 🚨 NON-NEGOTIABLE

When the same model created the artifact and reviews it, systematic blind spots are likely. You
MUST counteract this. If the artifact was created in the **current session**, note it at the top of
the report (`⚠️ SAME-SESSION REVIEW … consider a new session for review independence`). For any
behavior bound to an external standard, **cite the specific standard text** rather than reasoning
from memory; flag explicitly if you can't. Before concluding the scan, run the adversarial-question
checklist. Full safeguards in [report-format.md](report-format.md).

## Key agent behavior rules

> **Grounded Options & Recommendations (coding standards → Working style) apply here.** Before presenting options/findings/recommendations: filter out non-viable ones (no strawmen; ≥2 only when ≥2 are genuinely viable, else present the single viable path and name what was rejected), second-guess each, verify any code-modifying option against the actual current code (cite `file:line`), and lead with a recommendation backed by grounded reasoning. Match ceremony to stakes. In normal mode, the user decides. With active auto-design and existing remediation authorization, select and record the strongest eligible technical fix; never auto-waive risk or dismiss a critical/major finding, and escalate reserved decisions. **Recommendation hardening:** apply `_shared/recommendation-hardening.md` — for **high-stakes** findings (CRITICAL/MAJOR severity) spawn one independent challenger and reconcile *before* recording the recommendation; for all consequential findings run the in-context layers and close with the `Confidence:` / `Hardening:` disclosure.

- **Be adversarial, not hostile** — findings should feel helpful, not critical.
- **Specificity over volume** — one precise finding beats ten vague ones; never pad.
- **Don't invent problems** — a clean pass is a valid, trustworthy outcome.
- **Options must be real** — no strawman options to flatter a recommendation.
- **Respect previous decisions** — don't re-litigate Ambiguity Register entries without new info.
  A deferred complexity decision counts as accepted risk only when the named machinery is absent
  from the audited executable artifact; otherwise keep a 🟠 MAJOR finding open.
- **Cross-document awareness is contextual, not scope expansion** — read related documents to test
  the target, but keep findings, verdicts, modifications, and roadmap advancement within the audit
  scope contract.
- **Codebase evidence is not optional** — for dimensions 2, 4, 5, 6, 11, 13 (and any claim about
  the code) cite the specific file and code; if you can't verify, say so explicitly.
- **Reconnaissance is proportional** — read what the artifact touches and its direct dependents;
  don't read the whole codebase for a small artifact.

## Related skills & integrations

- After the **make-requirements** skill → `preflight requirements` (catches issues past its Phase 2B gate).
- After the **make-plan** skill → `preflight <feature>` (catches issues past its Phase 1C gate).
- Before the **exec-plan** skill → if no `00-preflight-report.md` exists, exec-plan MAY softly
  suggest running preflight first (soft suggestion, not a hard gate).
- The **grill-me** skill interrogates the user's intent *before* creation; preflight audits the
  *created* artifact against the code *after*. Complementary, opposite directions.
- The **roadmap** skill — a passing preflight advances the target's row to `RD Preflighted` (🔎) or
  `Plan Preflighted` (🔬); a BLOCKED outcome does not advance it.
- Reference your project's coding/testing standards (AGENTS.md) for what plans/requirements should target.

**Standalone:** when used without a follow-up, finish the scan + resolution, present the final
status, then ask the user what to do next (apply fixes, create a plan, start execution, or review
specific findings).
