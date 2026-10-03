---
name: analyze-project
description: Analyze the current repository and create or refresh concise CodeOps-aware AGENTS.md guidance using observed manifests, commands, structure, conventions, verification, and integration-branch facts. Use for analyze project, initialize project guidance, refresh AGENTS.md, or compact project instructions. Preserves hand-authored content and previews consequential rewrites.
---

# Analyze project guidance

`/init` can create a basic `AGENTS.md`; this skill adds CodeOps-specific, evidence-grounded guidance without replacing hand-authored policy.

## Protocol

1. Resolve the Git root, current/default branch, and nested `AGENTS.md` files.
2. Inspect manifests, build files, CI, test configuration, formatter/linter settings, source layout, package boundaries, and recent commit conventions.
3. Derive commands only from executable configuration or documented scripts. Never invent a plausible command.
4. Prepare a concise managed section between:

```text
<!-- CODEOPS-PROJECT:START -->
<!-- CODEOPS-PROJECT:END -->
```

5. Include project type, principal languages/frameworks, authoritative build/test/verify commands, high-level structure, generated-file warnings, and CodeOps artifact/config locations.
6. If the managed section exists, replace only its contents. Preserve all other text byte-for-byte.
7. On a non-integration branch, preview changes to repository-wide guidance and ask before writing unless repository policy explicitly permits branch-local updates.
8. In compact mode, remove duplication and stale generated detail from the managed section only. Flag suspected hand-authored bloat; never silently rewrite it.
9. Validate every recorded command or mark it explicitly unverified.

Keep `AGENTS.md` small. Operational routing belongs in `codeops/codeops.json` or `opencode.json`, not prose.
