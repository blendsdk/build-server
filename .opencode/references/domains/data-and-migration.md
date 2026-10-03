# Data and migration ambiguity lens

Use this lens for persistent schemas, imports/exports, migrations, indexing, backfills, retention, and data-model changes.

## Data lifecycle checklist

- Entity identity, ownership, cardinality, constraints, nullability, uniqueness, and invariants
- Canonical representation, normalization/denormalization, units, encoding, and precision
- Create/update/delete/archive/restore lifecycle and referential behavior
- Transaction/isolation requirements and concurrent writers/readers
- Query access patterns, indexes, scale assumptions, and performance bounds
- Sensitive-data classification, encryption, access, masking, retention, deletion, and audit
- Schema versioning and compatibility across application versions
- Migration preconditions, online/offline mode, locks, batching, throttling, and checkpoints
- Backfill correctness, resumability, idempotency, validation, and repair
- Rollforward, rollback, irreversible steps, backups, restore proof, and disaster recovery
- Import validation, duplicate/collision rules, partial files, and provenance
- Derived data/cache/index rebuild and consistency checks

## Gate

The gate fails until every migration has measurable pre/postconditions, bounded operational impact, resumable/idempotent behavior, verification, and a recovery path appropriate to irreversibility and data criticality.
