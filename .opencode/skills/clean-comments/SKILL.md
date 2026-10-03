---
name: clean-comments
description: Audit and clean source comments and API documentation without changing behavior. Use for clean comments, clean JSDoc, remove planning references from code, improve API docs, or enforce CodeOps documentation standards. Removes ephemeral requirement/plan identifiers, documents non-trivial public behavior, and supports report-only or references-only modes.
---

# Clean source documentation

## Safety boundary

This is a comment-only workflow. Never alter executable tokens, declarations, types, imports, string literals, generated files, vendored code, snapshots, CodeOps artifacts, or `AGENTS.md`.

## Protocol

1. Detect languages, documentation conventions, generated directories, and repository guidance.
2. Scan comments for ephemeral references such as `RD-*`, `AR-*`, `ST-*`, task identifiers, and `codeops/`, `plans/`, or `requirements/` paths.
3. Identify public/non-trivial entities with missing or misleading documentation, change-history comments, restated code, stale TODOs, and unsupported claims.
4. In report-only mode, cite findings and proposed scope without editing.
5. In references-only mode, restate ephemeral rationale in durable domain language without expanding unrelated documentation.
6. In full mode, document contracts, invariants, units, failure behavior, ownership, examples, and non-obvious rationale where the language/project convention warrants it.
7. Review the diff to prove only comments changed. Run the repository's normal formatter and verification command.

Documentation explains the shipped system, not the temporary process that produced it.
