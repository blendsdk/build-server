# Phase 2B — Content Quality Gate (caller preamble, upgrade-plan)

> **CodeOps Artifact Schema**: 1

The Content Quality Gate IS the shared Zero-Ambiguity Gate, scoped to **existing documents**: the
gate itself is defined ONCE in **[../../_shared/zero-ambiguity-gate.md](../../_shared/zero-ambiguity-gate.md)**
— read it before running Phase 2B. This preamble binds it to upgrade-plan and adds the
upgrade-only scanning rules:

- **Phase**: 2B — Phase 3 (structural upgrades) is BLOCKED until it passes. While blocked:
  no structural upgrades, no version-stamp updates, no document edits.
- **Scope**: scan ALL existing documents of the artifact being upgraded across the shared gate's
  12 categories, looking for content that predates the gate (vague decisions, unstated
  assumptions, AI-guessed specifications). Upgrading format without fixing content produces a
  polished but hollow artifact.
- **Register handling**: append to the artifact's existing register (continue numbering) or
  create a fresh one if none exists; tag every upgrade-found entry `(upgrade)` in the Category
  column. Record `Upgrade From:` / `Upgrade To:` in the register header.

## Vague-language patterns to flag

```
"TBD", "to be determined", "something like", "we could", "probably", "might", "maybe",
"a reasonable approach", "as needed", "if applicable", "similar to", "standard approach",
"best practices", "etc.", "and so on"
```

**Materiality clause:** flag an instance only where the vagueness **hides a decision** — wording
whose resolution would change what gets built, tested, or secured. Non-normative prose (context,
examples, illustrative asides) is exempt. When unsure whether it hides a decision, flag it.

## After the gate passes

Phase 3 applies structural upgrades AND writes every resolved content gap into the appropriate
document with an `AR #` back-reference, so document content and register stay linked.
