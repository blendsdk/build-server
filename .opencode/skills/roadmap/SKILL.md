---
name: roadmap
description: >-
  Tracks features across their lifecycle in a live, per-repo roadmap — every RD, plan, and task and
  the lifecycle stage each is in. Layout-aware: a single plans/00-roadmap.md in flat layout, or a
  two-tier per-feature + portfolio roadmap under codeops/ in nested layout. Use when the user says
  "roadmap", "make_roadmap", "update_roadmap", "review_roadmap", "show_roadmap", "archive_roadmap", or
  "compact_roadmap". Covers six actions: make_roadmap (create + seed rows from disk),
  update_roadmap (re-infer stages, sync to disk, cascade to the portfolio), review_roadmap
  (read-only health check for drift/broken links), show_roadmap (read-only status overview —
  progress, stages, and next steps), archive_roadmap (move a completed feature to the archive), and
  compact_roadmap (slim a bloated roadmap: strip the legacy Notes log and trim fat cells). Detects
  the action from the user's phrasing or arguments and branches. The roadmap is the cross-session
  derived cross-session summary at the RD/plan altitude.
---

# roadmap — Live Feature-Set Roadmap Keeper

> **CodeOps Artifact Schema**: 1

## CodeOps derived-status rule

Execution-plan checklists and plan metadata are authoritative. Derive status without writing a
second state store. For a read-only summary, run:

```bash
python3 "${CODEOPS_PLUGIN_ROOT}/scripts/codeops_plan.py" --root . --json
```

The helper reads every `> **Implements**:` declaration and each `[ ]`/`[~]`/`[x]`/`[!]` task.
Its output is derived and read-only; a nonzero exit means a required plan artifact, RD mapping, or
blocked reason is missing. Updating one row must never advance its siblings. Roadmaps summarize
lifecycle, tasks, blockers, and RD delivery; they never become an independent owner of those
facts. If roadmap text conflicts with the plan, report drift and repair only the derived view.

## Resolve paths first (layout-aware)

Before any action, determine the layout via **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)**. When reading it with a tool, use the unambiguous installed path `${CODEOPS_PLUGIN_ROOT}/_shared/layout-convention.md`; do not reconstruct the Markdown link path by hand.

- **Flat layout** (no `codeops/.codeops.yml`): a single roadmap at `plans/00-roadmap.md`. Behaves
  **exactly as flat layout always has** — everything below that mentions "the roadmap" means this one file, and the
  portfolio tier does not exist (its cascade steps are inert).
- **Nested layout** (marker present): **two tiers** — a per-feature roadmap at
  `codeops/features/<f>/00-roadmap.md` and a **portfolio roadmap** at `codeops/00-roadmap.md` (one
  row per feature, auto-cascaded). In nested layout the skill asks/confirms the **target feature**
  before acting on a per-feature roadmap, and creates the feature folder lazily (never guesses).

The roadmap is a living document that tracks an entire **feature** at a higher altitude than any
individual execution plan. Where `99-execution-plan.md` tracks the tasks *within one feature*, the
roadmap tracks *every requirement (RD), plan, and task* and the lifecycle stage each is in. It is
the user's cross-session lifeline: open it to see what is done, in flight, blocked, or in backlog.

It never replaces the execution plan; it indexes and summarizes across many of them.

## Action dispatch

Detect the action from the user's phrasing or argument and branch:

| Trigger | Action |
|---------|--------|
| `make_roadmap`, "create the roadmap", "start a roadmap" | **make** — create + seed |
| `update_roadmap`, "sync the roadmap", "update the roadmap" | **update** — re-infer + sync |
| `review_roadmap`, "check the roadmap", "is the roadmap healthy" | **review** — read-only health check |
| `show_roadmap`, "show the roadmap", "roadmap status", "where do things stand", "what's the progress on <feature>" | **show** — read-only status overview |
| `archive_roadmap`, "archive the feature-set", "archive the roadmap" | **archive** — move to `_archive` |
| `compact_roadmap`, "compact the roadmap", "clean up / slim the roadmap" | **compact** — strip the legacy Notes log + trim fat cells |

## The lifecycle state machine

```
⬜  Backlog          — RD identified but not yet drafted
✏️  RD Drafted       — RD document written
🔎  RD Preflighted   — RD passed preflight
📋  Plan Created     — a plan was produced
🔬  Plan Preflighted — plan passed preflight
🔄  Executing        — execution in progress
✅  Done             — plan fully executed
⛔  Blocked          — cannot proceed (waiting on a Deferred dependency)
⏸️  Deferred         — a discovered dependency pulled out as its own tracked item
```

**Linear happy path:**
`Backlog → RD Drafted → RD Preflighted → Plan Created → Plan Preflighted → Executing → Done`.

`Blocked` and `Deferred` are **orthogonal overlays** on the linear path — a row in
any stage can become `Blocked`, and any discovered dependency can be pulled out as
a `Deferred` sub-row.

The full stage-transition map (which lifecycle events advance which rows, and which
skill fires each hook) is in [stage-hooks.md](stage-hooks.md) — read it when wiring
or reasoning about transitions.

## Task rows (nested layout)

A feature's roadmap also tracks **lightweight tasks** (`T-NN`) beside its RD rows. A task uses the
compact lifecycle `⬜ Backlog → 🔄 Executing → ✅ Done` (with `⛔`/`⏸️` overlays) and never the
RD/Plan-Preflight stages. A trivial task is a row with no RD and no plan link; a non-trivial task
links a single mini-plan. `T-NN` and `RD-NN` are separate per-feature namespaces (no collisions).
Full task model + routing: [../../_shared/layout-convention.md](../../_shared/layout-convention.md).

## Two governing rules (apply to every action)

**Ask-if-missing / sync-if-exists** — the roadmap is never auto-created silently:

- **When MISSING:** ask the user whether to create it. Never fabricate one without consent.
- **When it EXISTS:** always sync from disk state automatically — never ask, never prompt.
  Stage hooks fire silently.

This keeps the roadmap opt-in to create, but always-fresh once it exists.

**Real-time update mandate** — the roadmap is updated **immediately** on each stage
transition, **BEFORE** verification, commit, or the next action. Update order:
`complete the stage transition → update the resolved roadmap file → proceed` (the resolved file
per the convention doc: `plans/00-roadmap.md` flat, the feature's `00-roadmap.md` nested). On each
transition update the row's `Stage`, `Status`, and `Last Updated`, plus the header
`Progress` counter and `Last Updated`. Rationale — crash resilience: a session can
crash or hit context limits at any moment; if the roadmap is stale the user loses
their cross-session view. Keep it always reflecting reality, and never end a
session/task with a stale roadmap.

**Stage-inference artifacts & the never-regress rule** — stages must be re-inferable from disk:

- `RD Drafted` ⇔ the RD file exists. `Plan Created` ⇔ a linked plan folder exists.
  `Executing`/`Done` ⇔ the plan's `99-execution-plan.md` checklist state (`Done` = all `[x]`).
- `RD Preflighted` ⇔ passing evidence names that exact RD as its audit target: either
  `00-preflight-report-RD-NN.md`, or the set-wide `00-preflight-report.md` whose recorded target
  includes it. A narrow report never advances sibling RDs.
- `Plan Preflighted` ⇔ the plan folder has a passing set-wide `00-preflight-report.md`. A
  `00-preflight-report-<document-stem>.md` proves only that document passed and does not advance the
  whole plan.
  (The preflight skill saves these reports — they ARE the stage's disk artifacts.)
- **Stages never regress on sync.** `update` may only advance or preserve a row's stage; if disk
  suggests a LOWER stage than recorded, keep the recorded stage and report the discrepancy
  (review_roadmap flags it). Regressing a row requires an explicit user instruction, recorded in
  the git commit message that makes the regression (and, if it changes a dependent, noted terse in
  that dependent's `Depends-on / Blocker` cell) — never in a running Notes log.

**Portfolio cascade mandate (nested layout only)** — the real-time update extends one altitude
up. After completing a per-feature stage transition, update that feature's row in
`codeops/00-roadmap.md` (re-roll Stage Summary / Progress / Status; bump the portfolio counts)
**before** verify/commit/next — **but only on the integration branch**. On a **non-integration
branch** (a parallel feature worktree) the portfolio write is **deferred**: update only the
isolated per-feature roadmap and leave `codeops/00-roadmap.md` untouched, so concurrent worktrees
never collide on it; `roadmap update` reconciles the portfolio from disk once the work lands on the
integration branch. In flat layout this step is inert. Full cascade rule, the integration-branch
deferral, and the status roll-up are in [stage-hooks.md](stage-hooks.md).

## Deterministic linking (RD ↔ plan)

Plan folders are named by feature (e.g. `plans/billing/`) and carry **no encoded RD
id**, and the repo can hold multiple unrelated feature-sets at once, so "everything
under `plans/`" is **not** a valid membership rule. Link deterministically instead:

- Every plan declares every requirement it implements on one `> **Implements**: RD-NN, RD-NN`
  line in its `00-index.md` (feature-qualified identifiers in nested layout — see the ID rules in
  the convention doc). The `Plan Created` hook reads this line and links the plan to each matching
  RD row in that feature's roadmap.
- A plan with **no declared RD** is linked only when the user explicitly states which
  RD (or `DEF-n`) it belongs to. Unrelated plans are never silently swept in.

## Deferred & Blocked handling

When a blocking dependency is discovered mid-preflight or mid-execution:

1. Add a **nested `↳ DEF-n` sub-row** directly beneath the affected parent row, visually tied to it.
2. Set the **parent row's Stage cell to `⛔ Blocked (was: <prior stage>)`** — the prior stage is
   recorded IN the cell so recovery never depends on conversation memory — and name the `DEF-n`
   it waits on in `Depends-on / Blocker`.
3. Track the `DEF-n` sub-row through its own lifecycle stages like any other item.
4. When `DEF-n` reaches `Done`, the parent **leaves `Blocked`** and resumes the stage recorded in
   its `(was: …)` annotation.

Deferred work is never hidden in a separate section — it stays nested under the item
it blocks so the dependency is obvious at a glance.

---

## make — create the roadmap

Create the roadmap using the template in [template.md](template.md) (header, legend, tracker
columns; and the **portfolio template** for nested layout). Path per the convention doc.

**Flat layout** → create `plans/00-roadmap.md`:

1. **Ask the user once for the feature-set name** — used in the header and as the
   archive folder slug.
2. **Auto-populate from disk (suggest, don't sweep):**
   - Seed one row per `requirements/RD-*.md` found.
   - For each `plans/*/99-execution-plan.md`, *suggest* a link plus an inferred stage
     (from checklist completion), but only write the plan into the roadmap **after the
     user confirms** it belongs to this feature-set.
3. **If the roadmap already exists:** do NOT ask — sync it from disk state instead
   (the update action).

**Nested layout** → two tiers:

1. **Portfolio** (`codeops/00-roadmap.md`): create it if absent (a fresh-scaffolded or just-migrated
   repo already has a seeded one). Seed one row per `codeops/features/<f>/` present, each row
   derived from that feature's roadmap.
2. **Per-feature roadmap** (`codeops/features/<f>/00-roadmap.md`): ask/confirm the target feature,
   create the feature folder lazily if new, then seed it from that feature's `requirements/` +
   `plans/` (same suggest-don't-sweep rule), and add `T-NN` task rows where tasks exist.
3. After creating/seeding a feature roadmap, **cascade** its summary to the portfolio row.

## update — re-infer stages and sync to disk

Advance stages and sync the roadmap to current disk state.

- Walk each row, re-infer its stage from disk per the **stage-inference artifacts** above (RD
  present, preflight reports, plan present, checklist completion) and update `Stage`, `Status`,
  and `Last Updated` — honoring the **never-regress rule** (advance or preserve; report
  discrepancies instead of downgrading).
- **Delegate ALL counter arithmetic to the engine:** run `scripts/codeops-roadmap-sync.sh` (write
  mode). It recomputes the header `Progress` counters, the portfolio `Progress`/`Status` cells,
  and the `Features` count from disk — **never re-derive these numbers in prose** (the same
  prose-vs-script division as the migration engine: the skill owns stage judgment, the script
  owns arithmetic). Stage Summary phrasing remains yours. The engine counts only `RD-*` rows
  (`T-*` tasks are excluded), is **follow-on aware** (a feature with all RDs Done but an open
  `## Open follow-ons` row holds at `🔄`), and **preserves hand-maintained values** — a
  non-computed `Progress` such as `n/a` and any ` · …` / ` (…)` annotation are kept verbatim, and a
  held row's `Status` is not re-rolled. See [template.md](template.md) → *Open follow-ons* and the
  Progress/Features field notes for the authoring contract.
- **Nested layout:** stage re-inference is per-feature (your judgment); the script performs the
  numeric **cascade** into `codeops/00-roadmap.md` in the same run.
- **Recommend compaction if the roadmap is bloated:** run `scripts/codeops-roadmap-compact.sh
  --check`; if it reports a legacy `## Notes` section or an oversized cell, recommend the user run
  **compact**. `update` itself never strips or trims — it only re-infers stages and delegates
  counters (mirrors how it delegates arithmetic to the sync engine).
- **Rows stay dependency-ordered:** keep prerequisites above the rows that depend on them (see
  [template.md](template.md) → Row ordering & discipline); a planned dependency is a terse
  `depends on RD-NN` in the row's `Depends-on / Blocker` cell.
- **If the roadmap is missing:** fall back to **make** — ask whether to create it, then create it.

## review — read-only health check

Run a health check and report findings; change nothing on disk.

- **Counter/cascade drift is mechanical:** run `scripts/codeops-roadmap-sync.sh --check` — its
  `DRIFT` lines and non-zero exit ARE that portion of the report (Progress counters, portfolio
  Progress/Status cells, Features count). Do not re-derive the numbers in prose. Preserved
  hand-maintained values are reported on informational `HELD` lines and do **not** fail the check —
  an `n/a` sentinel or an annotated cell is healthy, not drift; surface `HELD` lines so a human can
  eyeball the hand-maintained values.
- **Bloat is mechanical too:** run `scripts/codeops-roadmap-compact.sh --check` — a reported legacy
  `## Notes` section or oversized cell is that portion of the health report; recommend **compact**
  to slim it (review itself changes nothing on disk).
- Every RD row references an existing `requirements/RD-*.md` file.
- Every plan link references an existing plan folder.
- The recorded `Stage` matches on-disk reality per the stage-inference artifacts (flag drift;
  remember stages never regress — a lower-than-recorded disk state is a discrepancy to report,
  not a downgrade to apply).
- Every `Blocked` row has a live `DEF-n` sub-row and a `(was: <stage>)` annotation; if the
  `DEF-n` is already `Done`, flag the parent as ready to unblock.
- **Nested layout (both tiers):** every portfolio row links an existing feature roadmap; Stage
  Summary phrasing matches the feature's rolled-up state.
- **If the roadmap is missing:** return the error below.

## show — present a status overview

Render a human-facing snapshot of where a feature (or the whole repo) stands: overall progress, the
per-item stage table, and the concrete next steps. **Read-only — this action never writes to disk.**
It is the presentation counterpart to `review`: `review` audits the roadmap for drift and broken
links, `show` simply *displays* it. Do not run the sync engine in write mode or edit any file here.

**Migrated artifacts are first-class inputs.** A document carrying both `CodeOps Artifact Schema: 1`
and `Migrated From Claude CodeOps Skills Version: ...` is a CodeOps artifact with retained
provenance, not an obsolete Claude-only artifact. Read its existing roadmap, requirements, and plan
links normally. Never hide or ignore a row merely because its content predates the migration.

**Resolve the target (layout-aware):**

- **Flat layout** → present the single `plans/00-roadmap.md`.
- **Nested + a feature argument** (`show_roadmap <feature>`) → present that feature's
  `codeops/features/<f>/00-roadmap.md`, including its `T-NN` task rows and any `## Open follow-ons`.
- **Nested + no argument** → present the **portfolio** `codeops/00-roadmap.md` (one row per feature)
  as the overview, then offer to drill into a named feature. If the target feature is ambiguous, ask
  — never guess (same rule as the other actions).

**What to present** (adapt the depth to the roadmap's size; keep it scannable):

1. **A one-line header** — which roadmap you are reading (its resolved path) and its recorded
   `Last Updated`.
2. **An overall progress line** — the header `Progress` fraction/percent (portfolio: the `Features`
   count), plus a short phrase on what most recently landed and what is in flight. **Report the
   recorded counters as-is; do not silently recompute or mutate them.** If a row's `Stage` or a
   counter looks stale versus disk (apply the stage-inference artifacts read-only), note the
   suspected drift in one line and suggest `update_roadmap` — never edit to "fix" it here.
3. **The tracker as a table** — the roadmap's rows with their `ID`, `Title`, `Stage`, `Status`
   emoji, `Plan` (✔ / —), and `Depends-on / Blocker`, in dependency order, with the legend beneath.
   Preserve `↳ DEF-n` sub-rows nested under the row they block.
4. **"Where you stand right now"** — a few grounded bullets: what just shipped, what is in flight,
   anything `Blocked` (name the `DEF-n` it waits on), and how much backlog remains.
5. **"Natural next steps"** — 1–3 concrete, state-grounded suggestions (e.g. preflight the created
   plan, execute it, unblock a `DEF-n`, or draft the next backlog RD). Lead with the single most
   obvious continuation; the user decides.

**If the roadmap is missing:** return the same error as `review` (below) — never fabricate one.

## archive — archive a completed feature

**Flat layout** (membership is **explicit** — move only the rows listed in the roadmap):

1. Read the feature-set slug from the roadmap header.
2. Create `plans/_archive/<feature-set>/`.
3. Move into it: the roadmap itself, plus **only** the RD documents and plan folders
   that appear as rows in the roadmap.
4. Leave all other `requirements/` and `plans/` content untouched. Never sweep every
   folder under `plans/`.
5. A fresh roadmap can then be created for the next feature-set.
6. **If the roadmap is missing:** return the error below.

**Nested layout** (feature-level, whole-folder — FR-12 / AR #11):

1. Confirm the feature to archive (its rolled-up Status should be ✅ Done; warn if not). Never
   fragment a live feature — archive the whole folder, not individual plans.
2. `git mv codeops/features/<f> codeops/_archive/<f>` (preserves history; intra-feature links
   survive because the whole folder shifts).
3. In `codeops/00-roadmap.md`, **move** the feature's row from `## Features` to `## Archived`
   (mark 📦, update the Roadmap link to `_archive/<f>/00-roadmap.md`) — **never delete it** — and
   refresh the `Features` count + `Last Updated`.
4. **If the portfolio is missing:** return the error below.

---

## compact — shrink an existing roadmap (both layouts)

Slim a roadmap that has bloated over time — a legacy `## Notes` running log and/or verbose table
cells — back to a lean status table. The mechanical, safety-critical work is delegated to the
engine; the judgment (rewriting a fat cell down to a terse phrase) is yours.

1. **Resolve layout.** compact operates on **every** roadmap in the repo — the portfolio, every
   feature roadmap, and `_archive/` — not a single feature.
2. **Require a clean git tree.** Deleting the Notes log is only reversible through git, so if the
   tree is dirty, STOP and ask the user to commit or stash first (the engine also refuses — check
   early so the user gets a clean message rather than a mid-run abort).
3. **Run the engine** — `scripts/codeops-roadmap-compact.sh` (apply). It strips every `## Notes`
   section in place and prints `FLAG <file>:<row>:<column> (<n> chars)` lines for oversized cells.
   It never rewrites a cell.
4. **Trim each flagged cell** to a terse status phrase, **preserving the load-bearing tokens
   verbatim** — `waiting on DEF-n` and `Blocked (was: <stage>)`. The verbose original stays in git
   history; never relocate it to another file on disk.
5. **Confirm, then re-sync.** Run `scripts/codeops-roadmap-compact.sh --check` — it must report no
   `## Notes` section and no oversized cell. Then run `scripts/codeops-roadmap-sync.sh` so the
   counter surfaces stay consistent.
6. **Report and stop.** List the affected files and leave the change for the user to review and
   commit (`git status` / `git diff`); never auto-commit.

**If no roadmap exists:** report `no roadmap found — nothing to compact`; never create one.

---

## Error handling

| Error case | Handling |
|------------|----------|
| **review** / **show** / **archive** when roadmap missing | Return `**Error:** No roadmap found at <resolved roadmap path>. Run make_roadmap first.` (path per the convention doc — `plans/00-roadmap.md` flat, `codeops/00-roadmap.md` or the feature roadmap nested) |
| **update** when roadmap missing | Fall back to **make** (ask-if-missing, then create) |
| **make** when roadmap already exists | Do NOT ask; sync from disk state (the update action) |
| Nested: per-feature transition but portfolio row stale | Cascade is mandatory + immediate; `review` flags the drift (AR #8) |
| Nested: target feature ambiguous | Ask the user; never guess (AR #26) |
| **compact** on a dirty or non-git tree | STOP; ask the user to commit/stash first — the engine also refuses (exit 1) |
| **compact** when no roadmap exists | Report `no roadmap found — nothing to compact`; never create one |

## Project conventions

For project-specific settings (build/test/verify commands, package manager,
structure, conventions), read the project's AGENTS.md (or detected project
conventions). If no AGENTS.md exists, detect settings from manifest files and use
only facts you can read — do not invent settings.

## Pointers & related skills

- [template.md](template.md) — the `plans/00-roadmap.md` template, legend, tracker
  columns, and a worked example. Read before **make**.
- [stage-hooks.md](stage-hooks.md) — the full stage-transition map, which skill fires
  which hook, and the source-of-truth rule. Read when reasoning about transitions.
- `scripts/codeops-roadmap-compact.sh` — the compact engine driven by the **compact** action, and
  by `update`/`review`'s `--check` bloat detection (strips the legacy Notes log, flags fat cells).
- Related skills: requirements (`RD Drafted` hook), preflight (`RD/Plan Preflighted`
  hooks), make-plan (`Plan Created` hook + linking), exec-plan (`Executing` / `Done` /
  `Blocked` hooks).
