---
name: git-commit
description: Safely verify, stage, and commit repository changes with a detailed Conventional Commit message, optionally rebasing and pushing when the user explicitly requests push. Use for commit my changes, git commit, commit and push, or prepare a CodeOps checkpoint. Inspects untracked files and secrets, never bypasses hooks, never force-pushes, and stops on verification or rebase failure.
---

# Guarded Git commit

## Authority

A request to commit authorizes a local commit only. Push only when the user explicitly asks to push or has already granted continuing push authority for this repository. Never amend published history, force-push, reset, or bypass hooks without separate explicit authorization.

## Protocol

1. Resolve the repository root and inspect `git status --short`, staged/unstaged diffs, and recent commit style.
2. If clean, report `nothing to commit` and stop.
3. Inspect every untracked file. Stop and ask before staging likely secrets, credentials, build output, large binaries, or unrelated scratch files.
4. Resolve the authoritative verification command from `AGENTS.md`, CodeOps plan Verify lines, or project manifests. Run it with output captured to a temporary log. On failure, report the failure tail and do not stage or commit.
5. Stage deliberately by explicit paths or coherent groups. Avoid `git add .` when the working directory may be a monorepo subtree or unrelated changes exist.
6. Review `git diff --cached --check`, the staged stat, and the staged diff. Ensure the commit contains one coherent purpose and preserves unrelated user changes.
7. Write a Conventional Commit message to a temporary file and commit with `git commit -F`. Never use an inline multiline message.
8. If a commit hook modifies files, inspect and restage only relevant changes, then retry once. Never use `--no-verify` automatically.
9. For push mode, fetch/rebase only when appropriate for the branch policy. Stop on conflicts; never resolve ambiguous conflicts automatically. Push normally, never with force.
10. Report the resulting commit, verification, and push state.

## Message shape

```text
type(scope): imperative summary

- concrete behavior or artifact changed
- important invariant or compatibility note
- verification performed
```

Use `feat`, `fix`, `refactor`, `test`, `docs`, or `chore` unless repository guidance defines another convention.
