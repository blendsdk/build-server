# Commit Modes (Reference)

How the exec-plan skill handles commits. SKILL.md links here. Read this before the first commit
decision.

**By default, the skill NEVER commits or pushes automatically.** The user should always have the
chance to review changes before they hit the repository. Files are always saved to disk
regardless of commit mode, so no work is ever lost — only the git operation is gated.

Commit using the `git-commit` skill (commit only) or the `git-commit` skill in push mode (commit + push), or a normal git commit.

---

## The three modes

| Mode | Flag | Behavior |
|------|------|----------|
| **Ask (default)** | *(no flag)* or `--ask-commit` | After each verified task, ask the user whether/how to commit. |
| **No-commit** | `--no-commit` | Never commit, never ask. Pure implementation. The user handles git. |
| **Auto-commit** | `--auto-commit` | Automatically commit + push via the `git-commit` skill in push mode after each verified task. No prompts. |

The commit step is only triggered when ALL of these are true:

1. ✅ The task/session is successfully complete.
2. ✅ All verification passes.
3. ✅ The execution plan shows the task at `[x]` (verified complete — the two-stage marks are in
   [execution-protocol.md](execution-protocol.md); a `[~]` task is never committed).

**Never commit** when verification is failing, a task is still `[~]` (implemented but not
verified), or the mode is `--no-commit`.

**Quality-loop interaction (profile-gated).** When the repo's quality profile activates the
post-phase quality step (see [execution-protocol.md](execution-protocol.md)), fixes accepted
from review findings are committed as **follow-up commits** under the same rules as task
commits. A 🔴 CRITICAL / 🟠 MAJOR finding pauses execution for the user's ruling in EVERY
mode — auto-commit automates the git operation, never the ruling.

---

## Ask-commit mode (default) — prompt protocol

After each task completes and verification passes, ask the user:

> "Task X.X.X complete, verification passing. How would you like to proceed?"

Offer these options:

1. **Commit and push** — commit + push via the `git-commit` skill in push mode, then continue to the next task.
2. **Commit only (no push)** — commit via the `git-commit` skill, then continue to the next task.
3. **Skip, continue to next task** — no commit; ask again after the next task.
4. **Skip all, commit at the end** — no commit, and **stop asking** for the rest of the plan.
   At plan completion, present the end-of-plan commit prompt below.

If the user picks option 4, remember the preference and don't prompt again until the plan is done.

### End-of-plan commit reminder (ask mode)

When all tasks are complete and there are uncommitted changes, ask:

> "All tasks complete. You have uncommitted changes. How would you like to proceed?"

1. **Commit and push** — commit + push all changes via the `git-commit` skill in push mode.
2. **Commit only (no push)** — commit all changes via the `git-commit` skill.
3. **Don't commit** — leave changes uncommitted; the user handles git manually.

---

## No-commit mode

When `--no-commit` is specified:

- ✅ Implement tasks, run verification, update the execution plan — everything as normal.
- ✅ No git operations whatsoever (no staging, commits, or pushes).
- ✅ No commit prompts.
- ✅ Session summaries note `Commit mode: no-commit — no commits made`.
- ✅ At plan completion, one informational note: "Plan complete. Commit mode was no-commit —
  changes are uncommitted."

---

## Auto-commit mode

When `--auto-commit` is specified:

- ✅ After each verified task, automatically commit + push via the `git-commit` skill in push mode.
- ✅ No prompts — fully automated. **Exception:** a quality-gate pause (🔴/🟠 finding from the
  post-phase quality step) still stops for the user's ruling; auto-commit resumes after it.
- ✅ Follow the commit message format below.
- ✅ End-of-plan: changes are already committed per-task — no additional commit action needed.

---

## Commit message format

When committing (ask mode approved, or auto-commit), use this message format. The Conventional
Commits **type comes from the task's nature** — `feat` for new capability, `fix` for a bugfix,
`test` for test-only tasks, `docs` for documentation, `refactor`/`chore` for restructuring and
plumbing — never a hardcoded `feat` for everything:

```
[type]([scope]): [task description]

- [Specific change 1]
- [Specific change 2]
- Verification: passing

Ref: plans/[feature-name]/99-execution-plan.md
Task: [X.X.X]
```

the `git-commit` skill handles staging, the message file, and the commit/push for you. If you
commit with a plain `git commit` instead, write the message above to a file and pass it with
`-F` rather than cramming it into `-m`.
