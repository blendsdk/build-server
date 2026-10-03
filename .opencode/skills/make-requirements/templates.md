# Phase 3 Authoring: Templates & Rules

> Read this when authoring requirement documents (after the Zero-Ambiguity Gate
> has passed). Contains the output structure, the README template, the universal
> RD template, acceptance-criteria specificity rules, and the "Did You Consider…"
> checklist used in Phase 4.

---

## 3.1 Output Structure

Create all documents in the `requirements/` directory:

```
requirements/
├── 00-ambiguity-register.md    # Zero-Ambiguity Gate register (audit trail)
├── README.md                   # Index, glossary, dependency graph, implementation order
├── RD-01-[feature-name].md     # First requirement document
├── RD-02-[feature-name].md     # Second requirement document
├── ...
└── RD-XX-[feature-name].md     # Last requirement document
```

## 3.2 README.md Template

```markdown
# [Project Name] — Requirements Documents

> **Project**: [Project Name] — [Brief Description]
> **Status**: [Draft | Review | Complete]
> **Created**: [Date]
> **Architecture**: [Tech stack summary]
> **CodeOps Artifact Schema**: 1

---

## Overview

[2–3 paragraph description of the project]

## Minimum-Sufficient Baseline

**Original goal:** [The outcome the user asked for]

**Smallest viable design:** [The smallest product scope that achieves the goal]

**Excluded support machinery:** [Layers, dependencies, harnesses, or infrastructure not needed]

**Approved complexity:** [Complexity-escalation AR references, or `None`]

## Domain Glossary

| Term | Definition |
|------|-----------|
| [Term] | [Definition] |

## Document Index

| # | Document | Description | Depends On |
|---|----------|-------------|------------|
| **AR** | [Ambiguity Register](00-ambiguity-register.md) | Zero-Ambiguity Gate decisions (audit trail) | — |
| **RD-01** | [Link to doc] | [Description] | — |
| **RD-02** | [Link to doc] | [Description] | RD-01 |

## Dependency Graph

[Text-based dependency tree]

## Suggested Implementation Order

| Phase | Documents | Description |
|-------|-----------|-------------|
| **A: MVP** | RD-01 → RD-XX | [Description] |
| **B: Enhanced** | RD-XX → RD-XX | [Description] |

## Key Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| [Decision] | [Choice] | [Why] |

## How to Use These Documents

Each requirements document is designed to be used with the make-plan skill:

1. Pick a requirements document (e.g., RD-01)
2. Run the make-plan skill
3. The plan system uses the RD as input to create implementation plans
4. Run the exec-plan skill for the feature
5. Implement iteratively
```

## 3.3 Universal RD Template

Every requirement document follows this structure:

````markdown
# RD-XX: [Feature Name]

> **Document**: RD-XX-[feature-name].md
> **Status**: Draft
> **Created**: [Date]
> **Project**: [Project Name]
> **Depends On**: [List of RD dependencies, or "—" if none]
> **CodeOps Artifact Schema**: 1

---

## Feature Overview

[1–2 paragraphs: what this feature does and why it's needed, written so someone
unfamiliar with the project can understand the purpose.]

---

## Functional Requirements

### Must Have
- [ ] [Requirement — specific, testable, implementable]

### Should Have
- [ ] [Requirement]

### Won't Have (Out of Scope)
- [Explicitly excluded item] — [reason or which RD covers it]

---

## Technical Requirements

### [Sub-section per major technical concern]

[Architecture details, data structures, interfaces, algorithms, protocols.
Include pseudocode or real code examples where clarity demands it. Include tables
for structured information (env vars, config keys, API endpoints).]

---

## Integration Points

### With RD-XX ([Name])
- [How this requirement connects to that one]

---

## Scope Decisions

| Decision | Options Considered | Chosen | Rationale | AR Ref |
|----------|-------------------|--------|-----------|--------|
| [Decision] | [Option A, B, C] | [Chosen] | [Why] | AR #X |

> **Traceability:** Every scope decision must reference the Ambiguity Register
> entry (AR #) that resolved it. See `00-ambiguity-register.md`.

---

## Security Considerations

> **🚨 This section is MANDATORY for every RD.** See your project's security
> coding standards (AGENTS.md). Mark a line `N/A` with a short reason when the RD has no matching
> exposure. Do not add security infrastructure only to populate this section.

- **Data sensitivity**: [What sensitive data does this feature handle? PII, credentials, tokens, financial data?]
- **Input validation**: [What user inputs exist? How are they validated and sanitized?]
- **Authentication & authorization**: [Who can access this feature? What permissions are required?]
- **Injection risks**: [SQL queries, HTML rendering, shell commands, or file operations involving user input?]
- **Encryption needs**: [Does data need encryption at rest or in transit?]
- **Rate limiting**: [Endpoints susceptible to brute force or abuse?]
- **Infrastructure**: [Container hardening, secrets management, network exposure?]

---

## Acceptance Criteria

1. [ ] [Testable criterion]
2. [ ] [Testable criterion]
3. [ ] Security requirements verified (input validation, injection prevention, auth, encryption)
````

## 3.4 RD Authoring Guidelines

- **Data Model Sketches**: for domain RDs, include conceptual entity relationships (not full SQL, but "A Project has many Participants. A Lab has many Equipment items.").
- **Security & Privacy Annotations**: flag PII, encryption needs, consent tracking, GDPR relevance.
- **Complexity Estimates**: tag each requirement section with estimated complexity (S/M/L/XL) to aid planning.
- **Non-Functional Requirements**: keep local performance, security, scalability, accessibility,
  availability, and recovery criteria in the RD that owns the behavior. Create a dedicated RD only
  when several features share one measurable cross-cutting contract and the user has approved any
  resulting complexity escalation.

## 3.4B 🚨 Acceptance Criteria Specificity — NON-NEGOTIABLE

**Acceptance criteria MUST be specific enough that a developer who has never
spoken to the user can write a correct test from the criterion alone.** This
prevents the acceptance-criteria tautology — where vague criteria let later tests
interpret them however the implementation happens to work, creating a
self-validating loop.

**Every acceptance criterion MUST meet ALL of these:**

1. **Measurable outcome** — a concrete, observable result (not "works correctly").
2. **Specific values** — exact numbers, formats, status codes, or field names where applicable.
3. **Standard references** — when behavior must conform to a standard (RFC, protocol, spec), cite the specific standard and section (e.g., "per RFC 8414 §2", not "follows the OIDC spec").
4. **Boundary conditions** — what happens at the edges (empty input, maximum length, zero items, expired tokens).
5. **Negative cases** — what should NOT happen / what should be rejected.

**Examples:**

```
❌ BAD: "The API returns a valid OIDC discovery document"
✅ GOOD: "GET /.well-known/openid-configuration returns a JSON document where the
   'issuer' field exactly matches the URL used to access the endpoint (per RFC
   8414 §2), and includes all REQUIRED fields: issuer, authorization_endpoint,
   token_endpoint, jwks_uri, response_types_supported, subject_types_supported,
   id_token_signing_alg_values_supported"

❌ BAD: "Users can reset their password"
✅ GOOD: "POST /auth/reset-password with a valid email returns 202 Accepted, sends
   an email with a one-time reset link that expires after 60 minutes, and the link
   cannot be reused after the password is changed"

❌ BAD: "The system handles invalid input gracefully"
✅ GOOD: "POST /api/users with a missing 'email' field returns 400 with
   { error: 'VALIDATION_ERROR', details: [{ field: 'email', message: '...' }] }.
   POST /api/users with an email longer than 254 characters returns 400."
```

**If the user gives vague acceptance criteria** during review, ask for specifics:
*"This criterion says 'handles errors properly' — what specific error conditions
should be handled, and what should the response look like for each?"*

**Traceability to tests:** when the make-plan skill later derives test cases from
these criteria, each spec test expectation MUST map directly to a specific
acceptance criterion. If a criterion is too vague to produce a concrete test
assertion, the criterion is defective — not the test.

## 3.5 Authoring Workflow

Write RDs one at a time, presenting each to the user for review:

1. Write RD-01 → present → collect feedback → revise.
2. Write RD-02 → present → collect feedback → revise.
3. Continue until all RDs are written.
4. If the session is getting long, save progress to `requirements/_draft/` and note which RDs remain (RDs are written to disk as completed — never held only in memory).

---

## Phase 4 reference: "Did You Consider…" Checklist

Before finalizing, run through commonly forgotten requirements:

```markdown
## Commonly Forgotten Requirements — Final Check

| # | Concern | Addressed? | In Which RD? |
|---|---------|------------|--------------|
| 1 | Audit logging / activity trail | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 2 | Data export (CSV, Excel, API) | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 3 | API versioning | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 4 | Rate limiting | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 5 | Error messages & user-facing UX | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 6 | Empty states (no data yet) | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 7 | Loading states & optimistic UI | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 8 | Accessibility (WCAG) | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 9 | Mobile responsiveness | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 10 | Backup & disaster recovery | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 11 | Monitoring & alerting | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 12 | Email notifications & templates | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 13 | Search functionality | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 14 | Pagination for all list views | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 15 | File upload / document management | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 16 | Soft delete vs hard delete | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 17 | Timezone handling | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 18 | Localization / i18n | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 19 | Terms of service / privacy policy | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 20 | GDPR / data retention / right to delete | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 21 | Session management / timeout | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 22 | Graceful degradation / offline behavior | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 23 | Admin / super-admin capabilities | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 24 | User onboarding / first-time experience | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 25 | Configuration management (feature flags, settings) | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 26 | **🚨 Input validation & sanitization (server-side)** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 27 | **🚨 Injection prevention (SQL, XSS, command, path traversal)** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 28 | **🚨 Authentication & authorization model** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 29 | **🚨 Rate limiting (auth endpoints, public APIs)** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 30 | **🚨 Secrets management (no hardcoded credentials)** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 31 | **🚨 Data encryption (at rest and in transit)** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 32 | **🚨 Infrastructure hardening (non-root containers, minimal images, CI secrets)** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
| 33 | **🚨 Security testing (injection tests, auth bypass, privilege escalation)** | ☐ Yes / ☐ No / ☐ N/A | RD-XX |
```

> **🚨 Items 26–33 are NON-NEGOTIABLE** — they must be addressed in every
> project. See your project's security coding standards (AGENTS.md) for the full
> standard. Acceptance criteria for these map to your project's testing standards
> (AGENTS.md). `N/A` is valid only with a concrete reason. Addressing an item does not authorize a
> new service, framework, or infrastructure surface; that still requires the Complexity Escalation
> Gate when triggered.
