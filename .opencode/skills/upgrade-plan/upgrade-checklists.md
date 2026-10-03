# Phase 3 — Per-Document Re-evaluation Checklists (Reference)

The upgrade-plan skill links here. Use these checklists in Phase 3, after the Content Quality Gate
([content-quality-gate.md](content-quality-gate.md)) has passed. Apply the **plan checklists** when
upgrading `plans/[feature-name]/`, and the **requirements checklists** when upgrading
`requirements/`.

For every document: re-evaluate against current standards (the make-plan skill's current standards
for plans; the make-requirements skill's current standards for requirements), add the version stamp
`> **CodeOps Artifact Schema**: 1` where stamps belong, and write in any content fixes resolved
during Phase 2B with an `AR #` back-reference. Always honor the Content Preservation Rules in
SKILL.md — never destroy user work.

---

## Plan upgrade — re-evaluation checklists

For a whole nested project, use `codeops_plan_migrate.py <codeops-dir>` to preview the mechanical
RD mapping and obsolete-graph deletion after these content checks pass. Apply only from a clean
Git tree and only when the preview has no blocked plan.

Re-evaluate each plan document against the make-plan skill's current standards.

### `00-index.md`
- [ ] Version stamp present? → Add `> **CodeOps Artifact Schema**: 1` if missing.
- [ ] Follows the current index template structure?
- [ ] Navigation links to all plan documents?
- [ ] Document count and overview accurate?

### `00-ambiguity-register.md`
- [ ] Exists? → If not, it was created during Phase 2B.
- [ ] All entries resolved with explicit user decisions?
- [ ] Upgrade entries tagged with `(upgrade)` in the Category column?
- [ ] `AR #` back-references added to all plan documents for resolved content gaps?

### `01-requirements.md`
- [ ] Security requirements section present? (per your project's coding standards — AGENTS.md)
- [ ] Acceptance criteria for each requirement?
- [ ] Requirements numbered and categorized?
- [ ] All scope decisions have `AR #` back-references?
- [ ] No vague language remaining?

### `02-current-state.md` (if it exists)
- [ ] Gap-analysis format follows the current template?

### `03-XX` technical specification documents
- [ ] **Preserve user-authored technical decisions verbatim.**
- [ ] Add missing structural sections (e.g. error-handling table, testing requirements).
- [ ] Insert `AR #` back-references for content gaps resolved during Phase 2B.
- [ ] No vague language remaining?

### `07-testing-strategy.md` (if it exists)
- [ ] Follows current testing standards — your project's testing standards (AGENTS.md)?
- [ ] Coverage-goals table present?
- [ ] Test categories clearly defined?

### `99-execution-plan.md`
- [ ] Version stamp present? → Add `> **CodeOps Artifact Schema**: 1` if missing.
- [ ] Commit-mode flags documented? (`--ask-commit`, `--no-commit`, `--auto-commit`)
- [ ] Session protocol section present and current?
- [ ] Success criteria includes a post-completion re-analysis step?
- [ ] Success criteria includes a security-hardening check?
- [ ] Success criteria includes a dead-code check?
- [ ] Success criteria includes zero-ambiguity verification?
- [ ] Techdocs-update step present in success criteria (via the techdocs skill)?
- [ ] Dependencies section present?

### Cross-references (all plan documents)
- [ ] References point to current skill/command names (make-plan skill, make-requirements skill,
      techdocs skill, the `git-commit` skill commands, the project's AGENTS.md)?
- [ ] No references to deprecated or renamed rules / MCP calls?

---

## Requirements upgrade — re-evaluation checklists

Re-evaluate each requirements document against the make-requirements skill's current standards.

### `00-ambiguity-register.md`
- [ ] Exists? → If not, it was created during Phase 2B.
- [ ] All entries resolved with explicit user decisions?
- [ ] Upgrade entries tagged with `(upgrade)` in the Category column?
- [ ] `AR #` back-references added to all RD documents for resolved content gaps?

### `README.md`
- [ ] Version stamp present? → Add `> **CodeOps Artifact Schema**: 1` if missing.
- [ ] Follows the current README template?
- [ ] Dependency graph present and accurate?
- [ ] Domain glossary present and complete?
- [ ] Document index lists all RD documents?
- [ ] Ambiguity Register listed in the document index?

### Individual RD documents (`RD-XXX-*.md`)
- [ ] Version stamp present? → Add `> **CodeOps Artifact Schema**: 1` if missing.
- [ ] Security considerations section present and complete? (per your project's coding standards — AGENTS.md)
- [ ] Acceptance criteria defined for each requirement?
- [ ] Dependencies on other RDs documented?
- [ ] Scope decisions have `AR #` back-references?
- [ ] Integration points section present?
- [ ] No vague language remaining?
- [ ] Priority and status fields present?
- [ ] Techdocs-update section present (via the techdocs skill)?

### Cross-references (all requirements documents)
- [ ] References point to current skill/command names (make-requirements skill, make-plan skill,
      techdocs skill, the `git-commit` skill commands, the project's AGENTS.md)?
- [ ] No references to deprecated or renamed rules / MCP calls?
