# Preflight — The 13-Dimension Scan (detail)

> **CodeOps Artifact Schema**: 1

Read this file before executing Step 3 of the protocol — and especially before auditing a plan,
where Dimension 13 (Codebase Alignment) carries the most weight. Steps 1 and 2 set up the scan;
this file covers reconnaissance detail and the full dimension definitions.

## Step 1: Load and understand the artifact

Before scanning, you MUST:

1. **Read the complete artifact** — every document, section, and line.
2. **Identify the artifact type** — requirements set, implementation plan, or ad-hoc document.
3. **Load context** — read the project's AGENTS.md (or detected project conventions); understand
   the tech stack, conventions, and constraints.
4. **Read the Ambiguity Register** (if one exists) — `requirements/00-ambiguity-register.md` or
   `plans/<name>/00-ambiguity-register.md`. Understand what decisions were already made and why.
5. **Freeze the scope** — record the exact audit target, context documents, and authorized
   modification set. Reading a related document does not add it to the target.
6. **Resolve artifact identity** — use the exact user-selected file or directory as the audit
   target. Related artifacts are context; findings do not silently expand the modification set.
7. **Freeze product scope** — load
   [../../_shared/scope-expansion-control.md](../../_shared/scope-expansion-control.md), record
   strict or exploration mode, and separate defects in the authorized target from optional new
   functionality suggested by the reviewer.
8. **Load the minimum-sufficient baseline** — use `requirements/README.md` for a requirements set
   or `00-index.md` for a full plan. For a legacy artifact without that section, derive the
   original goal and smallest viable design only from explicit artifact statements and repository
   evidence. If either is unclear, record a blocking ambiguity or finding; do not infer it.

## Step 2: Codebase Reconnaissance — 🚨 NON-NEGOTIABLE

This step is what separates a real preflight from a document-correction exercise. Without it, every
dimension scan is blind. Build a thorough understanding of the actual codebase the artifact targets.

### What to examine

| What to examine | Why | How |
|---|---|---|
| **Project structure** | Understand what exists, how code is organized | List files on the project root recursively; read the directory layout |
| **Entry points & main modules** | Understand architecture and flow | Read main/index files, server bootstrap, CLI entry points |
| **Type definitions & interfaces** | Understand the data model and contracts | Read type files, interface definitions, shared types |
| **Key source files** | Understand implementation patterns and conventions | Read files directly relevant to the artifact's scope |
| **Existing tests** | Understand test patterns, what's already covered | Read test dirs, test helpers, test config |
| **Package manifest & dependencies** | Understand available libraries | Read `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, etc. |
| **Configuration files** | Understand build, deploy, runtime setup | Read tsconfig, webpack, docker-compose, CI/CD configs |
| **Existing documentation** | Understand what's already documented | Read README, CHANGELOG, architecture docs |

### Depth of reconnaissance by artifact type

| Artifact type | Reconnaissance depth |
|---|---|
| **Requirements** | Moderate — understand architecture, patterns, and existing capabilities to assess feasibility and non-redundancy |
| **Implementation Plan** | Deep — read every file the plan proposes to modify or depend on; verify every component/API/pattern reference; understand the dependency graph around the affected area |
| **Ad-hoc Document** | Targeted — focus on the specific area the document addresses |

> Reconnaissance is proportional, not exhaustive. For a plan that modifies 3 files, read those 3
> files deeply plus their direct dependents — do not read the entire codebase for a small artifact.
> For a single-RD or single-plan-document audit, related artifacts are context only. Use them to
> prove or refute claims in the target; do not turn defects located solely in those documents into
> findings against the selected artifact.

### Mapping document references to code

Systematically map every reference in the artifact to actual code:

- Every **component, module, or service** → Does it exist? Where? What does it actually do?
- Every **file or directory path** → Does it exist? Is the path correct?
- Every **API, function, or class** → Does it exist? Does its signature match what's assumed?
- Every **pattern or convention** assumed → Is it actually used in the codebase?
- Every **dependency or library** referenced → Is it in the manifest? Right version?
- Every **existing behavior** described → Is that actually how the code works?

Any reference that cannot be verified against the code is a potential finding for the scan.

### Present the Codebase Context Summary

After reconnaissance, present:

```markdown
## Preflight: [Artifact Name]

**Artifact Type:** [Requirements Set / Implementation Plan / Ad-hoc Document]
**Documents:** [X] files, [Y] total sections
**Ambiguity Register:** [Found — X items resolved / Not found]
**Scope:** [Full scan / Targeted: specific document]

### Codebase Context

**Repository:** [project name]
**Tech Stack:** [language, framework, key libraries — from actual package manifest]
**Architecture:** [brief description of actual architecture observed]
**Files Examined:** [N] source files, [M] test files, [K] config files
**Key Observations:**
- [Notable architectural pattern or convention observed]
- [Key existing component relevant to the artifact]
- [Important constraint or limitation found in the code]

**Reference Verification:** [X] references mapped to code — [Y] verified, [Z] unverifiable

Beginning 13-dimension scan...
```

## Step 3: The 13 dimensions

Scan all 13 every time, with adversarial intent. Every check must be informed by Step 2.

The dimensions test whether the requested artifact is sound; they are not permission to invent a
larger product. Apply the necessary-correction burden of proof to every newly suggested behavior.
In strict scope, omit optional additions completely. With active exploration, move them to the
Scope Expansion Register without counting them as findings.

| # | Dimension | What to hunt for |
|---|---|---|
| 1 | **Ambiguities** | Vague language, undefined terms, weasel words ("appropriate", "as needed", "etc."), statements with multiple interpretations, undefined behaviors |
| 2 | **Implicit Assumptions** | Things taken for granted without stating, assumed capabilities/knowledge/environment. **Codebase check:** verify every assumption about the code — assumed APIs, data models, patterns, capabilities that may not exist or behave differently |
| 3 | **Logical Contradictions** | Statements that conflict — across documents, sections, or within a paragraph. Inconsistent decisions, conflicting constraints |
| 4 | **Completeness Gaps** | Missing requirements, journeys, error handling, edge cases, or acceptance criteria needed by the authorized behavior; do not treat adjacent optional functionality as missing. **Codebase check:** existing code/tests/functionality affected by the requested changes but not mentioned — missing impact analysis |
| 5 | **Dependency Issues** | Circular/missing dependencies, dependencies on undefined components, tasks referencing not-yet-created entities, broken chains. **Codebase check:** verify referenced dependencies against the actual manifest and import graph — exist? right versions? undeclared deps relied on? |
| 6 | **Feasibility Concerns** | Tasks possibly impossible/unrealistic, underestimated complexity, approaches incompatible with the stated stack, tasks too large to do atomically, or support machinery whose cost is disproportionate to the requested result. **Codebase check:** verify approaches against the actual architecture — will it work with how the code is structured? Do estimates match the real code? Does evidence show why the smallest direct solution fails? |
| 7 | **Testability** | Requirements/tasks with no clear way to verify success, vague criteria ("should work well"), missing test specs, untestable acceptance criteria |
| 8 | **Security Blind Spots** | Security defects that make the authorized behavior unsafe; distinguish a necessary correction from optional defense-in-depth functionality using grounded causal evidence |
| 9 | **Edge Cases** | Boundary conditions and failure modes of the authorized behavior; do not invent adjacent journeys merely to fill the checklist |
| 10 | **Scope Creep Indicators** | Existing artifact content that exceeds the confirmed baseline, unbounded tasks ("support all formats"), gold-plating, premature optimization, or a material new layer/dependency/harness/infrastructure surface without explicit complexity approval; newly imagined optional additions are silent or `SE-*` proposals, not findings |
| 11 | **Ordering & Sequencing** | Tasks in wrong order, phases that should swap, work planned before its dependencies exist, missing foundation work. **Codebase check:** verify order against the actual dependency graph — real module boundaries, import chains, build dependencies |
| 12 | **Consistency** | Naming inconsistencies across documents, conflicting conventions, terminology drift (same thing, different names), formatting that obscures meaning |
| 13 | **Codebase Alignment** | **The master reality check.** Entirely codebase-grounded — see below |

For Dimensions 6 and 10, apply the **Complexity Escalation Gate** in
[../../_shared/zero-ambiguity-gate.md](../../_shared/zero-ambiguity-gate.md). An unapproved
escalation is at least a 🟠 MAJOR finding and blocks a pass. Identify the smallest viable solution
and the extra build and maintenance surface; do not treat sophistication as evidence of need.

### Dimension 13: Codebase Alignment — detailed sub-checks

Every sub-check requires completed Step 2 reconnaissance and must reference specific files/code.

| Sub-check | What to hunt for | Example finding |
|---|---|---|
| **Phantom References** | Components/files/APIs/modules/classes/functions mentioned that do not exist | "Plan references `UserAuthService` in phase 3, but no such class exists. The actual auth logic is in `middleware/auth.ts` as a function chain." |
| **Stale Assumptions** | Incorrect claims about how existing code works — wrong signatures, data flows, behavior | "RD-05 states 'the cache layer supports TTL per key' but `CacheManager.set()` has no TTL param — it uses a global TTL from config." |
| **Architecture Mismatch** | Proposed patterns/structures that conflict with the established architecture | "Plan proposes a class-based service layer, but the codebase uses a pure-function pattern — every existing 'service' is an exported function." |
| **Impact Blindness** | Existing code affected by the changes but not acknowledged | "Plan modifies the `User` interface in `types/index.ts` but doesn't mention the 14 files that import it, 6 of which would break." |
| **Redundancy** | Things the document proposes to build that already exist | "RD-12 calls for 'a utility to parse env vars with defaults' — this already exists as `resolveConfig()` in `src/config.ts`." |
| **Test Impact** | Existing tests that would break/become invalid, or test patterns the doc doesn't follow | "The plan adds a new tool but ignores the existing pattern in `tools-setup.ts` where all tools share a lazy-loaded store fixture." |
| **Dependency Reality** | Assumed-available libs that aren't installed, or installed libs the doc ignores that could solve its problem | "Phase 2 proposes adding `lodash` for deep merge, but it isn't in dependencies. The project already has a custom `deepMerge` in `utils/`." |
| **Convention Violations** | Proposed naming/organization/patterns that violate actual conventions | "Plan names the new file `getUserData.ts` but the project uses kebab-case: `get-rule.ts`, `search-rules.ts`." |
| **Scope vs. Reality** | Complexity/effort estimates unrealistic given the actual code | "Plan estimates phase 4 (refactor caching) as 'straightforward, ~100 lines' but the cache spans 3 files, 450 lines, with 40 dependent tests." |
| **Migration & Compatibility** | Missing data migration plans, backwards-compat concerns, or rollback strategies | "Plan changes the config file format but doesn't address migration for existing users on the old format." |

**Rules for Dimension 13 findings:**

- Cite the **specific file(s) and line(s)** that contradict or invalidate the artifact's claims.
- Explain the **actual state** of the code, not just that it's "different".
- Phantom-reference findings MUST suggest what the document **probably meant** if there's a close match.
- Impact-blindness findings MUST list the **affected files** and how they'd be impacted.

### Dimension depth by artifact type

Scan all 13 every time; depth of analysis adapts:

| Dimension | Requirements | Plans | Ad-hoc |
|---|---|---|---|
| Ambiguities | 🔥 Deep | 🔥 Deep | 🔥 Deep |
| Implicit Assumptions | 🔥 Deep | 🔥 Deep | Standard |
| Logical Contradictions | 🔥 Deep | 🔥 Deep | Standard |
| Completeness Gaps | 🔥 Deep | 🔥 Deep | Standard |
| Dependency Issues | Standard | 🔥 Deep | Light |
| Feasibility Concerns | Standard | 🔥 Deep | Standard |
| Testability | 🔥 Deep | Standard | Light |
| Security Blind Spots | 🔥 Deep | Standard | Light |
| Edge Cases | 🔥 Deep | Standard | Light |
| Scope Creep Indicators | 🔥 Deep | 🔥 Deep | Standard |
| Ordering & Sequencing | Light | 🔥 Deep | Light |
| Consistency | Standard | Standard | Standard |
| Codebase Alignment | 🔥 Deep | 🔥 Deep | Standard |

- **🔥 Deep** — exhaustive analysis, actively hunt for issues.
- **Standard** — thorough review, flag anything found.
- **Light** — quick check, flag only obvious issues.
