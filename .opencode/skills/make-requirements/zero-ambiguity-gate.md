# Phase 2B: Zero-Ambiguity Gate — caller preamble (make-requirements)

> **CodeOps Artifact Schema**: 1

The gate itself is defined ONCE in **[../../_shared/zero-ambiguity-gate.md](../../_shared/zero-ambiguity-gate.md)**
— read it now, before Phase 3. This preamble only binds it to make-requirements:

- **Phase**: 2B — fires after discovery/challenge (Phases 1–2), before ANY requirement document
  is written. Also applies, scoped to new decisions, during add_requirement and upgrades.
- **Blocked artifacts while closed**: every `RD-XX-*.md` and `requirements/README.md`.
- **Register location**: `<requirements dir>/00-ambiguity-register.md` (resolve the directory per
  `_shared/layout-convention.md`).
- **Requirements-specific scan notes**: pay extra attention to *Scope ambiguities* (MVP vs.
  future, conflicting stakeholder needs), *Data & state* (cardinality, ownership), and
  *Security & compliance* (regulatory gaps) — requirements set the contract everything
  downstream inherits.
- Items pre-resolved by a grill-me session import as resolved/deferred rows and are not
  re-confirmed; only new rows need the user's confirmation (shared gate, rule 3).
