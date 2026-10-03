---
name: outcome-review
description: Review local CodeOps outcome evidence to improve workflow quality without uploading project content. Use for CodeOps retrospective, workflow metrics, escaped findings, rework analysis, planning accuracy, or project process review. Separates plugin-level problems from project-specific configuration and recommends only evidence-backed changes.
---

# CodeOps outcome review

Outcome evidence is opt-in, local, and content-free. Invocation counts are not quality evidence.

## Useful measures

- planned versus verified tasks;
- first-pass verification rate;
- implementation/review rework cycles;
- escaped critical or major findings;
- unplanned files or scope changes;
- assumptions later invalidated;
- runtime ambiguities by owning stage;
- interrupted-session recovery accuracy; and
- user decisions that could have been resolved from existing evidence.

## Protocol

1. Confirm metrics are enabled in `codeops/codeops.json`. If disabled or absent, report that no outcome history is available; do not infer one from transcripts.
2. Read only the local structured event store through `${CODEOPS_PLUGIN_ROOT}/scripts/codeops_outcomes.py`; do not parse project content into metrics.
3. Establish sample size and period before interpreting rates.
4. Classify recommendations:
   - **plugin:** recurring protocol, validator, prompt, or domain-lens defect across projects;
   - **project:** routing, verification, domain, or artifact policy specific to this repository;
   - **insufficient evidence:** plausible but not supported.
5. Prioritize correctness and escaped defects over token or elapsed-time optimization.
6. Present the smallest change likely to improve the measured outcome and define how to evaluate it.

Never upload or quote project content from the outcome store.
