# add_requirement & review_requirements Protocols

> Read this when the user is in **Add One RD** or **Health Check** mode (see
> Step 0 in SKILL.md). Both operate on an existing `requirements/` set and reuse
> the gate (`zero-ambiguity-gate.md`) and templates (`templates.md`).

---

## add_requirement Protocol

Triggered by "add_requirement", "add a feature/RD", "I also need …" when a
`requirements/` set already exists.

1. Read `requirements/README.md` to understand the current set.
2. Ask the user: *"What new capability or feature do you want to add?"*
3. Run a **condensed discovery** for just this feature — comparable-systems analysis and edge-case scenarios (see `discovery-phases.md` §1.3 and §1.5).
4. **🚨 Run the Zero-Ambiguity Gate for this new RD.** Compile an Ambiguity Register scoped to
   just this feature and resolve every item. In normal mode, resolve material items with the user.
   With active auto-design, resolve eligible technical items under the shared policy and escalate
   reserved items. **Append** new AR entries to the existing
   `requirements/00-ambiguity-register.md` (create it if it doesn't exist). All gate rules apply:
   no silent deferrals, unauthorized delegation, or guesswork. See `zero-ambiguity-gate.md`.
5. Determine where in the dependency graph the new RD fits.
6. Assign the next available RD number.
7. Write the new RD following the universal template, with AR # traceability (see `templates.md` §3.3).
8. Update `requirements/README.md`:
   - Add it to the document index.
   - Update the dependency graph.
   - Update implementation phases if affected.
9. Run cross-reference validation against the existing RDs (see SKILL.md Phase 4.1).
10. Sync the roadmap if one exists (SKILL.md Phase 4.4).

---

## review_requirements Protocol

Triggered by "review_requirements", "check my requirements", "what's
missing/inconsistent" when a `requirements/` set exists. Produces a diagnostic
report — it does NOT modify the RDs unless the user then asks.

1. Read all documents in `requirements/`.
2. Run these checks:
   - **Completeness** — every "Must Have" has acceptance criteria (and they meet the specificity rules in `templates.md` §3.4B).
   - **Consistency** — no contradictions between RDs.
   - **Coverage** — run the "Did You Consider…" checklist (`templates.md`).
   - **Dependencies** — no circular dependencies; all references valid.
   - **Scope creep** — "Should Have" items that should be "Won't Have".
   - **Orphans** — features mentioned but not owned by any RD.
   - **Traceability** — decisions in RDs back-reference AR # entries; the register exists and is fully resolved.
3. Produce a diagnostic report:

```markdown
## Requirements Health Check: [Project Name]

**Documents Analyzed:** X RDs
**Date:** [Date]

### ✅ Passing
- [Check that passed]

### ⚠️ Warnings
- [Minor issue — recommendation]

### ❌ Issues Found
- [Serious gap or inconsistency — action required]

### Suggestions
- [Improvement opportunity]
```

After presenting the report, offer to fix the issues found — e.g. via
add_requirement for missing coverage, or by revising specific RDs (each revision
that introduces a new decision must go through the Zero-Ambiguity Gate).
