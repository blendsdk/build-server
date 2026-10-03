# Domain-lens selection

Before requirements discovery and again before specification preflight, classify the system using repository evidence and user intent. Select every applicable lens; complex systems commonly require several.

| Evidence | Lens |
|---|---|
| Grammar, parser, IR, optimizer, type checker, evaluator, query planner, protocol codec | compiler and language |
| Money, balances, invoices, payments, pricing, tax, ledger, reconciliation | financial system |
| Browser UI, HTTP API, sessions, roles, tenant resources | web application |
| Threads, workers, queues, events, replicas, workflows, caches, multiple nodes | distributed and concurrent |
| Persistent schema, migration, backfill, import/export, retention, serialized artifacts, durable caches, file/protocol format evolution, or mixed-version compatibility | data and migration |

Treat compatibility language as evidence, not decoration. If an old artifact,
database, cache entry, message, module, or client must continue to work after a
change, select **data and migration** and define the version boundary, upgrade or
invalidation path, rollback behavior, and mixed-version window. An artifact does
not need to be a database row for evolution semantics to matter.

Always apply universal CodeOps ambiguity categories as well. Domain lenses add questions; they never replace scope, actors, failure behavior, security, quality attributes, traceability, or verification.
