# techdocs — Authoring, Update Protocol & Health Check (Phases 5–6 + review_techdocs)

> **CodeOps Artifact Schema**: 1

Read this before authoring any document, before any auto-update, and when running
`review_techdocs`.

---

## Phase 5 — Authoring guidelines

### Writing style

Technical documentation must be:

- **Clear** — Written for a developer who has never seen the project. No assumed context.
- **Concise** — Say what needs saying, nothing more. Prefer tables over paragraphs for structured data.
- **Current** — Every document has a "Last Updated" date. Stale docs are worse than no docs.
- **Concrete** — Include code examples, diagrams, and specific values. Avoid vague statements like "uses best practices."
- **Correct** — Every statement must reflect the actual codebase. Don't document aspirations as reality.

### Diagrams (Mermaid)

Use Mermaid syntax — rendered via `vitepress-plugin-mermaid`, which the setup step installs (vanilla VitePress does not render Mermaid):

- **Architecture diagrams**: `graph TB` or `graph LR`
- **Entity relationships**: `erDiagram`
- **Sequences**: `sequenceDiagram`
- **State machines**: `stateDiagram-v2`

### Cross-referencing

- Use relative links between doc pages (e.g. `[System Overview](/architecture/system-overview)`).
- Reference ADRs by number when explaining design choices (e.g. "See [ADR-003](/decisions/ADR-003-chosen-database)").
- Link to source code files when documenting specific implementations.

### What NOT to document

- **Secrets, credentials, or API keys** — Never. Not even examples that look real.
- **Auto-generated code** — Don't document what can be read from the code itself.
- **Temporary decisions** — If something is likely to change next week, don't write an ADR for it.
- **Obvious code** — Don't explain what `getUserById()` does. Document the *why*, not the *what*.

---

## Phase 6 — Incremental update protocol

### 6.1 After phase completion (incremental)

When an exec-plan phase completes and techdocs exist:

1. **Scan for architectural changes** — Did this phase introduce: new components/services? New
   data entities or relationships? New API endpoints? New external integrations? Infrastructure
   changes? Significant design decisions?
2. **If YES to any** → update the relevant sections:
   - New components → `system-overview.md`
   - New entities → `data-model.md`
   - New endpoints → `api-design.md`
   - New integrations → `integrations.md`
   - Significant decisions → create ADRs
3. **If NO** → skip (not every phase changes architecture).
4. **Update "Last Updated"** dates on modified documents.

For incremental updates, check new/changed code against the ADRs covering the affected area, and
apply the Design Intent Preservation check (6.4) for any relevant ADR.

### 6.2 After plan completion (comprehensive)

When all exec-plan tasks are complete and techdocs exist:

1. **Review every section** against the current codebase.
2. **Update all diagrams** to reflect current architecture.
3. **Verify all links** work.
4. **🚨 Check for design intent divergence** — see 6.4 below.
5. **Check for stale content** — anything no longer reflecting reality.
6. **Update the VitePress sidebar** if new pages were added.
7. **Update "Last Updated"** dates on all modified documents.
8. **Create ADRs** for any undocumented decisions from plan execution.

### 6.3 After make-requirements completion (incremental)

When make-requirements completes and techdocs exist:

1. **Extract design decisions** from the requirements documents.
2. **Create ADRs** for each significant decision (technology choices, architecture patterns, integration decisions).
3. **Update architecture sections** if the requirements imply architectural changes.
4. **Update the decision log** in `decisions/index.md`.

### 6.4 🚨 Design Intent Preservation — NON-NEGOTIABLE

**Auto-updates MUST NOT silently overwrite design intent with observed code behavior.** This rule
prevents the documentation tautology — where code changes (including bugs, regressions, and
architectural violations) get automatically documented as the new "intended architecture,"
erasing the original design rationale.

**The problem this solves:** If exec-plan introduces an architectural violation (e.g. a service
that should call through an API layer instead directly accesses the database), a naive auto-update
would change the architecture diagram and component description to match the violation. The next
make-plan run would then read the updated techdocs and treat the violation as the established
architecture. The original design intent is permanently lost.

**During every comprehensive update (6.2), you MUST:**

1. **Read all existing ADRs** — these are the documented design decisions.
2. **Compare the current codebase against ADR decisions** — does the code still follow them?
3. **If code MATCHES the ADR decisions** → update documentation normally (describe what exists).
4. **If code DIVERGES from an ADR decision** → DO NOT silently update. Instead:

   a. **Flag the divergence** to the user:

   ```
   ⚠️ Design Intent Divergence Detected

   ADR-003 decided: "All database access goes through the repository layer"
   Current code: UserController directly queries the database in src/controllers/user.ts:47

   Options:
   (A) Code is wrong — this is a violation that should be fixed
   (B) Decision changed — create a new ADR superseding ADR-003
   (C) Partial exception — document the exception with rationale
   ```

   b. **Ask the user** and wait for their decision before updating the affected section.
   c. **If option (B)** → create a new ADR with status "Supersedes ADR-XXX" and update docs accordingly.
   d. **If option (A)** → do NOT update the architecture docs to match the violation. Note it in a
      `⚠️ Known Violations` section for the next exec-plan run to fix.

**Rules:**

- ❌ NEVER silently change an architecture description to match code that contradicts an existing ADR.
- ❌ NEVER delete or modify an ADR's Decision/Rationale section during auto-update.
- ✅ ADR status can change to "Deprecated" or "Superseded" ONLY with user approval.
- ✅ New ADRs can be created to document evolved decisions, with explicit supersession references.

---

## review_techdocs — Health check

When the user asks for `review_techdocs`, perform a read-only health check (it changes no files):

1. Read all documents in `docs/`.
2. Analyze the current codebase structure.
3. Run the 7-dimension check:

| Check | What to look for |
|-------|-----------------|
| **Staleness** | "Last Updated" dates older than the most recent code changes |
| **Completeness** | Missing sections for existing components, entities, endpoints, integrations |
| **Accuracy** | Documented architecture doesn't match actual code structure |
| **ADR coverage** | Significant technology/pattern choices without corresponding ADRs |
| **Link health** | Broken internal links between documentation pages |
| **Diagram accuracy** | Mermaid diagrams that don't match actual architecture |
| **Getting started** | Setup guide works with current project state |

4. Produce a diagnostic report:

```markdown
## Techdocs Health Check: [Project Name]

**Documents Analyzed:** X files
**Date:** [Date]

### ✅ Passing
- [Check that passed]

### ⚠️ Warnings (Stale or Incomplete)
- [Section] — Last updated [date], but [component] was modified on [date]
- [Section] — Missing documentation for [component/entity/endpoint]

### ❌ Issues Found (Incorrect or Broken)
- [Specific inaccuracy or broken link]

### 📝 Missing ADRs
- [Decision that should have an ADR but doesn't]

### Suggestions
- [Improvement opportunity]
```
