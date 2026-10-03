# Recommendation Hardening Protocol

> Shared reference for the **Grounded Options & Recommendations** directive
> (`standards/coding-standards.md` → Working style). Linked by the recommendation-producing skills.
> **CodeOps Artifact Schema**: 1

This protocol makes recommendations trustworthy on the **first** pass. It is the standing answer to
the question *"are these your best possible recommendations?"* — asked and answered **before** you
present, every time, so the operator never has to ask it.

## Why this exists

Left unstructured, a model **satisfices**: it returns the first adequate set of options drawn from
"what does a reasonable answer look like," not "what is the best answer after exhausting the space."
The Grounded Options *second-guess* step, run in the same forward pass that produced the options,
shares that pass's framing and blind spots — so it rarely finds the better answer that an external
challenge would.

When a human challenges the recommendation, two different things can happen, and only one is good:

1. **Genuine deeper search** — a fresh pass takes the first pass as adversarial input, sees its gaps,
   and finds a better answer. *This is the lift we want.*
2. **Sycophantic drift** — the model produces a *different* answer because it read the challenge as
   "you were wrong," not because the new answer is better. *This is noise, and it is corrosive to
   trust.*

> **Convergence, not drift.** The goal of this protocol is to institutionalize (1) and design out
> (2). You do not "try harder when poked" — you run a **structured** hardening pass that *converges*
> on a verified-best recommendation. Reflexively changing an answer under perceived pressure is a
> failure of this protocol, not a success of it.

## When it applies

Apply the full protocol to every **consequential** recommendation: code-modifying directions,
architecture and design choices, scope decisions, defect-resolution directions, requirements
choices, plan-making and plan-execution decisions, and preflight findings.

> **Proportionality.** Trivial, easily-reversible, or obvious choices get a one-line recommendation
> and skip the ceremony — drowning the operator in hardening theater wastes their time as surely as
> strawman options do. Match the ceremony to the stakes.

## Layer 1 — Forced reframing

Before presenting a consequential recommendation, generate your candidate set, then **answer these
four prompts** (internally for ordinary decisions; surfaced briefly for high-stakes ones). They are
the forcing functions that break you out of the obvious framing:

- **10× budget:** "What would I recommend with **10× the time/budget**?"
- **Contrarian expert:** "What's the option a **contrarian senior expert** would push that I
  dismissed or didn't consider?"
- **Obsolescence:** "What would make my current top pick **obsolete or wrong**?"
- **Pre-empt the challenge:** "If the operator asks *'is this your best?'* — **answer that now.**
  What changes?"

Revise your candidate set with whatever these surface *before* moving on.

## Layer 2 — Definition-of-done rubric

A consequential recommendation may **not** be presented until **all** of these hold. This is the
**definition-of-done** for a recommendation — it operationalizes "best" so it is a checklist, not a
vibe:

- [ ] **≥1 genuinely non-obvious option considered** — never a strawman. (When only one option is
  genuinely viable, that is a valid outcome: present it alone, say it is the only viable one, and
  name what you rejected and why.)
- [ ] **Confidence level set** — High / Med / Low, with the specific thing that would change it.
- [ ] **Strongest counter-argument named** — the best case *against* your chosen pick, stated in one
  line.

## Layer 3 — Confidence & trust disclosure (conditional)

The disclosure exists to surface **residual uncertainty** — so it appears only when there is some:

```text
Confidence: High | Med | Low — <the specific thing that would change this>
Hardening: <what the deeper pass changed, or "no change">
```

The disclosure is REQUIRED when any of these hold:
- confidence is **Med or Low**;
- the hardening pass **changed something** (an option added/dropped, the pick revised);
- the recommendation is **high-stakes** (see below).

Otherwise — High confidence, hardening changed nothing, not high-stakes — **omit the disclosure**:
a boilerplate "Hardening: no change" at High confidence carries no information and trains the
operator to skip the lines that matter. (The layers 1–2 work still runs; only the two-line
disclosure is conditional.)

For a **high-stakes** recommendation, also state the challenger's verdict:
`Challenger: converged` or `Challenger: diverged — <how>`.

This disclosure is **presentation-layer only**. It may appear in a saved artifact (e.g. a preflight
report), but it is **not** a newly-required, validated field — existing artifacts remain valid
without it, and no migration is implied.

## Layer 4 — Tiered independent challenger

The independence layer is what actually closes the *trust* gap, because a self-critique in the same
context inherits the same blind spots. Run it **tiered by stakes**:

- **Always (every consequential recommendation):** Layers 1–3, in-context.
- **High-stakes only:** additionally spawn **one independent challenger** subagent.

### Challenger budget (hard caps)

- **One challenger per preflight scan, not per finding.** A preflight run with multiple
  CRITICAL/MAJOR findings spawns a SINGLE challenger that receives the whole finding batch
  (each finding's statement + surviving options) **plus the scan's recon summary / Codebase
  Context section**, so it challenges from evidence rather than from a cold start. It returns a
  per-finding verdict list.
- **At most 2 challenger spawns per skill run**, total — e.g. one for the finding batch and one
  for a late-discovered decision. Beyond the cap, proceed with Layers 1–3 and disclose
  `Challenger: budget exhausted` (cap confidence at Med for those items).

### The challenger mechanism

1. Dispatch **one** independent `design-challenger` role in a fresh subagent context. Give it the
   problem statement and surviving options — but **NOT** your chosen pick. Packet convention:
   `_shared/quality-profile.md`. A generated custom agent is optional; a generic subagent with the
   complete challenger contract is equivalent.
2. Instruct it to produce **its own** best recommendation and the strongest case for it, blind to
   your choice. Challenger prompt template:

   > *"Here is a decision and the candidate options: <problem + options>. Independently recommend the
   > single best option and give the strongest grounded case for it. You do not know my current pick.
   > If a better option is missing from the list, propose it. State your confidence and the strongest
   > argument against your own pick."*

3. **Reconcile** the challenger's recommendation with yours:
   - **Converged** → present with raised confidence; note `Challenger: converged`.
   - **Diverged** → present **both**, with a grounded reconciliation of why you land where you do;
     note `Challenger: diverged — <how>`. Never silently overwrite either side.

> **Fallback.** If the challenger subagent is unavailable or returns nothing usable, proceed with
> Layers 1–3, disclose `Challenger: unavailable`, and **cap confidence at Med**. Exception: a
> detected complexity escalation cannot proceed. The Complexity Escalation Gate requires an
> independent verdict, so it stays blocked when the challenger is unavailable or its budget is
> exhausted.

## High-stakes definition (the escalation trigger)

A recommendation is **high-stakes** — and therefore gets the challenger — when any of these hold:

- it is a **preflight** finding at **CRITICAL/MAJOR** severity (challenged as a batch — one
  challenger per preflight scan, see the budget above); or
- it is a **make-plan** (Phase 1C) or **make-requirements** (Phase 2B) gate decision tagged
  **complex/sensitive** (the project routing tags); or
- it triggers the shared **Complexity Escalation Gate**, regardless of routing tag; or
- the **user explicitly requests a challenger** for a decision, in any skill.

Everything else — minor/observation findings, trivial/standard-tagged decisions, ad-hoc choices —
gets Layers 1–3 only. When a gate decision carries no routing tag, treat it as `standard` (the
documented default) → no challenger. Skills without their own trigger (grill-me, exec-plan, the
wrappers) escalate ONLY via this definition — they carry no private one.

## Anti-patterns

- ❌ Changing your recommendation reflexively because you were questioned (drift, not convergence).
- ❌ Presenting >2 options without filtering, or padding with strawmen to manufacture a choice.
- ❌ Skipping the confidence/`Hardening:` disclosure where Layer 3 requires it (Med/Low
  confidence, a changed pick, or high stakes) — or padding every answer with a contentless
  "Hardening: no change" where it doesn't.
- ❌ Spawning a challenger for a trivial or easily-reversible choice (ceremony without stakes).
- ❌ Spawning per-finding challengers when the batch rule applies, or exceeding the 2-spawn cap.
- ❌ Giving the challenger your chosen pick (destroys its independence).
- ❌ Deriving "best" from how much effort you spent rather than from the definition-of-done rubric.
