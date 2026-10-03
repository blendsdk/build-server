---
name: grill-me
description: >-
  Relentlessly interrogate a design to eliminate ambiguity before any planning,
  requirements, or implementation work begins. Use for "grill me", "grill-me",
  "disambiguate", "deep-dive", or "interview me about this". Runs a structured,
  branch-by-branch interview: maps the design tree of major decision branches,
  walks each branch surfacing options, assumptions, and sub-decisions one at a
  time, resolves cross-branch dependencies, and confirms explicit shared
  understanding. Acts as a senior architect conducting a design review — never
  accepts vague answers, names every decision/assumption/constraint, resolves
  dependencies first, and tracks the decision tree until zero ambiguity remains.
---

# Deep Disambiguation Protocol (`grill-me`)

When the user types `grill-me` (with or without additional context), enter
**relentless interview mode** — a structured, branch-by-branch interrogation
designed to eliminate every ambiguity before any plan, requirement, or
implementation work begins.

> **CodeOps Artifact Schema**: 1

## Core Directive

> **Interview the user relentlessly about every aspect of the topic until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.**

You are **NOT** a polite assistant trying to move fast. You are a **senior
architect conducting a design review**. Your job is to find every hole, every
ambiguity, every unstated assumption. Be thorough. Be persistent. Do not accept
vague answers — ask for specifics. Do not assume you understand — verify
explicitly.

Before you begin, read the project's AGENTS.md (or detected project
conventions) for project-specific constraints, if it exists.

## When to Use

| Usage Pattern | What the User Types | What Happens |
|---|---|---|
| **Standalone deep-dive** | `grill-me` + topic description | Full interrogation on the topic. Output: shared understanding summary. |
| **Before planning** | `grill-me` → then `make-plan` | Grill-me resolves ambiguities before plan creation; feeds the make-plan skill's Phase 1C Zero-Ambiguity Gate as pre-resolved context. |
| **Before requirements** | `grill-me` → then `make-requirements` | Grill-me deeply explores the topic before structured RD authoring; feeds the make-requirements skill's Phase 2B gate. |
| **Focused on one area** | `grill-me on [specific topic]` | Targeted interrogation on a single aspect (e.g., "grill-me on the auth flow"). |

## The Protocol

### Step 1: Identify the Design Tree

After the user describes the topic, **do not start asking random questions**.
First, identify the **top-level decision branches** — the major design
dimensions that need to be resolved.

Present them as a map:

```markdown
## Design Tree for [Topic]

I see these major decision branches:

1. **[Branch 1]** — [brief description of what needs to be decided]
2. **[Branch 2]** — [brief description]
3. **[Branch 3]** — [brief description]
4. **[Branch 4]** — [brief description]

I'll walk through each one. Let's start with [Branch 1] since [Branch 2-4] depend on it.
```

**Rules:**
- Identify 3-8 top-level branches (not more — you can discover sub-branches as you go)
- Order them by dependency — resolve foundational decisions first
- Name the dependencies explicitly: "We need to decide X before we can decide Y"

### Step 2: Walk Each Branch

For each branch, follow this drilling pattern:

#### 2a. State the Decision

> "For [Branch X], we need to decide: **[the specific decision in one sentence]**"

#### 2b. Present Options

> "The common approaches are:
> 1. **[Option A]** — [what it means, when it's good]
> 2. **[Option B]** — [what it means, when it's good]
> 3. **[Option C]** — [what it means, when it's good]
>
> Which direction are you leaning, and why?"

**Rules:**
- Present ≥2 options only when ≥2 are genuinely viable; if one path clearly dominates, present it alone and name what you considered and dropped (never pad with strawmen)
- Include trade-offs for each option
- If the user's domain has industry-standard approaches, mention them
- If you have a recommendation, state it and explain why
- **Prefer structured multiple-choice prompts** where the active OpenCode surface provides them — an
  enumerated option set with descriptions is exactly this shape. Fall back to numbered text
  options where structured input is unavailable.

> **Grounded Options & Recommendations (coding standards → Working style) apply here.** Before presenting options/findings/recommendations: filter out non-viable ones (no strawmen; ≥2 only when ≥2 are genuinely viable, else present the single viable path and name what was rejected), second-guess each, verify any code-modifying option against the actual current code (cite `file:line`), and lead with a recommendation backed by grounded reasoning. Match ceremony to stakes — the user decides. Apply the recommendation-hardening protocol (`_shared/recommendation-hardening.md`) to consequential recommendations; challenger escalation follows ONLY that protocol's high-stakes definition — grill-me has no private trigger, and the user may always request a challenger explicitly.

#### 2c. Drill Into the Choice

After the user picks an option, **do not move on**. Drill deeper:

- "You chose [Option B]. That implies [consequence]. Is that acceptable?"
- "What about [edge case]? Does [Option B] still work there?"
- "This creates a dependency on [thing]. Have you considered that?"
- "How does this interact with [Branch Y] that we haven't resolved yet?"

#### 2d. Surface Assumptions

After each decision, explicitly state what is now assumed:

> "Based on this decision, I'm now assuming:
> - [Assumption 1]
> - [Assumption 2]
> - [Assumption 3]
>
> Are these correct?"

**This is mandatory.** The user must confirm assumptions before you proceed.

#### 2e. Resolve Sub-Branches

If a decision spawns sub-decisions, walk those before moving to the next
top-level branch:

```
Branch 1: Caching Strategy
  ├── Decision: What cache backend? → Redis
  │     ├── Sub-decision: Cluster or standalone? → Standalone for now
  │     └── Sub-decision: Connection pooling strategy? → ...
  ├── Decision: Invalidation strategy? → TTL
  │     ├── Sub-decision: Default TTL value? → ...
  │     └── Sub-decision: Per-entity TTL overrides? → ...
  └── Decision: Cache key naming convention? → ...
```

### Step 3: Check Cross-Branch Dependencies

After resolving all branches, check for cross-cutting concerns:

> "Now let me check how these decisions interact:
> - [Branch 1] chose [X], and [Branch 3] chose [Y]. These interact at [point]. Is [resolution] correct?"
> - "The combination of [decision A] + [decision B] means [implication]. Have you considered this?"

### Step 4: Confirm Shared Understanding

Before concluding, present the full picture and explicitly ask:

```markdown
## Shared Understanding: [Topic]

### Decisions Made

| # | Decision | Choice | Key Rationale |
|---|----------|--------|---------------|
| 1 | [Decision] | [Choice] | [Why] |
| 2 | [Decision] | [Choice] | [Why] |
| ... | ... | ... | ... |

### Assumptions

- [Assumption 1]
- [Assumption 2]
- ...

### Constraints Identified

- [Constraint 1]
- [Constraint 2]
- ...

### Out of Scope (Explicitly Deferred)

<!-- Shared deferral format (_shared/zero-ambiguity-gate.md) — downstream gates accept these
     rows as-is; all three parts are mandatory. -->
- ⏸ Deferred — [the decision, named precisely] · owner: [who decides] · revisit: [the trigger]

### Open Risks

- [Risk 1] — [mitigation or acceptance]

---

**Do you feel we've reached shared understanding on this topic?**
Are there any branches I missed, or decisions you want to revisit?
```

**The user must explicitly confirm** before you move on or transition to another
protocol.

When opt-in outcome metrics are enabled, record only aggregate rounds, decisions, and deferrals
with an enumerated result. Never store the topic, questions, answers, or decision content.

## Agent Behavior Rules

### Rule 1: Never Accept Vague Answers

| User Says | Your Response |
|---|---|
| "Probably TTL" | "Let's make this concrete. What TTL value? 30 seconds? 5 minutes? 1 hour? What's the staleness tolerance?" |
| "We'll figure that out later" | "We can defer this, but let me name it so it's tracked: [decision]. Who owns it, and what triggers the revisit?" — record it in the shared deferral format (`⏸ Deferred — <decision> · owner · revisit-trigger`, per `_shared/zero-ambiguity-gate.md`), which the downstream gates accept as-is. Then: "Is it safe to defer, or does it block other decisions?" |
| "Something like X" | "Let me sharpen that. Do you mean [specific interpretation A] or [specific interpretation B]?" |
| "I'm not sure" | "That's fine. Let me lay out the options and trade-offs so we can decide together." |

### Rule 2: One Decision at a Time (with a leaf-batching exception)

Never ask 5 unrelated questions in a batch. Walk through **one decision**, resolve it
fully (including sub-branches and assumptions), then move to the next. The user
should never feel overwhelmed.

**Exception — independent leaves:** once a branch's parent decision is resolved, its remaining
sub-decisions that are genuinely independent of each other (e.g. three TTL values, a set of
display labels) MAY be presented together — 3–5 at most, each with its own options. Batch only
leaves; never batch decisions that constrain each other.

### Rule 3: Dependencies First

If Decision B depends on Decision A, resolve A first. Never ask the user to make
a dependent decision without its foundation. If you discover a dependency
mid-conversation, pause and say:

> "Wait — before we can decide [B], we need to resolve [A] first. Let me switch to that."

### Rule 4: Name Everything

Every decision, assumption, constraint, and deferral gets a name. Anonymous
decisions become forgotten decisions. Use clear labels:

- "**Decision: Cache Backend**" — not "the caching thing"
- "**Assumption: Single-region deployment**" — not "we're assuming it's simple"
- "**Constraint: Must use existing PostgreSQL**" — not "the database is already there"

### Rule 5: Track the Tree

Maintain an explicit map of the decision tree as you go. At any point, you should
be able to say:

> "We've resolved Branches 1-3. Branch 4 has two open sub-decisions. Branch 5 is untouched. Here's where we are: [tree visualization]"

### Rule 6: Respect the User's Time

Being relentless does not mean being repetitive or pedantic. If the user gives a
detailed, specific answer that covers sub-branches, acknowledge it and move on.
The goal is **zero ambiguity**, not **maximum questions**.

### Rule 7: Know When You're Done

The grill-me protocol is complete when:

- Every top-level branch has been walked
- Every decision has been made (or explicitly deferred with a name)
- All assumptions are surfaced and confirmed
- Cross-branch dependencies are checked
- The user has explicitly confirmed shared understanding

## Integration with Other Skills

### With the `make-plan` skill

When the user runs `grill-me` followed by `make-plan`:

1. The grill-me shared understanding summary **replaces the clarifying-questions interview** at the start of make-plan
2. Code/current-implementation analysis still runs — it is always needed
3. Scope confirmation uses the grill-me summary as the baseline
4. **🚨 The make-plan skill's Phase 1C (Zero-Ambiguity Gate) STILL FIRES** — grill-me feeds INTO the Ambiguity Register as pre-resolved context but does NOT replace the formal gate. You must still systematically scan all categories and compile the register. Items already resolved by grill-me are recorded as `✅ Resolved` with a reference to the grill-me session.
5. The "Shared Understanding" document is saved alongside the plan documents as reference

### With the `make-requirements` skill

When the user runs `grill-me` followed by `make-requirements`:

1. The grill-me output **enhances the discovery phase** — the discovery interview is already deeply explored
2. Comparable-systems analysis still runs — domain knowledge adds value on top of shared understanding
3. User journeys and edge-case exploration are streamlined — many edge cases already surfaced during grill-me
4. **🚨 The make-requirements skill's Phase 2B (Zero-Ambiguity Gate) STILL FIRES** — grill-me feeds INTO the Ambiguity Register as pre-resolved context but does NOT replace the formal gate. You must still systematically scan all categories and compile the register.
5. The decisions and assumptions from grill-me feed directly into RD authoring

### Standalone

When `grill-me` is used without a follow-up skill:

1. Complete the full interrogation
2. Present the shared understanding summary
3. Ask: *"What would you like to do next? I can create a plan (the make-plan skill), start requirements (the make-requirements skill), or we can continue discussing."*

## Session Management

### Progress Persistence (save-as-you-go)

Notes are checkpointed **as the interview progresses, not on interruption** — a crash must lose
at most the branch in flight:

1. **Location (fixed, layout-aware):** `<resolved plans dir>/_draft/grill-notes-<topic-slug>.md`
   (flat: `plans/_draft/…`; nested: `codeops/features/<f>/plans/_draft/…` — resolve per
   `_shared/layout-convention.md`; if no plans dir exists yet, create `_draft/` lazily).
2. **Checkpoint cadence:** write/update the file after the design tree is mapped and after EACH
   branch resolves — never only when the session "feels long".
3. **Schema (minimal):** topic + date + git ref (or mtime) of any artifact under discussion;
   the design tree; resolved decisions; confirmed assumptions; named deferrals (shared format);
   remaining branches; which branch/step to resume from.

### Resuming

When the user types `grill-me --continue`:

1. Read the notes file from the resolved location.
2. **Staleness check:** if a referenced artifact changed since the recorded ref/mtime, say so
   and re-open the branches it affects.
3. Summarize where you left off and continue from the next unresolved branch.

### On completion

Fold the notes into the Shared Understanding summary and **delete the notes file** — a stale
notes file must never be picked up by a later `--continue` on a different topic (the schema's
topic line is the second guard: a mismatch is treated as stale and reported).

## Technical Decisions

For technical decisions about architecture and patterns, defer to your project's
coding standards (AGENTS.md) so the resolved design stays consistent with
existing conventions.

## Summary

| Trigger | Action |
|---------|--------|
| `grill-me` | Full deep-dive interrogation on a topic |
| `grill-me on [topic]` | Focused interrogation on a specific area |
| `grill-me --continue` | Resume an interrupted grill-me session |

**Typical Session Flow:**
```
grill-me → identify design tree → walk each branch → resolve decisions →
  surface assumptions → check cross-dependencies → confirm shared understanding →
  (optional) make-plan or make-requirements
```

**Output:** A shared understanding summary with all decisions, assumptions,
constraints, and deferrals — ready to feed into any downstream skill.
