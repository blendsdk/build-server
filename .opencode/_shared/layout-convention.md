# CodeOps Layout Convention (shared reference)

> **CodeOps Artifact Schema**: 1

This is the **single source of truth** for where CodeOps artifacts live. It is a shared
reference document, **not a skill** — it lives at the **plugin root** in `_shared/` (deliberately
**outside** `skills/`), so the plugin loader, which treats each `skills/<dir>` as a skill, never
meets a `SKILL.md`-less directory. Every layout-aware skill (`roadmap`, `make-requirements`,
`make-plan`, `exec-plan`, `preflight`, `upgrade-plan`, `retro-requirements`, `techdocs`) **links here** (as
`../../_shared/layout-convention.md`) for path resolution and ID rules instead of hardcoding
paths. Change the layout in one place: here.

CodeOps supports two layouts. A repo is in exactly one of them, decided by a single marker file.

---

## Detection rule (apply this first, every time)

```
1. If codeops/.codeops.yml exists AND it declares `codeopsLayout: nested`
       → NESTED layout. Resolve all artifact paths under codeops/features/<feature>/…
2. Otherwise (no marker, or a malformed/incomplete marker)
       → FLAT layout (the pre-3.0.0 behavior, unchanged). Surface a warning if a marker
         exists but is malformed, then proceed as flat — never crash.
3. In NESTED layout, <feature> is the target feature, which the skill ASKS the user to
       confirm/choose — it never silently guesses (see "Feature targeting" below).
```

Detection is a simple key match so it works without a YAML parser. The canonical check
(mirroring the JSON/`grep` fallback pattern in `scripts/validate.sh`):

```bash
if [[ -f codeops/.codeops.yml ]] && grep -Eq '^codeopsLayout:[[:space:]]*nested[[:space:]]*$' codeops/.codeops.yml; then
  layout=nested
else
  layout=flat
fi
```

---

## The path map (canonical)

| Concept | Flat layout (marker absent) | Nested layout (marker present) |
| ------- | --------------------------- | ------------------------------ |
| Requirements dir | `requirements/` | `codeops/features/<f>/requirements/` |
| RD document | `requirements/RD-NN-*.md` | `codeops/features/<f>/requirements/RD-NN-*.md` |
| Plan folder | `plans/<plan>/` | `codeops/features/<f>/plans/<plan>/` |
| Feature roadmap | `plans/00-roadmap.md` | `codeops/features/<f>/00-roadmap.md` |
| Portfolio roadmap | *(n/a)* | `codeops/00-roadmap.md` |
| Staged AGENTS.md notes | *(n/a)* | `codeops/features/<f>/AGENTS.notes.md` |
| Ambiguity register | `requirements/00-ambiguity-register.md` or `plans/<plan>/00-ambiguity-register.md` | the same file, under the feature |
| Scope-expansion register | See the target-qualified rules below | the same target-qualified filename, under the feature |
| Task mini-plan | `plans/<task-slug>/99-execution-plan.md` | `codeops/features/<f>/plans/<task-slug>/99-execution-plan.md` |
| Archive | `plans/_archive/<set>/` | `codeops/_archive/<f>/` |

In nested layout, a feature's inner directories are created **lazily** — only when that
feature's first RD, plan, or task is written. The marker and the (possibly empty) portfolio
roadmap are the only things `setup-codeops` creates up front.

### Scope-expansion register paths

Scope-expansion register paths are collision-free because their authority is scoped to one audit or
planning target:

| Governed target | Register filename |
|---|---|
| Full requirements set, full plan, or plan execution | `00-scope-expansion-register.md` in the governed artifact directory |
| Single requirement or single plan document | `00-scope-expansion-register-<document-name>.md` in the document directory |
| Ad-hoc file | `scope-expansion-register-<artifact-name>.md` in the artifact directory |
| Ad-hoc directory | `scope-expansion-register.md` inside the governed directory |

The shared scope-expansion protocol owns register contents and lifecycle. This layout convention
owns paths and target identity. `<document-name>` and `<artifact-name>` are the complete existing
filename, including its extension; for example, `foo.md` and `foo.txt` resolve to different
registers. Use only the final filename component and reject path separators, `..`, absolute paths,
or a name that is not the governed target's exact filename. An ad-hoc directory's register lives
inside that exact directory. Two governed targets must never resolve to the same register unless
they intentionally share the full-set or full-plan scope baseline.

---

## ID rules

- **RD ids reset per feature.** Within `codeops/features/billing/requirements/` the ids run
  `RD-01, RD-02, …` independently of every other feature. (In flat layout there is one global
  RD sequence, as before.)
- **Cross-feature references are feature-qualified.** A plan's `00-index.md` declares one or more
  requirements on a single line, for example `> **Implements**: billing/RD-01, billing/RD-02` in
  nested layout or `> **Implements**: RD-01, RD-02` in flat layout. The roadmap matcher and plan
  status parser read this line.
- **Tasks use a separate per-feature sequence** `T-01, T-02, …`, so a task id never collides
  with an RD id in the same feature. See the task-lane spec for the lightweight task model.

---

## Feature targeting (nested layout)

When a layout-aware skill runs in a nested repo and the target feature is not already implied
by context (e.g. the plan/RD being operated on), the skill **asks the user which feature** to
work in, and **creates the feature folder lazily** if it is new. It never guesses.

A new feature folder is `codeops/features/<feature>/` where `<feature>` is a sanitized slug:
lowercase, words separated by `-`, no path separators, no `..`, never absolute. Reject or
normalize any candidate that would traverse outside `codeops/features/` (see Error handling).

---

## Archiving (nested layout)

Archiving is **feature-level and manual**: `git mv codeops/features/<f> codeops/_archive/<f>`.
The portfolio roadmap keeps a compact Archived section — the feature's row is **moved** there
(📦), not deleted. Never fragment a live feature (don't archive individual plans out of one).

---

## `codeops/.codeops.yml` marker schema

Minimal and flat so it parses trivially. **`setup-codeops` is the sole writer of this file**
(every other skill must leave it untouched; the `analyze-project` command may *read*
`integrationBranch`, but never writes here).

```yaml
# CodeOps layout marker. Presence of this file opts the repo into the nested layout.
codeopsLayout: nested
layoutVersion: "3.0.0"
integrationBranch: master       # branch where features integrate; analyze-project refreshes AGENTS.md here
conventions:
  rdIdScope: per-feature        # RD numbering resets per feature
  taskIdPrefix: "T"             # lightweight task ids: T-01, T-02 …
  maintenanceFeature: _maintenance
  archiveDir: codeops/_archive
```

- Only `codeopsLayout: nested` is **required** for detection; the rest document the conventions
  and let future versions evolve.
- `integrationBranch` is **optional** — the branch where feature work integrates and
  `analyze-project` regenerates `AGENTS.md` (folding in any staged `AGENTS.notes.md`). When absent,
  `analyze-project` falls back to the repo default branch (`origin/HEAD`, else `main`/`master`), so
  existing markers keep working. `setup-codeops` should emit it.
- A committed sample marker lives at `scripts/fixtures/sample.codeops.yml` (used by
  `validate.sh` ST-16 to assert the schema parses and carries `codeopsLayout`).

---

## Error handling

| Error case | Handling strategy |
| ---------- | ----------------- |
| `.codeops.yml` present but malformed / missing `codeopsLayout` | Treat as **flat** (safe default) and surface a warning; do not crash |
| Marker present but `codeops/features/` missing | Nested layout still selected; the feature dir is created lazily on first write |
| Feature/slug contains `..`, `/`, or is absolute | Reject — normalize and refuse path-traversal before using it as a path component |
| Skill cannot determine the target feature | Ask the user; never guess |

---

## Lightweight tasks (the task lane)

Ad-hoc work — a bugfix, chore, or small change — is **not a feature**. It is a lightweight
**task**, and its ceremony scales with size. This is the single source for the task model; the
skills (`roadmap`, `make-requirements`, `make-plan`, `exec-plan`) reference it. The lane exists
in **both layouts** (flat gained it in 3.2.0 — AR #6): nested tasks carry a per-feature `T-NN`
id; flat tasks are simply a mini-plan folder (a `T-NN` roadmap row too when a roadmap exists).

**Routing — feature or task?**

```
Is this a new cohesive capability with real requirements?
  ├─ yes → FEATURE: make-requirements (RD) → make-plan → exec-plan
  └─ no  → TASK (T-NN):
            ├─ trivial     → a roadmap row + the commit; NO plan document
            └─ non-trivial → a single mini-plan, then exec-plan runs it
```
If it is genuinely unclear, ask — never silently default to the heavy pipeline.

**Where a task lives**

- *Flat layout* → a mini-plan at `plans/<task-slug>/99-execution-plan.md` (plus a roadmap row if
  `plans/00-roadmap.md` exists; a trivial task with a roadmap is just the row + commit).
- *Nested, belongs to a feature* (e.g. a bug in billing) → a `T-NN` row in
  `codeops/features/billing/00-roadmap.md`.
- *Nested, standalone / cross-cutting* → a `T-NN` row in `codeops/features/_maintenance/00-roadmap.md`.
  `_maintenance/` is a **normal feature folder** (same `00-roadmap.md` + `plans/`, rolls up into
  the portfolio), created **lazily** on the first standalone task. It simply tends to hold tasks
  rather than RDs.

**Ceremony by size**

- **Trivial** → just a roadmap row + the commit. No plan document.
- **Non-trivial** → a single mini-plan at the resolved task path (flat:
  `plans/<task-slug>/99-execution-plan.md`; nested:
  `codeops/features/<f>/plans/<task-slug>/99-execution-plan.md`) — execution doc only: objective,
  a short task checklist, and a verify line. **No RD, no 00–07 doc set, no Zero-Ambiguity Gate.**

**Task lifecycle** — a compact subset of the stage machine: `⬜ Backlog → 🔄 Executing → ✅ Done`
(plus `⛔ Blocked` / `⏸️ Deferred` overlays). Tasks never use the RD/Plan-Preflight stages.
Specification-first ordering still applies *when a task warrants tests* (e.g. a bugfix gets a
regression test); a trivial doc/config tweak may not.
