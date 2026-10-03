---
name: exec-plan
description: >-
  Executes an implementation plan created by the make-plan skill. Use when the user says
  "exec-plan", "run the plan", "execute the plan", "implement the named feature plan",
  or "continue the plan for a feature". Accepts a feature name and an optional commit-mode
  flag: --ask-commit (default, ask after each verified task), --no-commit (never commit),
  or --auto-commit (commit + push after each verified task). Reads the feature's execution plan,
  finds the next incomplete task, and runs the per-task loop (implement, update the execution
  plan immediately, verify, then commit per mode) following specification-first task ordering.
  Under the repo's CodeOps quality policy, a risk-derived quality loop reviews each executed
  phase (reviewer + auditor agents); critical/major findings require an authorized ruling in
  every commit mode, using the user in normal mode or eligible delegated resolution in auto-design.
---

# exec-plan — Execute an Implementation Plan

> **CodeOps Artifact Schema**: 1

## Auto-design option

If `$ARGUMENTS` contains exactly one exact standalone `--auto-design` token before the first `--` sentinel, remove it before resolving targets, paths, or modes; zero occurrences means normal mode, more than one is invalid, and tokens at or after the sentinel are target content; announce `Auto-design active — eligible technical decisions are
delegated and recorded`; then read and apply
[../../_shared/auto-design.md](../../_shared/auto-design.md). Resolve eligible runtime technical
ambiguities under that policy, update owning artifacts and stale downstream state, and re-run
gates before resuming. Propagate only to explicitly invoked supported children; an unsupported child fails closed. This mode does not grant action permission, commit permission, or scope
expansion and does not imply `--auto-commit`. **Normal mode:** without the exact token, every
material runtime choice still requires an explicit user decision; historical delegated records
must not infer delegated authority.

## Scope exploration option

If `$ARGUMENTS` contains exactly one exact standalone `--explore-scope` token before the first `--` sentinel, remove it before resolving targets, paths, or modes; zero occurrences means strict scope, more than one is invalid, and tokens at or after the sentinel are target content; announce `Scope exploration active — optional additions will be proposed for your decision`; then read and apply
[../../_shared/scope-expansion-control.md](../../_shared/scope-expansion-control.md). Strict scope is the default:
do not report or implement optional additions raised during execution or review.
Exploration may create `SE-*` proposals, but only the user may choose `Keep` and authorize a plan
update.

Execute the implementation plan at `plans/$ARGUMENTS/99-execution-plan.md`. The first
argument is the feature name; an optional flag selects the commit mode.

## Execution-entry gate

Before modifying implementation files, directly confirm the plan has its required documents, the
ambiguity register has no open material item, specification tests precede implementation, and no
critical/major preflight finding remains unresolved. Also confirm every material support surface
has specific complexity approval in an applicable AR/PF/RV decision.
`99-execution-plan.md` is the only mutable task-progress authority:

For a plan created before `00-index.md` gained its Minimum-Sufficient Baseline, derive the original
goal and smallest viable design from its existing requirements, specifications, repository
patterns, and approved decisions. Keep that session baseline in every dispatch packet. If it is not
clear, use the runtime ambiguity gate; do not force a document migration or guess.

- `[ ]` is not started;
- `[~]` is implemented with verification pending;
- `[x]` is verified; and
- `[!]` is blocked and includes `Blocked: <short reason>` on the task line.

Never advance sibling tasks. Implement, immediately mark `[~]`, verify, then mark `[x]` only on
success. The primary agent updates the checklist after every delegated result.

A runtime ambiguity blocks affected plan tasks: record it in the ambiguity register and mark each
affected task `[!]` with a short visible reason. In normal mode, present options and obtain the user's explicit decision. With active
auto-design, resolve and record an eligible technical ambiguity under the shared policy; reserved
authority still pauses for the user. If resolution requires changing an upstream artifact outside
the selected plan's documents, present the exact expanded modification set and obtain the user's
approval before editing because auto-design does not expand scope. Resolve the ambiguity, update
the affected plan artifacts, and only then resume.

Before treating a runtime discovery or reviewer remediation as executable, classify it under the
shared scope-expansion protocol. A necessary correction retains the ordinary ambiguity/finding
gate. An optional change is silent in strict scope or a non-executable `SE-*` proposal in
exploration mode; accepting the related finding is not scope authorization.

This skill covers **execution only**. To create a plan, use the make-plan skill.

## Resolve the plan path first (layout-aware)

Determine the layout via **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)**:

- **Flat layout** (no marker): the plan is at `plans/$ARGUMENTS/99-execution-plan.md` — as flat layout always has.
- **Nested layout** (marker present): the plan is under a feature —
  `codeops/features/<f>/plans/<plan>/99-execution-plan.md`. If the target feature/plan is ambiguous,
  **ask the user** (never guess). A non-trivial **task** mini-plan lives at the same nested path and
  executes identically (see "Lightweight tasks" above). Everywhere below that says
  `plans/$ARGUMENTS/` means this resolved plan path.

## Commit modes

| Flag | Behavior |
|------|----------|
| *(none)* / `--ask-commit` | **Default.** After each verified task, ask the user whether to commit. |
| `--no-commit` | Never commit, never ask. Pure implementation. |
| `--auto-commit` | Automatically commit + push (via the `git-commit` skill in push mode) after each verified task. |

Full prompt wording, end-of-plan reminders, and commit-message format live in
[commit-modes.md](commit-modes.md) — read it before the first commit decision.

## Lightweight tasks (both layouts)

A **non-trivial task** has a single mini-plan at the resolved task path (flat:
`plans/<task-slug>/99-execution-plan.md`; nested:
`codeops/features/<f>/plans/<task-slug>/99-execution-plan.md`). Execute it **exactly like a feature
plan** — same per-task loop, same real-time update mandate, same commit modes — it is just a
smaller `99-execution-plan.md` (objective + checklist + verify, no `00–07` set). Specification-first
ordering still applies *when the task warrants tests* (e.g. a bugfix's regression test).

A complexity escalation ends the mini-plan path before any approval can become executable. Mark
the affected task `[!]`, preserve any implementation diff without marking it verified, and switch
to make-plan's full standalone-plan path. Its `00-ambiguity-register.md` owns the complete stop
packet and direct user decision. Do not accept or store a complexity approval only in the
mini-plan; resume execution only from the resulting full plan after its gates pass. This also
applies when the escalation is first found by the post-task review.

A **trivial task** has **no plan document** to run: do the work directly, then record it as a
`T-NN` roadmap row + the commit (no execution-plan loop). The task model and routing rule live in
**[../../_shared/layout-convention.md](../../_shared/layout-convention.md)** — the lane exists in both
layouts (flat gained it in 3.2.0).

## Execution mode — inline first

Phases run **inline** on the session model by default; a phase is dispatched as ONE pinned-model
executor only when its routing tag maps to a cheaper model AND the phase amortizes the executor
bootstrap. Per-task or parallel dispatch happens only on the user's explicit request (it costs
more tokens, not fewer). Full rules in [execution-protocol.md](execution-protocol.md).

## Execution protocol (summary)

Read [execution-protocol.md](execution-protocol.md) for the full step-by-step protocol,
the specification-first ordering rules, the real-time update mandate, and the session
summary template. The essentials:

### Step 1 — Load the plan

1. Read `plans/$ARGUMENTS/99-execution-plan.md`.
2. Find incomplete tasks — both `[ ]` and implemented-but-unverified `[~]`; read supporting specs
   in `plans/$ARGUMENTS/`.
3. Determine the starting point: a `[~]` task is resumed first (re-verify, then promote or keep
   fixing); otherwise the first `[ ]` task.
4. If the plan is missing/empty/already complete, **STOP** — see the load table in
   [execution-protocol.md](execution-protocol.md). Generally suggest the make-plan skill.

**Schema check:** a legacy `CodeOps Skills Version` stamp or missing schema triggers a read-only
upgrade assessment; ask before migration or execution with recorded compatibility risk. Never
silently upgrade.

### Step 2 — Execute tasks (per-task loop)

For each task, in order:

1. **Run the minimum-sufficient checkpoint, then implement.** Compare the intended work with the
   original goal and smallest viable solution. If it triggers the shared Complexity Escalation
   Gate in `../../_shared/zero-ambiguity-gate.md`, mark the task `[!]`, run the independent
   challenge, show the full visible stop packet, and wait for explicit user approval before adding
   the larger machinery. Auto-design cannot approve it. Otherwise implement the task following the
   technical specs in `plans/$ARGUMENTS/`.
2. **🚨 Immediately update `99-execution-plan.md`** — completion marks are **two-stage**: mark the
   task `[~]` with an implemented-timestamp in its phase task list (or, in a pre-3.3.0 plan, in
   the Master Progress Checklist — see the protocol's dual-format detection) and bump the Progress
   counter / Last Updated stamp as soon as implementation finishes (crash-safe), promote it to
   `[x]` only after its verification passes. A task never shows `[x]` with a failing verify.
3. **Verify** — run your project's verify command (from the project's AGENTS.md, or detected
   project conventions), output captured per the protocol's **Verify-output capture rule**
   (PASS one-liner; on failure the last 50 log lines + log path). Pass → promote `[~]` → `[x]`;
   fail → fix and re-verify (mark stays `[~]`). Immediately after every `[x]` promotion, run the
   protocol's read-only progress-bar command for the selected plan and show its exact output in the
   next commentary update. Only `[x]` contributes to the displayed completion count.
4. **Commit** per the active commit mode (see [commit-modes.md](commit-modes.md)) — the commit
   gate keys off `[x]`.
5. **Techdocs check (after each phase):** if the phase introduced architectural changes and
   techdocs exist, do an incremental update via the techdocs skill.
6. Continue until all tasks are complete. (OpenCode auto-compacts context — no manual
   threshold handling is needed.)

> **🚨 Specification-first task ordering — non-negotiable.** Within each feature:
> `spec tests → verify red → implement → verify green → impl tests → full verify`.
> Never write implementation code before its spec tests exist, and never edit a spec test to
> match the implementation (the implementation is wrong, not the test). Details and the
> compressed single-session form are in [execution-protocol.md](execution-protocol.md).

> **🚨 Zero-ambiguity during execution.** If you hit any detail not covered by the plan docs or
> `00-ambiguity-register.md`, STOP and record it. In normal mode, present options and wait for an
> explicit user decision. With active auto-design, resolve an eligible technical choice under the
> shared policy or escalate a reserved choice. Record the authorized resolution in
> `00-ambiguity-register.md` (tag `(runtime)`), update affected plan documents, then resume.
> Never guess.

> **🚨 Complexity escalation during execution.** A material new layer, dependency, harness,
> framework, infrastructure surface, cross-cutting refactor, or future-proofing is a reserved stop
> even when the plan leaves implementation freedom. Apply the shared gate's prominent packet and
> challenger requirement. Record an approved runtime escalation in the Ambiguity Register as
> `Technical (complexity escalation)`.

> **Grounded Options & Recommendations (coding standards → Working style) apply here.** Before presenting options/findings/recommendations: filter out non-viable ones (no strawmen; ≥2 only when ≥2 are genuinely viable, else present the single viable path and name what was rejected), second-guess each, verify any code-modifying option against the actual current code (cite `file:line`), and lead with a recommendation backed by grounded reasoning. Match ceremony to stakes. In normal mode, the user decides; active auto-design resolves eligible technical decisions and escalates reserved ones. Apply the recommendation-hardening protocol (`_shared/recommendation-hardening.md`) to consequential recommendations; escalate to an independent challenger only when the decision is genuinely high-stakes.

### Step 3 — Session wrap-up

1. Finish the current task before stopping.
2. **🚨 First, update `99-execution-plan.md`** with all completed tasks (before anything else).
3. Run the verify command.
4. Handle the commit per the active commit mode.
5. Report a session summary (must state `Execution Plan Updated: ✅`). Template in
   [execution-protocol.md](execution-protocol.md).

To resume in a later session, just run `/exec-plan $ARGUMENTS` again — the execution plan is the
source of truth and tells the skill where to pick up.

## Quality loop (profile-gated)

Every non-trivial executed phase (and task mini-plan) ends with a post-phase quality review under
strict defaults unless an allowed adaptive-mode policy explicitly disables it. Activation rules,
lenses, supersession, dispatch packets, and budget caps are defined
once in **[../../_shared/quality-profile.md](../../_shared/quality-profile.md)** — this skill
links to them, never restates them.

The flow: the protocol records a phase-start ref when the phase begins; after the phase's last
task verifies, the correctness reviewer and any active auditors are dispatched **in parallel** on
the phase diff, their findings are merged and presented in severity-grouped batches, and each
ruling is recorded in the durable finding artifact.

> **🚨 Finding gate (load-bearing).** In normal mode, 🔴 CRITICAL and 🟠 MAJOR findings PAUSE
> execution for the user's ruling in ALL commit modes. With active auto-design, select and record
> an eligible technical fix, but never waive or dismiss a finding; reserved decisions still pause
> for the user. Auto-commit never bypasses the applicable authority gate. 🟡 MINOR findings are
> report-only. Accepted fixes are implemented, verified, follow-up-committed per the commit mode,
> and (after 🔴/🟠 fixes) re-reviewed ONCE on the fix diff — never a third time.
> Reviewers receive the active scope mode. Optional remediations are omitted in strict scope and
> become separate `SE-*` proposals during exploration; they are never accepted merely by a finding
> ruling or auto-design resolution.
> Escaped, unapproved complexity is at least a 🟠 MAJOR finding. It uses the shared Complexity
> Escalation Gate and cannot be waived by `quality.independentReview: false` once detected.

Step-by-step mechanics — the phase-start ref, spec-author dispatch, the post-phase quality step,
and emission points — live in [execution-protocol.md](execution-protocol.md).

## Roadmap sync

If a roadmap exists (`plans/00-roadmap.md` flat, or the feature's
`codeops/features/<f>/00-roadmap.md` nested), keep it in sync via the roadmap skill (update-first,
before verify/commit/next): set the RD/task row to `Executing` (🔄) on start, `Done` (✅) on
completion, and `Blocked` (⛔) with a nested `↳ DEF-n` sub-row when a blocking dependency is
discovered. **Nested layout:** after each per-feature transition, **cascade** to the portfolio
`codeops/00-roadmap.md` (re-roll that feature's row) before proceeding — per the roadmap skill's
cascade mandate. If no roadmap exists, these hooks are inert.

## Error handling

Brief rules for verification failure, plan deviation, and mid-task interruption are in
[execution-protocol.md](execution-protocol.md) — consult it when something goes wrong.

## Post-completion hooks (all tasks done)

1. Handle the end-of-plan commit per the active commit mode (see [commit-modes.md](commit-modes.md)).
2. **Techdocs:** if techdocs exist, do a comprehensive update via the techdocs skill; otherwise
   ask whether to create them.
3. **Re-analyze:** ask whether to re-analyze the project and update the project's AGENTS.md via
   the `analyze-project` skill.
4. **Roadmap:** set the RD row to `Done` via the roadmap skill if a roadmap exists.

## Conventions

- Follow your project's coding and testing standards (the project's AGENTS.md, or detected
  project conventions). If no AGENTS.md exists, detect build/test/verify commands from manifest
  files and use only facts you can read — do not invent settings.
- Commit using the `git-commit` skill (commit only) or the `git-commit` skill in push mode (commit + push), or a normal git commit.
- Related skills: make-plan (creation), upgrade-plan (outdated plans), preflight, roadmap, techdocs.
