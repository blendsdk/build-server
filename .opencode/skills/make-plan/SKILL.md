---
name: make-plan
description: >-
  Creates a detailed, multi-document implementation plan for a software feature or task before any code is written. Use when the user wants to "make a plan", types "make-plan", or asks to "plan this feature", "create an implementation plan", "plan out this work", or "write a spec/plan" for something to be built. Drives a mandatory clarifying-questions interview, a hard Zero-Ambiguity Gate, and produces a feature plan document set ending in a task-by-task execution plan. For EXECUTING an existing plan, use the exec-plan skill instead.
---

# Implementation Plan Creation (`make-plan`)

Create a detailed, multi-document implementation plan for a software feature or task. This skill covers plan **creation** only. To **execute** a finished plan, use the **exec-plan skill**.

## Auto-design option

If `$ARGUMENTS` contains exactly one exact standalone `--auto-design` token before the first `--` sentinel, remove it before resolving targets, paths, or modes; zero occurrences means normal mode, more than one is invalid, and tokens at or after the sentinel are target content; announce `Auto-design active — eligible technical decisions are
delegated and recorded`; then read and apply
[../../_shared/auto-design.md](../../_shared/auto-design.md). Resolve eligible architecture and
technical design decisions under that policy and propagate its downward-only context to explicitly
invoked supported children; an unsupported child fails closed. This mode does not grant action permission or scope expansion. **Normal mode:** without the exact token, every material choice
still requires an explicit user decision; historical delegated records must not infer delegated authority.

## Scope exploration option

If `$ARGUMENTS` contains exactly one exact standalone `--explore-scope` token before the first `--` sentinel, remove it before resolving targets, paths, or modes; zero occurrences means strict scope, more than one is invalid, and tokens at or after the sentinel are target content; announce `Scope exploration active — optional additions will be proposed for your decision`; then read and apply
[../../_shared/scope-expansion-control.md](../../_shared/scope-expansion-control.md). Strict scope is the default:
do not report or plan optional additions. Exploration may propose `SE-*` items but
never accepts them; only the user may choose `Keep`.

## Plan readiness proof

A plan is not ready merely because its documents exist. Before presenting it as executable,
directly confirm that its required documents exist, its `00-index.md` declares every implemented
RD on one `> **Implements**:` line, its ambiguity register has no open material item, and its
specification tests are ordered before implementation tasks. Run the semantic Zero-Ambiguity Gate.
Do not create a graph, readiness record, or transition request. `99-execution-plan.md` is the sole
mutable task-progress authority.

## Planning scope contract

Record three boundaries before discovery:

| Boundary | Meaning |
|---|---|
| **Planning target** | The selected RD, task, or standalone feature the plan will implement |
| **Context artifacts** | Related requirements, plans, code, and docs read to verify the target |
| **Modification set** | The requirement/specification artifacts the user has authorized make-plan to change |

Reading an artifact does not authorize changing it. If planning exposes an upstream defect, reopen
the owning requirement or specification and mark affected downstream plan content stale, but do
not edit it until the user confirms the exact expanded modification set. If the correction would
redesign sibling RDs or the requirement set, pause and offer a separate requirements revision
instead of silently absorbing it into plan creation.

Apply the shared scope-expansion classification before adding any newly suggested functionality.
Every planned item must trace either to the confirmed scope baseline or to a user-kept `SE-*`
entry. A necessary correction is reported with its causal evidence but does not itself authorize an
expanded modification set. An optional idea is silent in strict scope and becomes a proposal only
with active scope exploration.

> **CodeOps Artifact Schema**: 1

## What you produce

Re-run [../../references/domains/selection.md](../../references/domains/selection.md) before component decomposition. Requirements-stage lens selection is evidence, not a permanent assumption. Apply every selected lens to specifications, acceptance criteria, failure narratives, and test strategy.

A folder `plans/<feature-name>/` containing:

```
plans/<feature-name>/
├── 00-ambiguity-register.md   # Zero-Ambiguity Gate register (audit trail)
├── 00-index.md                # Overview and navigation
├── 01-requirements.md         # Requirements and scope
├── 02-current-state.md        # Current implementation analysis
├── 03-XX-<component>.md       # Technical spec per component (one or more)
├── 07-testing-strategy.md     # Spec test cases + verification
└── 99-execution-plan.md       # Phases, sessions, task checklist
```

The full templates for every document live in **[templates.md](templates.md)** — read it before writing any plan document in Phase 2.

## Resolve paths first (layout-aware)

Determine the layout via **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)** before creating the plan folder:

- **Flat layout** (no marker): the plan folder is `plans/<feature-name>/`; `00-index.md` declares `> **Implements**: RD-NN` — exactly as flat layout always has.
- **Nested layout** (marker present): the plan folder is `codeops/features/<f>/plans/<plan>/`. **Ask/confirm the target feature** first (create the feature folder lazily if new — never guess). `00-index.md` declares a **feature-qualified** `> **Implements**: <feature>/RD-NN`, and any `> **Source**` link points at the feature's own `requirements/` dir. Everywhere below that says `plans/<feature-name>/` means this nested plan path.

## Lightweight tasks (mini-plan path — both layouts)

Not every change is a feature. Ad-hoc work (a bugfix, chore, small change) is a **task** (`T-NN`), and a *non-trivial* task gets a **single mini-plan**, not the full multi-document set. When the work is a task (see the routing rule in **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)**):

- Write **only** the mini-plan at the resolved task path (flat: `plans/<task-slug>/99-execution-plan.md`; nested: `codeops/features/<f>/plans/<task-slug>/99-execution-plan.md`) — an execution doc with an **Objective**, a **Smallest viable design**, a short **task checklist**, and a **Verify** line. **No** `00–07` docs, **no** RD, and no main Zero-Ambiguity Gate.
- Stamp it `> **Type**: Task (lightweight) · **Feature**: <f> · **CodeOps Artifact Schema**: 1` and a `> **Progress**:` line (in flat layout drop the `**Feature**:` part).
- Specification-first ordering still applies *when the task warrants tests* (e.g. a bugfix gets a regression test first); a trivial doc/config tweak may not.
- A **trivial** task needs no plan at all — it is just a roadmap row + the commit (point the user to the roadmap skill, then do the work).
- The shared Complexity Escalation Gate still applies before a mini-plan or direct trivial-task
  execution. If the proposed approach triggers it, the task is not trivial: stop and run its
  challenger and visible packet. An approved larger support surface means the work is no longer
  lightweight. Use the full standalone-plan path below so the approval has an Ambiguity Register
  owner. Do not add a second decision file to the mini-plan.

Mini-plan shape:

```markdown
# Task T-05: Debounce the search input

> **Type**: Task (lightweight) · **Feature**: search · **CodeOps Artifact Schema**: 1
> **Progress**: 0/3 tasks (0%)

## Objective
Debounce the search box to 300ms to cut redundant queries.

**Smallest viable design:** Reuse the existing input handler and timer utility; add no framework or
shared debounce subsystem.

## Tasks
- [ ] T-05.1 Write a spec test: rapid keystrokes ⇒ one query after 300ms
- [ ] T-05.2 Implement the debounce; verify the test passes
- [ ] T-05.3 Full verify

**Verify**: [project verify command]
```

Everything below is the **full feature** pipeline; skip it for tasks.

## Project configuration

These rules are universal. For build/test/verify commands, package manager, structure, language conventions, and commit scope, read **the project's AGENTS.md (or detected project conventions)**. If there is no AGENTS.md, detect settings from manifest files (`package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Makefile`, `docker-compose.yml`, `pom.xml`, `build.gradle`, `CMakeLists.txt`, `*.sln`, `*.csproj`). Use only facts you can read from those files — never invent settings.

## Hard rules for every generated plan

- **No raw git commands in plan documents.** Plans must not contain `git add/commit/push` or bash blocks running git. When a plan needs to commit, it references the **git-commit skill** (commit) or **git-commit skill in push mode** (commit + push) command. Execution commit behavior is owned by the exec-plan skill.
- **Specification-first testing ordering is non-negotiable** (see Phase 2 and [templates.md](templates.md)): spec tests → red phase → implement → green phase → impl tests → verify.
- **Zero-Ambiguity Gate (Phase 1C) must pass before any plan document except its incrementally
  persisted `00-ambiguity-register.md` is written.** No other exceptions.

## Optional input: requirements documents

When a `requirements/` directory exists with `RD-XX-*.md` files (produced by the make-requirements skill), ask the user whether to base this plan on a specific RD. If they pick one, read it as primary input and shorten the Phase 1.1 interview (the RD answers most questions) — but still do Phase 1.2 current-state analysis and still run the Phase 1C gate. If they decline, run standard Phase 1. When a plan is based on an RD, `01-requirements.md` must include `> **Source**: [RD-XX](../../requirements/RD-XX-feature-name.md)` (in nested layout the relative link resolves within the same feature, e.g. `../../requirements/RD-XX-*.md` under `codeops/features/<f>/`) and `00-index.md` must declare `> **Implements**: RD-NN` — **feature-qualified** (`> **Implements**: <feature>/RD-NN`) in nested layout (used by the roadmap skill).

---

## Phase 1 — Information Gathering (MANDATORY)

### 1.1 Ask clarifying questions

> **ZERO-AMBIGUITY RULE — active from the first question.** Applies to every decision with semantic weight: design, architecture, behavior, scope, edge cases, error messages, naming, file structure. Behavior/scope/data/security decisions ALWAYS gate; cosmetic choices with zero semantic impact are exempt (per the shared gate's semantic-impact exemptions), and low-stakes cosmetic items may be batched. In normal mode, if there is more than one semantically distinct option, the **user decides**. With active auto-design, resolve and record eligible technical decisions under the shared policy; reserved decisions still require the user. Demand concrete, specific answers. Do not fill gaps with assumptions, infer intent, or apply "reasonable defaults" outside that delegated policy. If an answer is vague, ask again with sharper options.

Cover at minimum: **Feature scope** (what it does / does NOT do, boundaries), **Technical context** (affected code, existing patterns, constraints), **Dependencies** (prerequisites, external deps), and **Success criteria** (definition of done, required tests, required docs).

### 1.2 Analyze current implementation

Read relevant source files; identify affected components; find similar/reference patterns; note technical debt; review project docs and AGENTS.md. If `docs/index.md` exists with `techdocs: true` frontmatter, read the relevant architecture sections first (see the techdocs skill).

### 1.3 Confirm scope

Present a scope confirmation (feature, IN scope, OUT of scope, key decisions needed) and ask the user to confirm or adjust. While doing this, start compiling the **Ambiguity Register** — finalized and enforced in Phase 1C.
This confirmation is the authorized scope baseline. Do not place optional suggestions in IN scope,
OUT of scope, or the Ambiguity Register in strict mode. With active scope exploration, collect them
separately in the Scope Expansion Register and wait for `Keep`, `Defer`, or `Discard` rulings.

---

## Phase 1B — Pre-Implementation Re-evaluation

Before writing documents (and again before each execution phase), re-check: Completeness (all requirements + edge cases), Context/Reasoning (can you justify each phase?), Task Granularity (2–4h tasks, independently testable), Dependencies (documented, no cycles), Testing (every task has validation), Architecture (anything >700 lines? plan a split), Scope Boundaries, No Dead Code, and Security (every user-input path identified; injection/auth/authz/rate-limiting/data protection addressed). Establish the smallest viable design as the baseline. Run every material support surface beyond it through the shared Complexity Escalation Gate. Re-evaluate when requirements change or new constraints surface.
Completeness, security, and edge-case review close the requested behavior; they do not authorize
adjacent features. Apply the necessary-correction burden of proof before treating newly discovered
work as required.

---

## Phase 1C — Zero-Ambiguity Gate (NON-NEGOTIABLE HARD GATE)

**This gate MUST pass before any plan document except the incrementally persisted Ambiguity
Register is created. No exceptions, no overrides, no "good enough."** Plans built on ambiguity
produce code the user did not ask for. Every item in every plan document must trace to an explicit,
user-confirmed decision.

The mechanism is the **Ambiguity Register** (`00-ambiguity-register.md`): a numbered inventory of every gap, ambiguity, unstated assumption, and open question, hunted systematically across all 12 categories. The full category checklist, register template, gate-enforcement rules, named-deferral policy, traceability requirement, surface-during-authoring rule, and interactions with the grill-me / upgrade-plan skills are in **[zero-ambiguity-gate.md](zero-ambiguity-gate.md)** — **read it now, before Phase 2.**

That shared protocol also owns the always-active **Complexity Escalation Gate**. A new layer,
dependency, harness, framework, infrastructure surface, cross-cutting refactor, or other material
support mechanism is blocked until its visible stop packet receives an independent challenger
verdict and explicit user approval. Record it as `Technical (complexity escalation)`. Auto-design
cannot approve the larger option.

When opt-in outcome metrics are enabled, record only the enumerated planning result and aggregate
round/decision counts. Never store feature names, questions, decisions, or artifact content.

Gate opens only under the shared gate contract: every row is either `✅ Resolved` or a fully named,
explicitly approved `⏸ Deferred` entry; normal mode has user confirmation of the complete register,
while auto-design mode has complete delegated provenance for every eligible resolution and user
confirmation for reserved ones; nothing is silently deferred; and the header reads
`✅ GATE PASSED`. A deferred decision cannot be implemented
by this plan unless it is later resolved. If zero ambiguities are found, still create the register
file proving the review ran. In normal mode, you may recommend an option but may never decide for
the user. With active auto-design, eligible technical decisions use the shared policy and reserved
decisions remain user-owned.

> **Grounded Options & Recommendations (coding standards → Working style) apply here.** Before presenting options/findings/recommendations: filter out non-viable ones (no strawmen; ≥2 only when ≥2 are genuinely viable, else present the single viable path and name what was rejected), second-guess each, verify any code-modifying option against the actual current code (cite `file:line`), and lead with a recommendation backed by grounded reasoning. Match ceremony to stakes. In normal mode, the user decides; active auto-design resolves eligible technical decisions and escalates reserved ones. **Recommendation hardening:** apply `_shared/recommendation-hardening.md` — for **high-stakes** Phase 1C gate decisions (complex/sensitive-tagged) spawn one independent challenger and reconcile *before* presenting; for all consequential decisions run the in-context layers and close with the `Confidence:` / `Hardening:` disclosure.

---

## Phase 2 — Create Plan Documents

1. Create the plan folder (`plans/<feature-name>/` flat, or `codeops/features/<f>/plans/<plan>/` nested — resolve via the convention doc).
2. Write each document using the templates in **[templates.md](templates.md)** — including its **Reference, don't restate** rule (one owning doc per fact; everything else cites ST-# / 03-doc § / AR-# with at most a one-line gloss). Stamp `00-index.md` and `99-execution-plan.md` with `> **CodeOps Artifact Schema**: 1`.
3. Every design decision, scope decision, and error-handling strategy must carry an `AR #` back-reference to the register (only exceptions: universally obvious facts and zero-semantic-impact formatting).
3b. Every addition accepted through scope exploration must also carry its owning `SE-*`
    back-reference. `Defer`, `Discard`, and `Superseded` entries never produce plan tasks.
4. `07-testing-strategy.md` must contain concrete **Specification Test Cases (ST-*)** with input→expected-output pairs, each traced to a requirement / spec doc / AR entry. Expectations come from the SPEC, never from imagined implementation behavior.
4b. **Confirm the verify command once.** The command that fills every Verify line comes from the
   project's AGENTS.md or manifests — state what you detected and have the user confirm it (an AR
   entry like any decision). If nothing is detectable, ask — **never invent a command**.
5. `99-execution-plan.md` must structure every feature phase with the mandatory three-session ordering (Spec Tests → Implementation → Impl Tests & Hardening), carrying each phase's tasks as a **single checkbox list** — the plan's single source of truth for progress; a task line appears exactly once in the document. The full ordering rules are in [templates.md](templates.md).
6. If you discover a NEW ambiguity while writing, STOP immediately and add it to the register.
   In normal mode get the user's decision; with active auto-design resolve an eligible technical
   item under the shared policy or escalate a reserved item. Only then resume
   (surface-during-authoring rule — see [zero-ambiguity-gate.md](zero-ambiguity-gate.md)).
7. If authoring introduces or enlarges a material support surface, STOP and rerun the shared
   Complexity Escalation Gate. Prior approval covers only the machinery and cost recorded in its
   packet.

**Authoring convergence:** after two post-gate ambiguity batches, pause document creation and
reconfirm the planning target, context artifacts, and modification set. The user chooses whether
to return to discovery or stop with the plan incomplete. Do not keep alternating between document
generation and newly expanded discovery without that explicit scope decision.

Adapt component documents to the project type (Web App, API, Library, CLI, UI Components, Mobile, Compiler, Microservices, Infrastructure, Database, Bug Fix, Refactoring — the typical component breakdowns are listed in [templates.md](templates.md)).

---

## Phase 3 — Quality Checklist

Before finalizing, run the full quality checklist in **[quality-checklist.md](quality-checklist.md)** (Completeness, Granularity, Dependencies, Testing, Specification-First Testing, No Dead Code, Security-First, Zero-Ambiguity, Execution Plan Completeness, Format). The Specification-First, Security-First, Zero-Ambiguity, and Execution-Plan-Completeness blocks are NON-NEGOTIABLE.

---

## Phase 4 — Present Plan Summary

Report what was created:

```markdown
## Plan Created: [Feature Name]

**Location:** `plans/[feature-name]/`

**Documents Created:**
- 00-ambiguity-register.md ✅ (Zero-Ambiguity Gate — all items resolved)
- 00-index.md ✅
- 01-requirements.md ✅
- 02-current-state.md ✅
- [component docs] ✅
- 07-testing-strategy.md ✅
- 99-execution-plan.md ✅

**Summary:** Total Phases: X · Total Sessions: X · Estimated Time: X–X hours

**To begin implementation:** use the exec-plan skill on `[feature-name]`.
```

---

## Phase 5 — Roadmap Sync

After the plan is created, sync the roadmap if one is in play:

- **If `plans/00-roadmap.md` exists:** set the implemented RD's row to stage `Plan Created` (📋) and link the new plan. The link is deterministic — `00-index.md` declares `> **Implements**: RD-NN`, and the row is matched from that line. A plan with no declared RD is linked only when the user explicitly says which RD (or `DEF-n`) it belongs to. Update the roadmap BEFORE moving on.
- **If it does NOT exist:** ask the user whether to create a roadmap. Never auto-create it silently.

See the **roadmap skill** for the full Roadmap Keeper protocol.

---

## Related skills

- **exec-plan skill** — executes a finished plan (`99-execution-plan.md`), commit modes, real-time progress updates, post-completion re-analysis.
- **grill-me skill** — deep disambiguation before planning; its shared understanding feeds into the register as pre-resolved context but does NOT replace the Phase 1C gate.
- **make-requirements skill** — produces the `RD-XX-*.md` documents this skill can consume.
- **roadmap skill** — `make-plan` sets `Plan Created`; the roadmap tracks stages.
- **upgrade-plan skill** — upgrades outdated plans; the gate applies to new decisions only.
- **techdocs skill** — architecture docs read during Phase 1.2 and updated during execution.
- For coding, testing, and git standards, follow **your project's coding standards (AGENTS.md)** and use **git-commit skill** / **git-commit skill in push mode** for commits.
