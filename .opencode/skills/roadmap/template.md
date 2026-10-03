# Roadmap Template & Tracker Reference

Resolve where the roadmap lives via **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)**:

- **Flat layout** (no marker): a single roadmap at `plans/00-roadmap.md` — exactly as before.
- **Nested layout** (marker present): a **per-feature roadmap** at
  `codeops/features/<f>/00-roadmap.md` (the template below, scoped to one feature, **plus task
  rows**) and a **portfolio roadmap** at `codeops/00-roadmap.md` (one row per feature — see
  [The portfolio roadmap template](#the-portfolio-roadmap-template)).

The per-feature roadmap and the flat roadmap share the same template, columns, and legend; use it
verbatim when creating either. The portfolio is a separate, higher-altitude template.

## The single / per-feature roadmap template

````markdown
# Roadmap: [Feature-Set Name]

> **Feature-Set**: [Feature-Set Name]
> **Status**: In Progress
> **Created**: [YYYY-MM-DD]
> **Last Updated**: [YYYY-MM-DD HH:MM]
> **Progress**: [Done RDs] / [Total RDs] ([Z]%)
> **CodeOps Artifact Schema**: 1

## Legend

⬜ Backlog · ✏️ RD Drafted · 🔎 RD Preflighted · 📋 Plan Created · 🔬 Plan Preflighted · 🔄 Executing · ✅ Done · ⛔ Blocked · ⏸️ Deferred

## Tracker

| ID | Title | RD | Plan | Stage | Status | Last Updated | Depends-on / Blocker |
|----|-------|----|------|-------|--------|--------------|----------------------|
| RD-01 | [Title] | [link] | [link] | Done | ✅ | [date] | — |
| RD-02 | [Title] | [link] | [link] | Executing | 🔄 | [date] | — |
| RD-03 | [Title] | [link] | — | Blocked (was: RD Preflighted) | ⛔ | [date] | waiting on DEF-1 |
| ↳ DEF-1 | [Discovered dependency] | — | [link] | Plan Created | 📋 | [date] | blocks RD-03 |
| RD-04 | [Title] | — | — | Backlog | ⬜ | [date] | — |
````

## Header fields

- **Feature-Set** — display name; the slug form is the `plans/_archive/<slug>/` folder name on archive.
- **Status** — `In Progress` while active; `Archived` once `archive_roadmap` runs.
- **Created** / **Last Updated** — `Last Updated` bumps on every transition.
- **Progress** — `[Done RDs] / [Total RDs] ([Z]%)`; counts only top-level `RD-*` rows that reached
  `Done`. `T-*` task rows and `↳ DEF-n` sub-rows never count toward the fraction. A Progress value
  that is **not** this computed shape (e.g. `n/a`, or `history archived (no active RD tracker)`) is
  treated as hand-maintained: the sync engine preserves it verbatim and does not touch it. A
  computed value may carry a trailing ` · <note>` annotation (e.g. `2 / 2 (100%) · hardening done`);
  the engine refreshes the count and keeps the ` · …` suffix.
- **CodeOps Artifact Schema** — the artifact-schema stamp (currently `1`).

## Tracker columns

| Column | Meaning |
|--------|---------|
| ID | `RD-NN` for a top-level requirement; `T-NN` for a lightweight task (nested layout — separate per-feature namespace, see the task-lane spec); `↳ DEF-n` for a nested discovered dependency. |
| Title | Short human label. |
| RD | Relative link to `requirements/RD-*.md`, or `—` if not yet drafted. |
| Plan | Relative link to the plan folder's `00-index.md`, or `—` if no plan yet. |
| Stage | One of the 9 lifecycle states (text form). A `Blocked` row records its prior stage in-cell — `Blocked (was: <stage>)` — so unblocking never depends on memory. |
| Status | The matching emoji for the stage (see legend). |
| Last Updated | Date (or date + time) of the last change to this row. |
| Depends-on / Blocker | Terse. Name a planned prerequisite (`depends on RD-03`) or, for a `Blocked` row, the `DEF-n` being waited on — a short phrase, never a paragraph. |

Links are relative to the roadmap file itself. Flat layout (`plans/00-roadmap.md`): RDs are
`../requirements/RD-NN-*.md`, plans are `<plan>/00-index.md`. Nested layout
(`codeops/features/<f>/00-roadmap.md`): RDs are `requirements/RD-NN-*.md`, plans are
`plans/<plan>/00-index.md`.

## Row ordering & discipline

- **Order rows by dependency** — put prerequisites above the rows that depend on them, so the list
  is worked top-to-bottom, one row at a time, until the roadmap is done. Capture a *planned*
  dependency terse in the `Depends-on / Blocker` cell (e.g. `depends on RD-01`); a *discovered*
  blocker becomes a `↳ DEF-n` sub-row with `waiting on DEF-n` in the cell.
- **Keep it a table.** A roadmap is only its table (the per-feature/flat roadmap is header + Legend
  + Tracker; the portfolio adds Features + Archived). A row's cells are short status phrases, never
  narrative — per-item history and rationale live in the plan folder and git, not here. There is no
  running-notes log; a stage regression is explained in the git commit that makes it.

## Worked example

```markdown
# Roadmap: Billing Platform

> **Feature-Set**: Billing Platform
> **Status**: In Progress
> **Created**: 2026-05-01
> **Last Updated**: 2026-05-14 16:20
> **Progress**: 1 / 4 (25%)
> **CodeOps Artifact Schema**: 1

## Legend

⬜ Backlog · ✏️ RD Drafted · 🔎 RD Preflighted · 📋 Plan Created · 🔬 Plan Preflighted · 🔄 Executing · ✅ Done · ⛔ Blocked · ⏸️ Deferred

## Tracker

| ID | Title | RD | Plan | Stage | Status | Last Updated | Depends-on / Blocker |
|----|-------|----|------|-------|--------|--------------|----------------------|
| RD-01 | Invoicing core | [RD-01](../requirements/RD-01-invoicing.md) | [invoicing](invoicing/00-index.md) | Done | ✅ | 2026-05-10 | — |
| RD-02 | Payment gateway | [RD-02](../requirements/RD-02-payments.md) | — | Blocked (was: RD Drafted) | ⛔ | 2026-05-14 | waiting on DEF-1 |
| ↳ DEF-1 | Secrets vault integration | — | [vault](vault/00-index.md) | Executing | 🔄 | 2026-05-14 | blocks RD-02 |
| RD-03 | Dunning emails | [RD-03](../requirements/RD-03-dunning.md) | — | RD Preflighted | 🔎 | 2026-05-12 | — |
| RD-04 | Usage metering | — | — | Backlog | ⬜ | 2026-05-01 | — |
```

Here RD-02 is `Blocked` by the nested `DEF-1` sub-row; once DEF-1 reaches `Done`,
RD-02 resumes from its prior stage.

In a **nested-layout** repo this same roadmap lives at `codeops/features/<f>/00-roadmap.md` and
may also carry `T-NN` **task rows** beside its RD rows (a trivial task is just a row; a non-trivial
one links a single mini-plan). RD and `T` ids are separate per-feature namespaces and never collide.

## Open follow-ons (optional)

When every `RD-*` row is `Done` but post-completion work is still outstanding, record it in an
optional `## Open follow-ons` section **below the Tracker** — so the feature reads as "shipped, with
tail work" rather than either fully done or artificially incomplete:

```markdown
## Open follow-ons

| Item | Scope | Stage | Status |
|------|-------|-------|--------|
| `usage-export` | Production usage export, deferred post-launch | Backlog | ⬜ no plan yet |
```

The table's **last column must be `Status`**. A follow-on is *open* when its Status cell contains no
✅. While any follow-on is open, the sync engine rolls the feature up to `🔄` (not `✅`) and excludes
it from the portfolio `Features` done count — but follow-on rows **never** count toward the RD
fraction (a feature with 2/2 RDs Done and an open follow-on still reads `2/2 RDs`). A section whose
table is not `Status`-last is ignored. Once every follow-on row is ✅ (or the section is removed),
the feature rolls up `✅` normally.

---

## The portfolio roadmap template

> **Nested layout only.** Lives at `codeops/00-roadmap.md`. One row per feature in the repo; it is
> a *derived summary* of the per-feature roadmaps, never the detailed record. Each feature's Stage
> Summary, Progress, and Status roll up from that feature's own roadmap. Roll-up precedence: any
> blocked → ⛔; all RDs Done with an open follow-on → 🔄; all RDs Done and none open → ✅; any
> executing → 🔄; else ⬜. The portfolio **auto-cascades**: every per-feature stage transition
> immediately updates that feature's portfolio row (see [stage-hooks.md](stage-hooks.md)).

````markdown
# Portfolio Roadmap: [Repo / Product Name]

> **Status**: Active
> **Last Updated**: [YYYY-MM-DD HH:MM]
> **Features**: [Done] / [Total] done
> **CodeOps Artifact Schema**: 1

## Legend

⬜ Backlog · 🔄 In progress · ✅ Done · ⛔ Blocked · ⏸️ Deferred · 📦 Archived

## Features

| Feature | Roadmap | Stage Summary | Progress | Status | Last Updated |
|---------|---------|---------------|----------|--------|--------------|
| billing | [→](features/billing/00-roadmap.md) | 2 RDs · 1 plan executing | 1/2 RDs | 🔄 | 2026-06-29 |
| auth    | [→](features/auth/00-roadmap.md)    | backlog | 0/3 RDs | ⬜ | 2026-06-20 |

## Archived

| Feature | Roadmap | Completed | Last Updated |
|---------|---------|-----------|--------------|
| onboarding | [→](_archive/onboarding/00-roadmap.md) | 4/4 RDs | 2026-05-30 |
````

### Portfolio header fields

- **Status** — `Active` while the repo has live features; informational.
- **Last Updated** — bumps on every cascade.
- **Features** — `[Done] / [Total] done`, counting feature rows whose rolled-up Status is ✅. Rows
  whose `Progress` is hand-maintained (e.g. `n/a`) are not engine-computed and are excluded from
  both totals. A trailing ` (…)` annotation on this value is preserved when the count is refreshed.

### Portfolio columns

| Column | Meaning |
|--------|---------|
| Feature | The feature folder name under `codeops/features/`. |
| Roadmap | Relative link to that feature's `00-roadmap.md`. |
| Stage Summary | Short derived phrase (e.g. "2 RDs · 1 plan executing"). |
| Progress | Derived count of `RD-*` rows (e.g. "1/2 RDs"), optionally with a ` · …` annotation. A hand-maintained value such as `n/a` is preserved by the engine, which then leaves this row's Status untouched. |
| Status | Rolled-up emoji (🔄 / ✅ / ⛔ / ⬜ / ⏸️); not re-rolled for a row whose Progress is hand-maintained. |
| Last Updated | Date of the last cascade to this row. |

### Archived section

Archiving a feature **moves** its row here (📦) — never deletes it (AR #11). The feature folder is
`git mv`d to `codeops/_archive/<f>/`, so the Roadmap link points under `_archive/`.

A fresh-scaffolded or just-migrated repo seeds this portfolio automatically (the `setup-codeops`
migration writes a one-feature portfolio; refine it with `update`).
