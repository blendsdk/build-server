# Phase 3 — Quality Checklist

Run this before finalizing the plan documents. The **Specification-First Testing**, **Security-First**, **Zero-Ambiguity**, and **Execution Plan Completeness** blocks are NON-NEGOTIABLE.

## ✅ Completeness
- [ ] All requirements captured
- [ ] All affected components identified
- [ ] All scope decisions documented
- [ ] All dependencies mapped
- [ ] Every planned item traces to the confirmed scope baseline or a user-kept `SE-*` entry
- [ ] Strict scope contains no optional suggestions; exploration proposals remain non-executable
      until the user chooses `Keep`
- [ ] The planned solution passes the coding standards' **minimum-sufficient design** rule
- [ ] The plan states the smallest viable design; every larger material support surface is removed
      or has an explicitly user-approved `Technical (complexity escalation)` AR entry
- [ ] No complexity escalation relies on silence, generic recommendation acceptance,
      `--auto-design`, a finding ruling, or permission to apply fixes as approval

## ✅ Granularity
- [ ] Each task is one reviewable change: 1-3 files, ~50-150 lines, immediately testable
- [ ] Anything touching >=6 files, 200+ lines, or 3+ concerns is SPLIT into multiple tasks
- [ ] Each task has clear deliverables
- [ ] Each task is independently testable

## ✅ Dependencies
- [ ] Phase dependencies documented
- [ ] Task dependencies documented
- [ ] No circular dependencies
- [ ] Dependency order is logical

## ✅ Testing
- [ ] Every component has test requirements
- [ ] E2E tests are planned when feasible and applicable; otherwise the plan records `N/A` with a
      concrete reason and does not create a new harness only to satisfy the template
- [ ] Test coverage goals defined

## ✅ Specification-First Testing — 🚨 NON-NEGOTIABLE
- [ ] `07-testing-strategy.md` contains the `🚨 Specification Test Cases` section with concrete ST-cases
- [ ] Every ST-case has concrete input → expected output pairs (not just test names/descriptions)
- [ ] Every ST-case traces to a requirement, spec document, RFC, or AR entry
- [ ] ST-case expectations are derived from specification documents, NOT from imagined implementation behavior
- [ ] `99-execution-plan.md` follows the three-phase task ordering: spec tests → implementation → impl tests
- [ ] Spec test tasks reference ST-cases from `07-testing-strategy.md`
- [ ] Spec test and impl test files use separate naming conventions (`*.spec.test.*` and `*.impl.test.*`)
- [ ] A red-phase verification task exists in the execution plan (verify spec tests fail before implementation)

## ✅ No Dead Code
- [ ] No unused parameters (except interface contracts, overrides, and framework-required signatures)
- [ ] No unused functions, classes, or modules
- [ ] No unreachable code or commented-out blocks
- [ ] Language-specific dead code tooling enabled (if available)

## ✅ Security-First — 🚨 NON-NEGOTIABLE
- [ ] All user input validated and sanitized server-side
- [ ] Injection prevention addressed (SQL, XSS, command injection, path traversal)
- [ ] Authentication & authorization properly designed
- [ ] Rate limiting planned for public and authentication endpoints
- [ ] No hardcoded secrets or credentials — secrets management strategy defined
- [ ] Sensitive data encrypted at rest and in transit
- [ ] Error responses expose no internal details (no stack traces, no DB schemas)
- [ ] Existing or required infrastructure is hardened (non-root containers, minimal base images,
      no secrets in images/CI); projects with no infrastructure change record `N/A` rather than
      inventing one
- [ ] Security test cases included in the testing strategy

## ✅ Zero-Ambiguity (per Phase 1C) — 🚨 NON-NEGOTIABLE
- [ ] Ambiguity Register (`00-ambiguity-register.md`) exists and is saved to disk
- [ ] Every register entry has Status = `✅ Resolved` with an explicit user decision or a
      complete auto-design delegated record, or a complete, explicitly user-approved `⏸ Deferred`
      record
- [ ] Every deferred decision is absent from executable plan content; deferred extra machinery is
      absent from the plan
- [ ] All decisions in plan documents have AR # back-references (only exceptions: universally obvious facts + zero-semantic-impact formatting)
- [ ] No plan document contains AI-assumed defaults, inferred behaviors, or guessed specifications
- [ ] Surface-during-authoring rule was followed — new ambiguities were added to the register and
      resolved by the user or, when active and eligible, under the auto-design policy
- [ ] Scope expansion was never disguised as ambiguity resolution or delegated to auto-design

## ✅ Execution Plan Completeness — 🚨 NON-NEGOTIABLE
- [ ] Every phase section carries its tasks as a checkbox list (`- [ ] N.N.N …` with target file)
- [ ] Every task appears exactly once document-wide — no consolidated restatement anywhere
- [ ] The execution-rule callout (single-source marks, two-stage `[~]`/`[x]`, progress-header update, resume rule) is present under Implementation Phases
- [ ] Task numbering is consistent across phase sections and the phase table

## ✅ Reference, Don't Restate — 🚨 NON-NEGOTIABLE
- [ ] Every citation (ST-#, 03-doc §, AR-#) resolves to an existing anchor/entry
- [ ] No document restates content owned by another (spot-check 3 facts: each has a single owner)
- [ ] RD-based plans use the thin delta `01-requirements.md`; standalone plans use the full form
- [ ] No audit/traceability table duplicates AR or ST rows (citations only)

## ✅ Format
- [ ] All documents follow the templates
- [ ] Tables are properly formatted
- [ ] Task numbers follow the convention (Phase.Session.Task)
- [ ] Checkboxes included for tracking
- [ ] `00-index.md` and `99-execution-plan.md` are stamped with `> **CodeOps Artifact Schema**: 1`
