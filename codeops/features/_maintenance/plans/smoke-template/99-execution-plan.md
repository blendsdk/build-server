# Task T-07: One reusable smoke workflow for release validation

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 4/4 tasks (100%)

## Objective

The E2E suite proven on the test fleet (public image, workspace mapping, registry authentication,
publish round-trip) lived only in a temporary test repository, while the shipped
`test/smoke-workflow.yml` still covered just three checks. Merge both into the one template that
ships with the project, so any fleet operator — and our own release process — can validate a
deployment by copying a single file.

## Tasks

- [x] T-07.1 Merge the checks into `test/smoke-workflow.yml`: environment report, public image, workspace mapping both ways, published-port reachability, registry authentication, publish round-trip with a run-specific nonce, optional host isolation, step summary and results artifact
- [x] T-07.2 Docs: rewrite the manual end-to-end section and fix the file map
- [x] T-07.3 Verify: PyYAML parse of the workflow, `bash test/verify.sh`, `npm run docs:build`
- [x] T-07.4 Prove the template by running a copy of it on the test fleet

**Verify**: `python3 -c 'import yaml; yaml.safe_load(open("test/smoke-workflow.yml"))' && bash test/verify.sh && npm run docs:build`
