# Phase 1C: Zero-Ambiguity Gate — caller preamble (make-plan)

> **CodeOps Artifact Schema**: 1

The gate itself is defined ONCE in **[../../_shared/zero-ambiguity-gate.md](../../_shared/zero-ambiguity-gate.md)**
— read it now, before Phase 2. This preamble only binds it to make-plan:

- **Phase**: 1C — fires after Phase 1 discovery, before any plan document except the incrementally
  persisted register is written.
- **Blocked artifacts while closed**: every file in the plan folder except the incrementally
  persisted register itself — `00-index.md`, `01-requirements.md`, `02-current-state.md`, all
  `03-XX` specs, `07-testing-strategy.md`, `99-execution-plan.md`.
- **Register location**: `<plan folder>/00-ambiguity-register.md` (resolve the folder per
  `_shared/layout-convention.md`).
- **Plan-specific scan notes**: pay extra attention to *Naming & terminology* (file/dir/class/
  function/API names the plan will create) and *Technical unknowns* (architecture choices the
  execution plan will commit to).
- Items pre-resolved by a grill-me session import as resolved/deferred rows and are not
  re-confirmed; only new rows need the user's confirmation (shared gate, rule 3).
