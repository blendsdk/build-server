# Auto-Design Authority Policy

> **Policy version**: 1
> **CodeOps Artifact Schema**: 1

`--auto-design` delegates eligible technical design decisions to CodeOps for one workflow chain.
It preserves ambiguity closure: it changes who may resolve an eligible ambiguity, never whether
the ambiguity must be found, recorded, traced, challenged, and verified.

## Invocation contract

Only exactly one standalone token `--auto-design` before the first `--` end-of-options sentinel
activates this policy. Zero occurrences means Default mode; more than one is invalid and must stop
with a usage correction. A token at or after the sentinel is target content, not an option.
Lookalikes such as `--auto-designer`, `--auto-design=true`, or bare `auto-design` do not activate
it. A supporting skill removes the one recognized token before resolving feature names, paths,
targets, or other options, announces activation, and assigns a root invocation ID. Explicitly
invoked supporting children inherit a downward-only context:

```text
mode: auto-design
root invocation ID: <stable ID for this workflow chain>
parent workflow: <invoking supported workflow>
policy version: 1
delegated categories: <parent's eligible classes or a strict subset>
reserved categories: <the complete reserved set>
permission state: <unchanged action and commit permissions>
```

A child may narrow authority but never widen it. An unsupported child fails closed and uses normal
authority rules. A later independent invocation is in **Default mode** unless its own arguments
contain `--auto-design`. The mode is never persisted as a repository or global default.

## Default mode

Without `--auto-design`, existing behavior is unchanged: every material semantic choice requires
an explicit user decision or explicit named deferral.

## Eligibility boundary

CodeOps may decide only when a choice stays within confirmed goals, product behavior, scope,
constraints, and acceptance criteria; concerns an implementation mechanism; contradicts no user
decision or governing artifact; and creates no reserved-authority consequence.

Eligible classes include algorithms, data structures, internal architecture and interfaces,
compiler and optimizer mechanisms, failure and recovery design, concurrency and consistency,
persistence and reversible migration mechanisms, security mechanisms within an approved policy,
testing strategy, performance engineering, and implementation sequencing.

## Reserved authority

Always escalate product behavior or scope, priorities and acceptance criteria, access and security policy,
data ownership or retention, legal/ethical/compliance or risk acceptance, financial exposure,
budget/deadline commitments, paid-vendor choices, public compatibility breaks,
destructive migration, credentials, spending, deployment/publication, destructive or irreversible
external actions, external communication, and equally defensible designs that create materially
different products.

The shared Complexity Escalation Gate is also reserved authority. Auto-design may select the
smallest viable implementation, but it cannot approve a larger layer, dependency, harness,
framework, infrastructure surface, or other escalation. Only the user's explicit approval of the
gate packet authorizes that larger option.

`--auto-design` does not grant action permission. It does not authorize implementation outside the
invoked workflow, file-scope expansion, commits, pushes, `--auto-commit`, installation, purchases,
deployment, publication, destructive operations, credentials use, or external-system changes.

Scope expansion remains separately user-owned under
[`scope-expansion-control.md`](scope-expansion-control.md). Auto-design cannot activate optional
scope exploration, choose `Keep` for an `SE-*` proposal, revive discarded scope, or reinterpret an
optional addition as an eligible technical decision.

## Strongest-option procedure

1. Gather repository evidence, domain knowledge, constraints, and failure conditions.
2. Generate every genuinely viable option, actively searching for a non-obvious alternative.
   When only one option survives evidence, name rejected candidates and why; never invent a
   strawman merely to create a comparison.
3. Apply forced reframing: 10× budget, contrarian expert, obsolescence, and pre-emptive challenge.
4. Compare correctness, soundness and safety, objective fit, maintainability, verifiability,
   performance, compatibility, operational recovery, delivery risk, proportional complexity, and
   future evolution.
5. State the strongest counterargument and set confidence.
6. Require a blind independent challenger for complex, sensitive, high-impact, or
   difficult-to-reverse choices. Material divergence, unavailable required review, or insufficient
   confidence triggers bounded escalation; it never silently accepts or waives risk.
7. Select the best-supported option. Strongest means most likely to make the whole project
   succeed, not the most sophisticated design.

## Durable resolution

The owning ambiguity or decision artifact records complete eligibility and provenance, including
rejected alternatives and reopen triggers:

```text
Authority: AI — delegated by --auto-design
Eligibility: <class and boundary rationale>
Objective: <governing success objective>
Decision: <selected option>
Evidence: <repository/domain facts and constraints>
Rejected alternatives: <viable alternatives and reasons>
Strongest counterargument: <best case against the choice>
Confidence: High | Med | Low — <what would change it>
Hardening: <result and challenger verdict when required>
Policy version: 1
Root invocation ID: <ID>
Reopen triggers: <observable invalidation conditions>
```

The canonical delegated marker may occupy an existing `User Decision` column for backward
compatibility. Do not create a parallel decision database or duplicate rationale in traceability.

## Bounded escalation

Research and challenge first. If a choice is reserved, constraints conflict, material evidence
remains unavailable, concerns cannot be separated, or no option is defensible, stop once per root
cause with the exact decision, boundary/evidence failure, strongest available recommendation, and
minimum user input needed. It must never guess or loop repeatedly over the same evidence.

## Invalidation

When new evidence breaks an assumption or a reopen trigger fires, reopen the owning decision,
mark affected downstream specifications, tests, tasks, implementation, and verification stale,
repeat this policy, and rerun applicable readiness and semantic gates.

## Supported workflows

The closed allowlist is `make-requirements`, `make-plan`, `preflight`, and `exec-plan`. Adding a
workflow requires specification coverage and deterministic integration checks.
