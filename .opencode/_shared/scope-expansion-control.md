# Scope Expansion Control

> **CodeOps Artifact Schema**: 1

This shared protocol keeps optional product additions separate from the work the user actually
authorized. It is used by `make-plan`, `preflight`, and `exec-plan`. Each workflow links here
instead of defining its own scope-expansion semantics.

## Activation

Strict scope is the default. Optional expansion discovery is enabled only by exactly one standalone
token `--explore-scope` before the first `--` end-of-options sentinel. Remove that token before
resolving targets, paths, or modes. Zero occurrences means strict scope, more than one is invalid,
and tokens at or after the sentinel are target content. Lookalikes such as `--explore-scopes`,
`--explore-scope=true`, and bare `explore-scope` do not activate the mode.

The flag is invocation-scoped. It is never persisted as a repository or global default. A child
workflow or reviewer receives the mode only when its dispatch packet explicitly carries it; missing
or invalid mode context fails closed to strict scope.

These examples are normative:

| Arguments | Result |
|---|---|
| `target` | `strict` |
| `--explore-scope target` | `explore` |
| `--explore-scope --explore-scope target` | `invalid` |
| `-- --explore-scope` | `strict`; the token is target content |
| `--explore-scope -- --explore-scope` | `explore`; the later token is target content |
| `--explore-scopes`, `--explore-scope=true`, or `explore-scope` | `strict` |

## Prime directive

Record the authorized scope baseline before analysis. In strict scope:

- stay inside that baseline;
- do not report optional additions, speculative improvements, gold-plating, or additional product
  behavior;
- do not turn optional ideas into findings, requirements, specifications, tests, tasks, blockers,
  readiness failures, or roadmap work; and
- optional ideas must not affect finding counts, severity, verdicts, progress, or execution.

Silence applies only to new optional proposals. Existing content that already exceeds the
authorized baseline remains an in-scope scope-creep defect and must be reported so it can be
removed or explicitly authorized.

## Necessary correction or optional expansion

A **Necessary correction** is the smallest correction for which grounded causal evidence shows
that omission makes the explicitly requested behavior incorrect, unsafe, or infeasible and that
there is no compliant solution wholly inside the authorized scope. The agent carries the burden of proof
and must always report the evidence and why the correction is necessary. Reporting necessity
does not authorize expanding the modification set or applying the correction.

A credible unresolved material risk to correctness, safety, or feasibility is a **blocking
uncertainty** requiring bounded investigation. It is neither silently hidden as optional nor
promoted into implementation. If evidence remains speculative or the requested behavior can still
work correctly, safely, and feasibly without the addition, the idea is optional.

## Exploration mode

With active `--explore-scope`, collect genuinely useful optional additions after completing the
in-scope analysis. Do not mix them into ordinary ambiguity questions or findings. Present one
compact numbered Scope Expansion Register so the user can rule on every proposal.

### Register format

Create the register only when at least one proposal exists. Resolve its collision-free path through
[`_shared/layout-convention.md`](layout-convention.md). IDs are artifact-local, monotonic, never reused,
and allocated as `SE-001`, `SE-002`, and so on. Preserve append-only history rather than
overwriting an earlier ruling. The register header records the governed target type, its
normalized project-relative path, and the confirmed scope baseline or later baseline revision. Reject an
absolute or parent-traversing target path.

The proposal table is the current-state view of every user decision:

| ID | Proposed addition | Origin | Why it is outside scope | Impact | Recommendation | Current state |
|---|---|---|---|---|---|---|
| `SE-001` | Concrete new behavior, artifact, dependency, or subsystem | Finding, assumption, review, or scenario | Boundary exceeded | Cost, complexity, compatibility, operations, and maintenance | `Keep`, `Defer`, or `Discard` with rationale | `Proposed` until the user rules |

Every ruling appends a decision event. `SEV-*` IDs are register-local, monotonic, never reused, and
allocated as `SEV-001`, `SEV-002`, and so on. Append order is the ordering authority, so the last
valid appended event determines current state. Never edit, delete, or reorder an earlier event:

| Event ID | SE ID | Timestamp | From state | Decision | Authority and evidence | Owner | Revisit trigger | Replacement or reversal |
|---|---|---|---|---|---|---|---|---|
| `SEV-001` | `SE-001` | ISO 8601 | `Proposed` | `Keep`, `Defer`, `Discard`, or `Superseded` | User ruling or other explicit authority plus its provenance | Required for `Defer` | Required for `Defer` | Required when superseding or reversing |

Accepted proposals also maintain dependency-oriented authority links:

| SE ID | Derived artifact | Relation or kind | Current state | Evidence source |
|---|---|---|---|---|
| `SE-001` | Requirement, specification, test, task, implementation evidence, verification, or roadmap item | `authorizes` or `invalidates` | Current, stale, or superseded | Durable artifact evidence |

Implementation linkage belongs in plan or other artifact evidence and never in source comments.
Recompute the proposal table's current state from the latest valid event; the event log
remains authoritative history.

### State transitions

Only these lifecycle transitions are valid:

| From state | Allowed next state |
|---|---|
| `Proposed` | `Keep`, `Defer`, `Discard` |
| `Keep` | `Superseded` |
| `Defer` | `Keep`, `Discard`, `Superseded` |
| `Discard` | `Keep`, `Superseded` |
| `Superseded` | *(terminal)* |

A deferred entry may transition only after its recorded trigger is unambiguously satisfied or the
user explicitly requests reconsideration. A discarded entry may transition to `Keep` only with new
evidence and renewed explicit authorization. A reversal is recorded as a new event; it never
rewrites the earlier event.

The stored decision vocabulary is:

- **`Keep`** — explicitly accepted into authorized scope. Only `Keep` may produce a requirement,
  specification, test, executable task, implementation, or roadmap item. Every derived artifact
  back-references its `SE-*` authority.
- **`Defer`** — records a named owner and observable revisit trigger. It remains dormant and
  non-executable on ordinary resume. Re-present the same `SE-*` ID only when unambiguous trigger
  evidence exists or the user explicitly requests reconsideration; re-presentation never implies `Keep`.
  Unverifiable or ambiguous trigger evidence leaves it dormant.
- **`Discard`** — remains durable, non-executable context. Reconsideration requires new evidence
  and renewed authorization under the same ID; never erase the earlier decision.
- **`Superseded`** — the proposal or its accepted scope is no longer current, with its replacement
  or reversal recorded.

Bulk acceptance is valid only when the user explicitly accepts the listed `SE-*` recommendations.
Silence, `--auto-design`, `--auto-commit`, a finding ruling, or permission to apply fixes never
counts as expansion authority.

## Findings and fix permission

Finding resolution and expansion authorization are separate. A `PF-*`, `RV-*`, `SA-*`, or `PE-*`
finding may link to an `SE-*` proposal, but accepting the finding selects only its in-scope
resolution. Commands such as `apply all fixes` do not authorize optional expansion proposals;
they apply only in-scope fixes and proposals already ruled `Keep`.

An optional proposal never blocks merely because it is deferred, discarded, or undecided. A
necessary correction or blocking uncertainty may block because the requested behavior itself has
not been shown correct, safe, and feasible.

## Resume, reversal, and invalidation

Every resume loads the applicable register before analysis. Preserve all IDs, decisions, evidence,
owners, triggers, and derived links. Never reintroduce a discarded proposal as a new ID or re-open
it without new evidence and renewed authorization.

When the user reverses `Keep`, stop affected execution. Use recorded authority links to invalidate
only dependency-traced downstream specifications, tests, tasks, implementation, and verification.
Mark pending or in-progress derived tasks superseded and current downstream state stale; historical
evidence stays intact. The removed work must not remain executable or apparently ready. Require an
explicitly authorized safe removal or remediation decision, and never auto-revert irreversible or
externally applied work.

## Interaction with auto-design

`--auto-design` chooses eligible technical designs only inside already authorized scope.
`--auto-design` cannot choose `Keep`, revive `Discard`, broaden a modification set, suppress a
necessary correction, or treat optional product behavior as technical authority. The two flags may coexist:
exploration proposes additions, the user owns their scope rulings, and auto-design may
operate inside an accepted addition only after `Keep` is recorded.

## Workflow bindings

- **make-plan:** trace every planned item to the original scope baseline or a kept `SE-*` entry.
  Optional ideas are silent in strict scope and register proposals in exploration mode before any
  plan artifact promotes them.
- **preflight:** audit defects in the selected target regardless of mode. Optional remediations are
  silent in strict scope or linked to `SE-*` proposals in exploration mode. A finding decision is
  never the proposal decision.
- **exec-plan:** classify runtime ambiguities and reviewer remediations before implementation.
  Optional fixes are silent in strict scope or proposed through the register in exploration mode;
  only kept proposals may enter the executable plan.
