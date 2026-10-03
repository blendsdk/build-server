# Web application ambiguity lens

Use this lens for browser applications, HTTP APIs, mobile backends, and user-facing network services.

## Behavior and boundary checklist

- Actors, roles, tenant boundaries, resource ownership, authorization matrix, and administrative exceptions
- Authentication, session/token lifecycle, revocation, recovery, MFA, and device behavior
- API request/response schemas, validation, errors, pagination, filtering, ordering, idempotency, and versioning
- UI states: initial, loading, empty, partial, success, stale, offline, unauthorized, forbidden, validation error, and server failure
- State transitions, optimistic updates, retries, duplicate submission, and conflict resolution
- Accessibility: semantics, keyboard, focus, announcements, contrast, motion, and error association
- Responsive/browser/device support and localization/timezone behavior
- Caching layers, invalidation, privacy, consistency, and stale-data UX
- File/upload/download handling and untrusted content
- CSRF, XSS, injection, SSRF, redirect, cookie, CORS, CSP, and rate-limit boundaries
- Background jobs, notifications, webhooks, scheduling, and eventual-consistency visibility
- Observability, privacy-safe logging, support diagnostics, feature flags, rollout, and rollback
- Deployment compatibility, migrations, zero-downtime constraints, and client skew

## Gate

The web gate fails when any actor/action/resource combination lacks an authorization result, any user-visible transition lacks a defined state, or any network operation lacks validation, error, retry/idempotency, and stale/concurrent behavior appropriate to its risk.
