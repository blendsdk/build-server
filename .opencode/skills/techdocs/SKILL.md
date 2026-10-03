---
name: techdocs
description: >-
  Creates and maintains VitePress-compatible technical architecture documentation and
  architecture decision records (ADRs). Use when the user says "make_techdocs",
  "review_techdocs", "techdocs", "document the architecture", "create architecture docs",
  "write ADRs", or "architecture decision records". Covers two modes: make_techdocs to
  create or comprehensively regenerate the docs/ set (system overview, data model, API
  design, infrastructure, security, ADRs, developer guides, reference), and review_techdocs
  to run a 7-dimension health check (staleness, completeness, accuracy, ADR coverage, link
  health, diagram accuracy, getting-started) and produce a diagnostic report. Also fires
  automatically as an incremental or comprehensive update when an exec-plan phase or plan
  completes, or when make-requirements completes — but only if the project has opted in.
  Scope is technical/architectural docs for developers, NOT product/end-user documentation.
---

# techdocs — Technical Architecture Documentation

> **CodeOps Artifact Schema**: 1

Create and maintain a living, VitePress-compatible technical architecture documentation set in
the project's `docs/` directory, capturing accumulated design knowledge across requirements and
planning phases. The body branches by phrasing and arguments:

| Phrasing / argument | Mode | Action |
|---|---|---|
| `make_techdocs`, "document the architecture", "create architecture docs" | **Create / regenerate** | Phases 1–6: comprehensive create or full regeneration |
| `make_techdocs --continue` | **Resume** | Pick up an interrupted authoring session (see Session resume) |
| `review_techdocs`, "review the techdocs", "health check the docs" | **Health check** | 7-dimension diagnostic report (no file changes) |
| *(auto)* exec-plan phase complete | **Incremental** | Add ADRs / update changed sections only |
| *(auto)* exec-plan plan complete | **Comprehensive** | Full pass over every section vs. codebase |
| *(auto)* make-requirements complete | **Incremental** | New design decisions → ADRs |

## What this is (and is NOT)

| In scope — TECHNICAL docs (this skill) | Out of scope — PRODUCT docs |
|---|---|
| Architecture, design decisions, data models, API contracts, infrastructure, security | End-user guides, tutorials, FAQ, release notes, marketing |
| Developer onboarding, dev workflow, deployment procedures | Feature announcements, user-facing changelogs |

Product documentation is a separate concern. If the project needs user-facing docs, the user
should request them explicitly. They live elsewhere (e.g. `docs/product/`) and are NOT governed
by this skill.

## Opt-in, then auto-update

Technical documentation is **not mandatory by default**, but once opted in it is **automatically
maintained**.

### The opt-in marker

The presence of `docs/index.md` with this frontmatter marker means techdocs are active:

```yaml
---
techdocs: true
---
```

If `docs/index.md` exists but lacks this marker, it is NOT a techdocs-managed file — do not
auto-update it.

### Detection & ask-once protocol

When this skill fires as an auto-update hook (from the exec-plan or make-requirements skills):

1. **Does `docs/index.md` exist with the `techdocs: true` marker?**
   - **Yes** → run the appropriate auto-update (incremental or comprehensive — see the mode table).
   - **No** → ask the user once: *"Would you like to create technical architecture docs for this
     project?"*
     - **Yes** → run the create flow (Phases 1–6).
     - **No** → skip, and do not ask again until the next plan completes.

### Auto-update triggers

Once opted in, update techdocs at these checkpoints:

| Trigger (from another skill) | Update type | What to update |
|---|---|---|
| exec-plan **phase** completion | Incremental | New ADRs for decisions made; sections that changed |
| exec-plan **plan** completion | Comprehensive | Full review of all sections; consistency; diagrams |
| make-requirements completion | Incremental | New design decisions, updated scope, integration points |
| Manual `make_techdocs` | Comprehensive | Full review and regeneration |

**Incremental** = quick pass; add new ADRs, update changed sections only.
**Comprehensive** = full pass; review every section against actual codebase state.

> 🚨 **Design Intent Preservation is non-negotiable.** Auto-updates MUST NOT silently overwrite
> documented design intent (ADR decisions) with observed code behavior. The full rule, including
> the divergence-flagging protocol, lives in
> [authoring-and-update.md](authoring-and-update.md) — read it before any comprehensive update.

## Relationship to other skills

| Skill | Relationship |
|---|---|
| the make-requirements skill | **Upstream.** Requirements define WHAT. Techdocs capture architectural decisions made during requirements discovery. On completion → incremental techdocs update. |
| the make-plan skill | **Parallel.** Plans define HOW for one feature; techdocs capture SYSTEM-LEVEL architecture spanning features. make-plan reads techdocs as context. |
| the exec-plan skill | **Downstream.** Architecture evolves during execution. Phase complete → incremental; plan complete → comprehensive. Auto-update hooks fire from it. |
| the retro-requirements skill | **Upstream.** When reverse-engineering an existing system, techdocs capture the discovered architecture. |

## Phase overview

| Phase | What happens | Reference |
|---|---|---|
| **1. Information gathering** | Read `requirements/`, `plans/*/`, the codebase, the project's AGENTS.md (or detected conventions). Ask clarifying questions only on a first run with no requirements/plans. | below |
| **2. Document structure** | Lay out the VitePress `docs/` tree; adapt sections to the project type (only create relevant sections). | below |
| **3. VitePress setup** | Install VitePress, generate `.vitepress/config.ts`, add npm scripts, update `.gitignore`. | [vitepress-setup.md](vitepress-setup.md) |
| **4. Document templates** | Write each section from the canonical templates. | [templates.md](templates.md) |
| **5. Authoring guidelines** | Apply writing style, Mermaid diagram conventions, cross-referencing, and what NOT to document. | [authoring-and-update.md](authoring-and-update.md) |
| **6. Incremental update protocol** | Auto-update after phase/plan/requirements completion, including Design Intent Preservation. | [authoring-and-update.md](authoring-and-update.md) |

### Phase 1 — Information gathering

Gather from: existing `requirements/`, existing `plans/*/`, the current codebase (structure,
patterns, dependencies), and the project's AGENTS.md (or detected project conventions). In a
**nested-layout** repo these sources live under `codeops/features/<f>/{requirements,plans}/`
(resolve via [../../_shared/layout-convention.md](../../_shared/layout-convention.md)); in flat layout
they are the top-level `requirements/` and `plans/*/` as before. If this skill runs right after
make-requirements or exec-plan, most of this is already in context.

**Ask clarifying questions only on a true first run with no requirements/plans:** system purpose,
key stakeholders and their experience level, architecture style (monolith / microservices /
serverless / hybrid), key integrations, deployment model. If requirements/plans exist, extract
these from the documents — do not re-ask.

### Phase 2 — Document structure

Create only the sections relevant to the project type — empty placeholders add noise, not value.
Full VitePress directory layout:

```
docs/
├── .vitepress/
│   └── config.ts                # VitePress configuration
├── index.md                     # System overview + techdocs opt-in marker (ENTRY POINT)
├── architecture/
│   ├── system-overview.md       # High-level architecture, component diagram
│   ├── data-model.md            # Domain model, entity relationships, schemas
│   ├── api-design.md            # API contracts, endpoints, protocols
│   ├── infrastructure.md        # Deployment, Docker, CI/CD, networking
│   └── security.md              # Security architecture, threat model
├── decisions/
│   ├── index.md                 # ADR log (chronological)
│   ├── ADR-001-[short-name].md  # Individual decision records
│   └── ...
├── guides/
│   ├── getting-started.md       # Developer setup, prerequisites, first run
│   ├── development.md           # Dev workflow, coding patterns, conventions
│   └── deployment.md            # How to deploy, environments, configuration
└── reference/
    ├── configuration.md         # Config options, env vars, feature flags
    └── integrations.md          # External system connections, protocols, auth
```

**Adapting to project type** (create required sections; add optional ones as warranted):

| Project type | Required | Optional |
|---|---|---|
| Web App / SaaS | All | — |
| API / Backend | system-overview, data-model, api-design, security, infrastructure | — |
| Library / SDK | system-overview, api-design, getting-started, development | data-model, infrastructure |
| CLI Tool | system-overview, getting-started, development | data-model, infrastructure |
| Microservices | All (esp. infrastructure, integrations) | — |
| Mobile App | system-overview, data-model, api-design, security | infrastructure |
| Infrastructure | system-overview, infrastructure, security, deployment | data-model, api-design |

Then proceed to Phase 3 ([vitepress-setup.md](vitepress-setup.md)) and Phase 4
([templates.md](templates.md)).

## review_techdocs (health check)

When the user asks for `review_techdocs`, run the read-only 7-dimension health check (staleness,
completeness, accuracy, ADR coverage, link health, diagram accuracy, getting-started) and produce
a diagnostic report. It changes no files. The full check table and report template are in
[authoring-and-update.md](authoring-and-update.md).

## Session resume

Techdocs authoring can be lengthy. If you need to stop mid-run, save all completed documents to
`docs/`, record which sections remain in `docs/_draft/techdocs-progress.md`, and tell the user to
resume with `make_techdocs --continue`. On `--continue`, read `docs/_draft/techdocs-progress.md`,
read the existing completed documents, and continue from the next section. (OpenCode
auto-compacts context — no manual threshold handling is needed.)

## Conventions

- Follow your project's coding standards and your project's testing standards (the project's
  AGENTS.md, or detected project conventions) when documenting development and testing guides.
- Document security architecture against your project's security coding standards (AGENTS.md).
- When new pages are added (ADRs, sections), update `.vitepress/config.ts` sidebar — see
  [vitepress-setup.md](vitepress-setup.md).
- Related skills: make-requirements, make-plan, exec-plan, retro-requirements.

## Reference files

- [templates.md](templates.md) — all VitePress file templates (index, architecture/*, ADR log + ADR template, guides/*, reference/*). Read when writing any document in Phase 4.
- [vitepress-setup.md](vitepress-setup.md) — Phase 3 install, `config.ts`, npm scripts, `.gitignore`, and sidebar auto-update. Read when scaffolding VitePress or adding pages.
- [authoring-and-update.md](authoring-and-update.md) — Phase 5 authoring guidelines + Mermaid types, Phase 6 incremental/comprehensive update protocol with the Design Intent Preservation rule, and the review_techdocs health check. Read before authoring, before any auto-update, and for review_techdocs.
