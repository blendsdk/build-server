---
name: upgrade-plan
description: Upgrade an existing CodeOps requirements set, specification, plan, or project from a legacy artifact format to the current schema and quality standards. Use for upgrade my plan, upgrade requirements, migrate CodeOps artifacts, or bring project artifacts up to date. Assesses and previews changes, closes content ambiguities before structural migration, preserves user-authored semantics and progress, and verifies the result without advancing the roadmap.
---

# Upgrade CodeOps artifacts

The current CodeOps artifact schema is `1`. Historical Claude CodeOps `3.x` stamps describe the producing skill release, not this schema. Treat them as legacy input requiring assessment, not as numeric predecessors of schema 1.

## Scope

Upgrade content and structure in place. Layout moves belong to `setup-codeops`. Never combine a layout migration and semantic/schema upgrade into one irreversible operation.

Targets may be a requirements set, one feature plan, one feature, or the whole CodeOps project. Resolve flat/nested paths via [../../_shared/layout-convention.md](../../_shared/layout-convention.md).

## Phase 1 — Read-only assessment

1. Read every target artifact and its links.
2. Detect `CodeOps Artifact Schema: 1`, legacy `CodeOps Skills Version`, partial migrations,
   obsolete `traceability.json` files, missing RD-to-plan declarations, and contradictory stamps.
3. Run current requirement, specification, plan, domain-lens, and content-quality checks.
4. Inventory user-owned semantics, completed/in-progress task marks, custom notes, identifiers, and links that must survive byte-for-byte or meaning-for-meaning.
5. Produce an upgrade report listing additions, structural changes, semantic gaps, preserved content, risks, and rollback/recovery method.

If current semantic gates pass, every plan declares its implemented RDs, and every execution plan
uses the four checklist markers, report no upgrade needed. Treat obsolete traceability files as
deletion candidates after confirming no external consumer depends on them; do not migrate their
graph state into a replacement platform.

For a whole nested `codeops/` project, preview the deterministic structural portion with:

```bash
python3 "${CODEOPS_PLUGIN_ROOT}/scripts/codeops_plan_migrate.py" ./codeops
```

If the preview has no `BLOCKED` entries and the user approves it, rerun with `--apply`. The
migrator never resolves content ambiguities: return blocked mappings or legacy blocker semantics
to this skill before applying.

## Phase 2 — Approval and content-quality gate

Present the report before writing. The user may approve all, request details, narrow scope, or decline.

After approval, run [content-quality-gate.md](content-quality-gate.md). Structural modernization must not hide vague or contradictory content. Record every material gap as an ambiguity, resolve it explicitly, and update its authoritative owner before migration.

## Phase 3 — Structural migration

Follow [upgrade-checklists.md](upgrade-checklists.md):

- add `> **CodeOps Artifact Schema**: 1` where artifact stamps belong;
- add or update each plan's single `> **Implements**:` declaration;
- preserve completed `[x]` and implemented `[~]` task states;
- convert a blocked legacy task to `[!]` with a short visible reason;
- preserve technical decisions, requirements, criteria, rationale, and notes;
- update renamed skill/project-guidance references;
- add missing ambiguity, domain, security, verification, and project-tracking sections; and
- never silently renumber identifiers that external artifacts reference.

Use small recoverable edits. Git history is the rollback and recovery mechanism.

## Phase 4 — Verification

Run the plan parser and the project's verification commands:

```bash
python3 "${CODEOPS_PLUGIN_ROOT}/scripts/codeops_plan.py" --root . --json
```

Then verify document/task/requirement counts and user semantics are preserved; material
ambiguities are resolved or explicitly approved deferrals; tests precede implementation; no task
is marked `[x]` without passing verification; roadmap lifecycle state is unchanged except for
approved drift repair; and the Git diff contains only the approved migration.

Report old formats, new schema, files changed, ambiguities resolved, RD-to-plan coverage, preserved
progress, and residual risk. Do not auto-advance lifecycle stages.
