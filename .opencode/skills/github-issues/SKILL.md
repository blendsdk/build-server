---
name: github-issues
description: Inspect a repository's GitHub issues as an adaptive table using its own labels, issue types, project fields, dependencies, priorities, and effort scheme; or close/reopen explicitly named issues with guarded native reasons. Use for GitHub issue overview, issue triage, dependencies, close issue, reopen issue, duplicate issue, or CodeOps backlog review. Read operations may be implicit; mutations require explicit user intent.
---

# GitHub issue operations

Use the installed `gh` CLI. Run `gh auth status` first and resolve the target repository from an explicit repository argument or `gh repo view`.

## Overview mode — read only

1. Discover the repository's labels and available issue/project metadata. Never impose a universal label vocabulary.
2. Fetch issues once with requested native filters: state, label, assignee, author, milestone, search, and limit.
3. Resolve type, priority, and effort using native fields first, then the repository's own label families.
4. Resolve open dependencies using native relations when available and conventional body markers as a documented fallback.
5. Apply semantic filters only after explaining mappings such as `high → P1` in the detected scheme.
6. Render `# · Title · Type · Priority · Effort · Deps · Assignee`. Do not truncate titles and disclose result limits or degraded metadata.

All user strings remain quoted command arguments. Never use `eval` or construct a shell command from issue content.

## Close/reopen mode — explicit mutation only

Validate the complete batch before mutation:

- issue identifiers must be numeric after stripping `#`;
- `completed`, `not-planned`, `duplicate`, and `reopen` modes are mutually consistent;
- a duplicate target cannot be among issues being closed; and
- the repository and requested comment are unambiguous.

For each issue:

1. Fetch and echo its title, current state, and intended action.
2. Skip already-satisfied state.
3. Before closing, list open dependents. If any exist, pause for explicit confirmation.
4. Use native `gh issue close` or `gh issue reopen`. When native duplicate reasons are unavailable, comment `Duplicate of #N` and close as not planned.
5. Continue past nonexistent individual issues but record every outcome.

Return a per-issue summary. Never create, edit, label, close, reopen, or comment unless the user's request explicitly authorizes that mutation.
