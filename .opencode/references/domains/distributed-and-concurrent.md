# Distributed and concurrent system ambiguity lens

Use this lens for multiple threads/processes/nodes, queues, actors, workflows, replicated state, caches, background jobs, and asynchronous integrations.

## Concurrency and failure checklist

- State ownership, mutation authority, synchronization, and atomicity boundaries
- Ordering guarantees per key, partition, stream, request, and observer
- Delivery semantics, deduplication, idempotency, replay, and poison-message behavior
- Consistency model, visibility, stale reads, conflict resolution, and convergence
- Transactions across resources, outbox/inbox, sagas, compensation, and orphan recovery
- Timeout, cancellation, deadline propagation, retries, backoff, jitter, and retry budgets
- Leader election, leases, fencing tokens, split brain, and clock assumptions
- Backpressure, admission control, queue bounds, overload, fairness, and starvation
- Deadlock/livelock/race prevention and safe shutdown
- Partial availability, dependency degradation, circuit breaking, and health semantics
- Schema/protocol evolution with mixed-version participants
- Observability and correlation sufficient to reconstruct distributed outcomes

## Required interleavings

Specify and test at least: concurrent duplicate requests, read during write, fail before/after durable commit, timeout with unknown outcome, retry on a different node, reordered delivery, delayed stale worker, partition and heal, cancellation during side effect, and rolling mixed-version deployment.

## Gate

The gate fails when correctness relies on unstated timing, a single delivery, synchronized clocks, failure-free dependencies, or process-local state that is not process-local in deployment.
