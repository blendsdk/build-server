# Financial-system ambiguity lens

Use this lens whenever the system records, calculates, authorizes, transfers, reconciles, reports, or audits monetary value or financially consequential state.

## Integrity closure checklist

- Ledger model, account types, posting rules, balancing invariants, and immutable history
- Currency identity, minor units, decimal precision, rounding mode, allocation, and residual handling
- Effective, posting, settlement, and event timestamps with timezone and business-day rules
- Idempotency keys, duplicate detection windows, replay behavior, and exactly-once claims
- Transaction boundaries, isolation, locking, partial failure, rollback, retry, and compensation
- Authorization, limits, approvals, segregation of duties, and credential/recovery flows
- Holds, reservations, pending/posted/failed/reversed state transitions
- Reversal, refund, chargeback, correction, backdating, and restatement semantics
- Fees, taxes, rates, rate sources, rate timestamps, and rounding order
- Reconciliation sources, tolerances, unmatched items, dispute handling, and repair authority
- Audit event completeness, immutability, provenance, retention, and privacy
- Overflow, negative values, zero, extreme scale, and malformed/external data
- Reporting consistency, close periods, snapshots, and historical reproducibility
- Regulatory, jurisdictional, and data-residency constraints explicitly supplied by qualified owners

## Required failure narratives

Specify observable state after every boundary failure: request timeout before/after commit, duplicate delivery, dependency outage, partial batch, stale authorization, concurrency conflict, reconciliation mismatch, and crash during recovery. “Retry” is not a complete rule without idempotency and state-observation semantics.

## Gate

The financial-integrity gate fails until every value-changing operation preserves its accounting invariants under duplication, concurrency, failure, retry, reversal, and audit reconstruction.
