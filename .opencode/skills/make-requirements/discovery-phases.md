# Phase 1 (Discovery) & Phase 2 (Structuring)

> Read this during **Full Discovery** mode. Phase 1 is a multi-turn interview;
> Phase 2 turns the confirmed scope into a numbered RD structure. The
> Zero-Ambiguity Rule is active from the very first question — see
> `zero-ambiguity-gate.md`.

---

## Phase 1: Discovery & Domain Analysis

A **multi-turn conversation**. Ask questions in batches, wait for answers,
iterate. Never try to produce all requirements in one shot.

### 1.1 Project Vision Interview

Start broad:

- **What is this project?** What problem does it solve? Who is it for?
- **What technology decisions are already made?** (language, framework, database, hosting)
- **What's the scale?** (number of users, data volume, deployment model)
- **Is there an existing system** this replaces or improves upon?
- **What's the timeline / urgency?** (affects MVP scoping)

### 1.2 Stakeholder Mapping

Before features, identify ALL user types and stakeholders. For each role, explore:
what they need from the system; their daily workflow; what frustrates them about
current solutions; what permissions they should and should not have.

```markdown
## Identified Stakeholders

| # | Role | Description | Key Needs |
|---|------|-------------|-----------|
| 1 | [Role Name] | [Who they are] | [What they need] |
| 2 | [Role Name] | [Who they are] | [What they need] |

Does this list look complete? Are there other user types I'm missing?
```

### 1.3 Comparable Systems Analysis (The Secret Weapon)

**The most important sub-phase.** You MUST:

1. **Identify comparable systems** in the domain — name them explicitly so the user can research them.
2. **Extract relevant features** from those systems.
3. **Present them as a selection table** — user marks each Want / Maybe / Skip.

```markdown
## Features From Similar Systems

Based on your description, this project has similarities to [System A], [System B],
and [System C]. Here are features from those systems that might be relevant:

### Category: [Category Name]

| # | Feature | Description | Your Thoughts? |
|---|---------|-------------|----------------|
| X1 | **[Feature Name]** | [What it does and why it's valuable] | ☐ Want / ☐ Maybe / ☐ Skip |
| X2 | **[Feature Name]** | [What it does and why it's valuable] | ☐ Want / ☐ Maybe / ☐ Skip |
```

**Rules:**
- Always name the comparable systems.
- Group features by domain area, not by source system.
- **Include features the user did NOT mention** — that's the whole point.
- Present only the most relevant gaps first: normally 2–5 features in each relevant category.
  Expand a category when the user asks or the domain evidence shows a material omission. Do not
  fill a quota.
- Include the rationale for why each feature might be relevant.
- Treat every extracted feature as optional until the user chooses `Want`; comparable systems are
  evidence for discovery, not authority to enlarge this product.
- If an optional candidate may require material support machinery, add a short possible-cost note
  to its description and batch it with related candidates. Do not run the full Complexity
  Escalation Gate while it is still `Maybe` or unselected. Run the gate only after the user chooses
  `Want` or otherwise confirms the candidate in scope, and before it becomes executable.

### 1.4 User Journey Walkthroughs

For each key user type (from 1.2), walk through their complete journey as a narrative:

```
"A [Role] wants to [goal]. They start by [action]. The system shows [what].
They then [action]. At this point, they need to [requirement]. But wait —
what if [edge case]? This may need [candidate requirement]. Should it be in scope?"
```

This surfaces requirements that fall between the cracks of isolated feature
discussions. Present discovered requirements to the user for confirmation.

### 1.5 "What Happens When..." Scenarios

Proactively explore failure modes and edge cases:

```markdown
## Edge Case Scenarios

| # | Scenario | Question | Impact if Not Handled |
|---|----------|----------|----------------------|
| 1 | [What if X fails?] | [Specific question] | [Consequence] |
| 2 | [What if user does Y?] | [Specific question] | [Consequence] |
```

Common scenarios to explore:
- What happens when a key entity is deleted but has references?
- What happens when a user's role or access changes mid-workflow?
- What happens when the system is unavailable during a critical process?
- What happens when data volumes exceed initial expectations?
- What happens when users try to abuse or game the system?
- What happens when requirements conflict between user types?

### 1.6 Scope Confirmation

After all discovery, present a summary for confirmation:

```markdown
## Scope Confirmation

**Project:** [Name]
**Type:** [SaaS / Internal Tool / Library / etc.]
**Tech Stack:** [Confirmed technologies]

**What's IN scope (confirmed):**
- [Feature/capability 1]

**What's MAYBE in scope (needs decision):**
- [Feature] — [open question]

**What's OUT of scope (explicitly excluded):**
- [Feature/capability] — [reason]

**Key Decisions Made:**
| Decision | Chosen | Rationale |
|----------|--------|-----------|
| [Decision] | [Choice] | [Why] |

**Open Questions (to resolve during RD authoring):**
1. [Question]

Please confirm or adjust before I create the requirement documents.
```

---

## Phase 2: Structuring

### 2.1 Domain Glossary

Establish shared vocabulary before writing any RD:

```markdown
## Domain Glossary

| Term | Definition | Notes |
|------|-----------|-------|
| [Term] | [Precise definition as used in this project] | [Disambiguation if needed] |
```

Define every domain-specific term that could be ambiguous; note where your
project's definition differs from common usage. The glossary goes into
`requirements/README.md` and is referenced by all RDs.

### 2.2 Decomposition into Requirement Documents

Break the confirmed scope into numbered RDs.

**Decomposition heuristics:**
- Start with the smallest set of independently useful, testable RDs that covers confirmed scope.
- Fold project setup, toolchain, and ordinary tests into the first owning RD unless they are an
  independently deliverable workstream.
- Give a data layer, cross-cutting concern, integration, UI area, or domain module its own RD only
  when its behavior and acceptance criteria form a coherent contract. Otherwise keep it with the
  feature that owns it.
- Put cross-cutting non-functional requirements in a dedicated RD only when several features share
  one measurable contract. Keep local performance, security, accessibility, availability, and
  operations criteria in their owning RDs.
- Order the resulting RDs by real dependency. Do not create scaffolding, deployment, monitoring,
  or other support work only to match a standard document sequence.

**Sizing guidance:**
RD count follows the confirmed behavior and coherent document boundaries. It is not a target. If
one RD can state the behavior clearly and remain reviewable, do not split it to satisfy a template.

### 2.3 Dependency Graph

Map dependencies between RDs as a table and a text tree:

```markdown
## Dependency Graph

| # | Document | Depends On |
|---|----------|------------|
| RD-01 | [Name] | — |
| RD-02 | [Name] | RD-01 |
| RD-03 | [Name] | RD-01, RD-02 |

## Visual

    RD-01 (Foundation)
      │
      ├── RD-02 (Data Layer)
      │     ├── RD-03 (Core Module A)
      │     └── RD-04 (Core Module B)
      └── RD-05 (Cross-cutting)
```

### 2.4 MVP vs. Full Vision Phasing

For each feature group, explicitly separate MVP from full product:

```markdown
## Implementation Phases

| Phase | RD Documents | Description | Priority |
|-------|-------------|-------------|----------|
| **A: MVP** | RD-01 → RD-04 | Core functionality, minimum viable product | Must Have |
| **B: Enhanced** | RD-05 → RD-08 | Important features, post-MVP | Should Have |
| **C: Full Product** | RD-09 → RD-12 | Nice-to-have, future iterations | Could Have |
```

### 2.5 Integration Map

If external integrations exist:

```markdown
## External Integrations

| Integration | Protocol | Direction | RD Document |
|------------|----------|-----------|-------------|
| [System] | [REST/OIDC/SMTP/etc.] | [Inbound/Outbound/Both] | RD-XX |
```

After Phase 2 is complete, proceed to the **Zero-Ambiguity Gate**
(`zero-ambiguity-gate.md`) before authoring any RD.

---

## Adapting to Project Type

Tailor discovery questions and comparable-systems analysis to the project type:

| Project Type | Comparable Systems to Explore | Key Discovery Focus |
|---|---|---|
| **SaaS / Web App** | Competing SaaS products, similar industry tools | Multi-tenancy, billing, user management, onboarding |
| **Internal Tool** | Enterprise tools (Jira, Confluence, etc.) | Workflow automation, integrations, permissions |
| **API / Backend** | Public APIs in the space, developer platforms | Versioning, rate limiting, auth, documentation |
| **Library / SDK** | Similar open-source libraries | API design, backward compatibility, bundle size |
| **CLI Tool** | Similar CLI tools (kubectl, gh, etc.) | Command structure, output formats, configuration |
| **Mobile App** | Competing mobile apps | Offline support, push notifications, device features |
| **E-commerce** | Shopify, WooCommerce, Stripe | Catalog, cart, checkout, inventory, payments |
| **CMS / Content** | WordPress, Strapi, Contentful | Content modeling, publishing workflow, media management |
| **Healthcare** | Epic, Cerner, HIPAA-compliant tools | Compliance, audit trails, consent management |
| **Education** | Canvas, Moodle, SONA | Enrollment, grading, scheduling, accessibility |
| **FinTech** | Stripe, Plaid, banking APIs | Regulatory compliance, transaction safety, reconciliation |
