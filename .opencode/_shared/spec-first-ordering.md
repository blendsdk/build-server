# Specification-First Task Ordering (shared protocol)

> **CodeOps Artifact Schema**: 1

The **single canonical definition** of CodeOps' specification-first ordering. `make-plan` applies
it when generating `99-execution-plan.md`; `exec-plan` enforces it while executing one. Both link
here; neither carries its own copy.

Every feature implementation phase follows this three-step structure. It prevents tautological
testing — tests that mirror the implementation instead of independently verifying it against the
specification.

```
Phase N: [Feature Name]

  Step N.1: Specification Tests (BEFORE implementation)
    N.1.1  Write specification tests from 07-testing-strategy.md ST-cases
           → File: [feature].spec.test.[ext]
           → Source: 07-testing-strategy.md ST-1 through ST-X
           → MUST NOT read implementation logic when writing these tests
    N.1.2  Run spec tests — verify they FAIL (red phase)
           → Document any that pass pre-implementation with justification

  Step N.2: Implementation
    N.2.1  Implement [feature/component] per technical specification
           → Reference: 03-XX-[component].md
    N.2.2  Run spec tests — verify they PASS (green phase)
           → If any spec test fails: STOP, fix the implementation (NOT the test)

  Step N.3: Implementation Tests & Hardening
    N.3.1  Write implementation tests (edge cases, internals, error paths)
           → File: [feature].impl.test.[ext]
    N.3.2  Full verification (the project's verify command)
```

## Why this ordering

| Step | What it prevents |
|------|-----------------|
| Spec tests BEFORE implementation | Deriving test expectations from the code you just wrote |
| Red-phase verification | Meaningless spec tests (they must test something that doesn't exist yet) |
| Spec tests PASS after implementation | An implementation that doesn't satisfy the specification |
| Impl tests AFTER implementation | Nothing — impl tests MAY be derived from the code (edge cases, internals); spec tests may not |

## Enforcement

**🚫 PROHIBITED:**

- ❌ Writing implementation code before specification tests exist for that feature
- ❌ Skipping the spec-test step ("we'll write tests after")
- ❌ Combining spec tests and implementation in one task, or writing them simultaneously
- ❌ Generating a plan where implementation tasks precede spec-test tasks for the same feature

**✅ REQUIRED in every generated `99-execution-plan.md`:** the three-step ordering per feature
phase; explicit `[feature].spec.test.[ext]` and `[feature].impl.test.[ext]` file references;
references to the ST-cases from `07-testing-strategy.md` in spec-test tasks; a distinct
red-phase verification task.

**Immutable-oracle rule:** if the implementation does not match a spec test, the implementation
is wrong — not the test. Never modify a spec test's expectations to match code. (This rule binds
subagent executors too — a delegated task that hits a failing spec test reports a blocker; it
never edits the test.)

## Small features (compressed form)

You MAY compress into a single step, but the ordering is still mandatory:

```
Step N.1: [Feature Name]
  N.1.1  Write specification tests (from ST-cases)
  N.1.2  Verify spec tests fail (red phase)
  N.1.3  Implement feature
  N.1.4  Verify spec tests pass (green phase)
  N.1.5  Write implementation tests
  N.1.6  Full verification
```

The order `spec tests → red phase → implement → green phase → impl tests → verify` is NEVER
negotiable, regardless of feature size.
