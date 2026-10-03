---
name: setup-routing
description: Configure risk- and capability-based OpenCode subagent routing for a project. Use when the user asks to set up CodeOps routing, specialist reviewers, model or reasoning policy, or project-local agents. Analyzes the system's domains and risks, proposes roles and review requirements, records structured CodeOps policy, and optionally generates project-local OpenCode agent files. Never weakens CodeOps gates when agents are unavailable.
---

# Configure CodeOps routing for OpenCode

Routing is an optimization and isolation mechanism, not a source of correctness. Requirements,
ambiguity, direct artifact checks, verification, and review gates remain identical whether work
runs inline, through a named custom agent, or through a dynamically prompted generic subagent.

## Inputs

Read, in order:

1. `AGENTS.md` and nested guidance;
2. `codeops/codeops.json`, if present;
3. project manifests, languages, frameworks, and verification commands;
4. requirement/specification tags and system invariants;
5. active security, financial, concurrency, performance, and compatibility risks; and
6. current `.opencode/agents/*.md`, preserving all hand-authored files.

## Classify the project

Assign one or more domain capabilities:

- compiler/language semantics;
- financial integrity;
- authentication and authorization;
- tenant isolation;
- distributed systems and concurrency;
- performance critical;
- persistence and migration;
- public API/protocol compatibility;
- web/application behavior; or
- standard product engineering.

Then classify each planned phase:

| Risk | Meaning | Minimum routing |
|---|---|---|
| Critical | A defect can corrupt money/data, break security/isolation, or establish incompatible semantics/contracts | demanding executor where useful plus at least two independent relevant reviewers |
| High | Cross-cutting, difficult to reverse, concurrency-sensitive, migration-heavy, or public-contract work | demanding reasoning plus one independent reviewer |
| Standard | Normal feature work with bounded impact | inline or balanced executor plus one review pass |
| Mechanical | Fully specified, locally reversible transformation | fast executor or inline; deterministic verification still required |

## Propose before writing

Present:

- detected domains and concrete evidence;
- phase tag → capability/effort policy;
- required specialist reviewers;
- proposed concurrency limit;
- whether custom TOML agents add value over dynamic packets; and
- exact files that would change.

Model names are implementation choices, not policy names. Default to the current OpenCode model guidance and environment availability. A project override may pin a model, but every role must remain operable without the pin.

## Structured policy

Store CodeOps policy in `codeops/codeops.json`, not in `AGENTS.md`. `AGENTS.md` receives only a concise instruction that CodeOps routing is configured and that material ambiguity and verification gates may not be bypassed.

Example policy fields are documented in [routing.md](routing.md).

## Optional project-local agents

Only after confirmation, generate selected `.opencode/agents/*.md` files with:

```bash
python3 "${CODEOPS_PLUGIN_ROOT}/scripts/install_agents.py" --project . --roles ROLE[,ROLE...]
```

The installer:

- creates only generated files carrying the CodeOps marker;
- never overwrites a hand-authored agent;
- supports `--dry-run` and `--check`;
- uses read-only sandboxing for auditors and challengers;
- writes complete developer instructions; and
- never modifies global OpenCode configuration.

## Runtime dispatch rule

For every dispatch, send a bounded packet containing scope, authoritative excerpts, relevant decisions, target paths, verification command, forbidden actions, and required output schema. Do not assume a custom agent inherits the conversation's system model.

When a requested role is unavailable:

1. use a generic subagent with the complete role packet when isolation or independence matters;
2. otherwise run inline;
3. report the fallback; and
4. preserve every gate and required reviewer count.

## Verification

After setup:

```bash
python3 "${CODEOPS_PLUGIN_ROOT}/scripts/install_agents.py" --project . --check
```

Report configured roles, model pins if any, read-only roles, fallbacks, and unresolved capability gaps.
