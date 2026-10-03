# Stage Transition Map & Hooks

The roadmap sits **above** the per-feature execution plan. It does not replace
the execution plan — it indexes and summarizes across many of them.

Resolve paths via **[../../_shared/layout-convention.md](../../_shared/layout-convention.md)**. In
**nested layout** there are two roadmap altitudes (per-feature + portfolio); in **flat layout**
there is a single roadmap and the portfolio cascade step below is inert.

| Altitude | Document (flat / nested) | Tracks | Produced/updated by |
|----------|--------------------------|--------|---------------------|
| Portfolio (highest, nested only) | *(n/a)* / `codeops/00-roadmap.md` | One row per feature in the repo | this skill + the **cascade hook** below |
| Feature-set / per-feature | `plans/00-roadmap.md` / `codeops/features/<f>/00-roadmap.md` | Every RD/plan/task + its lifecycle stage | this skill (`make` / `update`) + the stage hooks below |
| Single feature (low) | `plans/[feature]/99-execution-plan.md` / `codeops/features/<f>/plans/<plan>/99-execution-plan.md` | Tasks within one feature/plan | the make-plan / exec-plan skills |

## Stage transition map

Other skills fire these transitions on the roadmap. Each hook follows the
**ask-if-missing / sync-if-exists** rule: if no roadmap exists the hook is inert
(never auto-create); if one exists the hook fires silently (never prompt).

| Lifecycle event | Roadmap effect |
|-----------------|----------------|
| RD created (the requirements skill, `make-requirements` / `add_requirement`) | Row → `RD Drafted` (✏️) |
| Preflight passes on an RD (the preflight skill) | Row → `RD Preflighted` (🔎) |
| A plan is produced (the make-plan skill) | Row → `Plan Created` (📋); link the plan |
| Preflight passes on a plan (the preflight skill) | Row → `Plan Preflighted` (🔬) |
| Execution starts (the exec-plan skill) | Row → `Executing` (🔄) |
| Execution completes (the exec-plan skill) | Row → `Done` (✅) |
| Dependency discovered mid-preflight / mid-exec | Add a nested `↳ DEF-n` sub-row; parent → `Blocked` (⛔) |
| `DEF-n` reaches `Done` | Parent leaves `Blocked`, resumes its prior stage |

## The portfolio cascade hook (nested layout only — AR #8)

The portfolio roadmap is a derived summary, kept fresh by a cascade that extends the real-time
update mandate **one altitude up**. On **every** per-feature stage transition above:

```
complete the per-feature roadmap transition (codeops/features/<f>/00-roadmap.md)
  → on the INTEGRATION branch: immediately update that feature's row in codeops/00-roadmap.md
       (re-roll Stage Summary / Progress / Status; bump the portfolio Last Updated + Features count)
  → on a NON-INTEGRATION branch (a parallel feature worktree): DEFER the portfolio write —
       leave codeops/00-roadmap.md untouched; `roadmap update` reconciles it from disk on landing
  → THEN proceed (verify / commit / next action)
```

- On the **integration branch** the cascade is **mandatory and immediate** — never end a
  session/task there with a portfolio row that disagrees with its feature roadmap; `review` flags
  any such drift.
- **Parallel worktrees — integration-branch deferral:** on a **non-integration branch** the
  portfolio write is **deferred** so concurrent worktrees never collide on the shared
  `codeops/00-roadmap.md`. Resolve the integration branch the way `analyze-project` does — the
  `integrationBranch` marker key, else `origin/HEAD`, else `main`/`master`; if `git` is unavailable,
  treat the current branch as integration (unchanged behaviour). The **per-feature** roadmap write
  stays immediate — it is isolated per feature, so it never conflicts.
- **Status roll-up:** any executing row → 🔄; all rows done → ✅; any blocked row → ⛔; otherwise ⬜.
- **Cross-feature blockers** stay within the feature's roadmap, named feature-qualified in the
  depending row's `Depends-on / Blocker` cell (e.g. `waiting on auth/RD-02`). The portfolio has no
  Notes section — it rolls the blocked feature up to ⛔ and the detail lives in that row's cell.
- In **flat layout** there is no portfolio, so this hook is **inert** (unchanged flat-layout behaviour).

## Which skill owns which hook

- **requirements skill** — fires the `RD Drafted` hook on RD creation.
- **preflight skill** — fires the `RD Preflighted` and `Plan Preflighted` hooks.
- **make-plan skill** — fires the `Plan Created` hook and links the plan (via the
  `> **Implements**: RD-NN` line — see deterministic linking in SKILL.md).
- **exec-plan skill** — fires the `Executing`, `Done`, and `Blocked` + `DEF` hooks.

## Source-of-truth rule (stated directly here)

The roadmap is a **cross-session derived view** at the RD/plan altitude. Requirements own agreed
behavior; plan metadata owns RD mapping; `99-execution-plan.md` owns task progress:

- **Read-if-exists** — when a roadmap exists, read it at the start of relevant work
  to see what is done, in flight, blocked, or in the backlog.
- **Update-first** — apply the matching stage transition to the roadmap *before*
  verification, commit, or the next action (see the real-time update mandate in SKILL.md).
- **Before ending a session/task** — make sure the roadmap reflects the latest
  reality. Do not finish with a stale roadmap.
