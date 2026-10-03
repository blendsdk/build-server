# Execution Protocol (Reference)

Detailed execution protocol for the exec-plan skill. SKILL.md links here. Read this for the
load-the-plan edge cases, specification-first ordering, the real-time update mandate, the
session summary template, and error handling.

---

## Step 1: Load the Plan

1. Read `plans/[feature-name]/99-execution-plan.md`.
2. Find incomplete tasks: **both** unchecked `[ ]` items **and** implemented-but-unverified `[~]`
   items (see the two-stage marks below).
3. Read supporting technical specs in `plans/[feature-name]/`.
4. Determine the starting point: a `[~]` task is resumed FIRST — re-read its partial-completion
   note, re-run verification, then promote it to `[x]` or continue fixing. Otherwise start at the
   first `[ ]` task.
5. **Resume spot-check:** before building on prior work, confirm the most recent `[x]` task's
   named files actually exist (branch switches and reverts happen). If they don't, flag the drift
   to the user before continuing.

If the execution plan can't be loaded cleanly, **STOP** and handle as follows:

| Condition | Action |
|-----------|--------|
| `plans/` directory doesn't exist | STOP — suggest using the make-plan skill first |
| `plans/[feature-name]/` doesn't exist | STOP — suggest the make-plan skill, or check for typos in the feature name |
| `plans/[feature-name]/` exists but `99-execution-plan.md` is missing | STOP — plan is incomplete; suggest recreating it with the make-plan skill |
| `99-execution-plan.md` exists but has no tasks | STOP — plan is empty; suggest recreating it with the make-plan skill |
| All tasks already marked `[x]` | Report "All tasks are already complete." Suggest re-analyzing the project via the `analyze-project` skill |
| No verify command resolvable — the plan's Verify lines are empty/generic AND neither the project's AGENTS.md nor its manifests name one | STOP — ask the user to name the verify command, write it into the plan's Verify lines, then proceed. **Never invent a command** (a plausible-looking `npm test` that was never configured verifies nothing) |

### Artifact schema check

Read `00-index.md` and `99-execution-plan.md`. A current plan declares one or more RDs on its
`> **Implements**:` line and uses `[ ]`, `[~]`, `[x]`, and `[!]` as its complete task-state
vocabulary. A legacy `CodeOps Skills Version` stamp or no schema stamp triggers a read-only
upgrade assessment. Do not execute a legacy plan merely because its task checkbox shape can be
parsed; the user must approve migration or explicitly accept the recorded compatibility risk.

Before implementation, directly check required documents, closed material ambiguities,
specification-first ordering, and unresolved critical/major findings. Before promoting a task to
`[x]`, run its verification. A task update never advances siblings.

Suggestion only — the user may proceed without upgrading.

---

## Step 2: Execute Tasks

### Phase start

Before a phase's first task (and before a T-NN mini-plan's first task), snapshot the complete
non-ignored worktree—including staged, unstaged, and untracked files—into a temporary Git tree,
without changing the real index:

```bash
python3 "${CODEOPS_PLUGIN_ROOT}/scripts/codeops_worktree_snapshot.py" snapshot --root .
```

Write the returned SHA as `> **Phase baseline tree**: <sha>` in the phase header (for a mini-plan,
its single header). This snapshot works in every commit mode and prevents pre-phase dirty work from
entering the review. Also record the phase's expected modification set from its task target paths
and deliverables. A changed path outside that set is scope drift: attribute it to the phase and
expand the recorded set, or identify it as unrelated work and exclude it from the review packet.
Never silently review or commit unrelated user changes as phase work.
Record the invocation's scope mode (`strict` by default or `explore`) beside the expected
modification set. Every executor and reviewer packet receives that mode plus the confirmed product
scope baseline; missing mode context fails closed to strict scope.
When opt-in outcome metrics are enabled, record only a content-free execution-stage event through
`codeops_outcomes.py`; metrics never gate execution.

**Spec-author dispatch (profile-gated).** Tasks marked `[spec-author]` dispatch the
spec-test-author agent — packet per `_shared/quality-profile.md` — BEFORE any implementation
task of that phase, and the red phase is confirmed from its report. A spec test that cannot be
written from the packet is a blocker for the user, never guessed around. Without an active
profile the session writes the spec tests itself; specification-first ordering is identical
either way.

Task completion is **two-stage**: `[~]` = implemented (crash-safe progress mark), `[x]` = verified
complete. For each task, in order:

1. Run the **minimum-sufficient checkpoint** before editing. Compare the intended work with the
   original goal, established project patterns, relevant approved complexity AR/PF/RV decisions,
   and the smallest viable implementation. If it triggers the Complexity Escalation Gate in
   `_shared/zero-ambiguity-gate.md`, mark the task `[!]`. For a T-NN mini-plan, preserve the current
   diff without marking it verified and switch to the full standalone-plan path before dispatching
   the challenger, presenting the packet, or accepting a decision; its
   `00-ambiguity-register.md` owns the decision. For a full plan, dispatch the required blind
   challenger, present the complete visible stop packet, and wait for explicit user approval.
   Auto-design, auto-commit, or a generic finding ruling cannot approve the larger option.
2. Implement the task following the technical specifications. **The code and doc comments you
   write must never reference the plan, requirements, `codeops/`, or any RD/AR/task ID** — those
   files are ephemeral; the shipped code must stand on its own (per the standards' Documentation
   ban). Restate any rationale you drew from the plan in plain language instead.
3. **🚨 Immediately update `99-execution-plan.md`** — mark the task `[~]` with a timestamp
   (`- [~] 1.1.1 … ⏳ (implemented: YYYY-MM-DD HH:MM)`, timestamp via `date '+%Y-%m-%d %H:%M'`)
   and update the Progress header. Do this before running verification or anything else — if the
   session crashes now, the implementation progress is preserved and the resume session knows the
   task still needs verification.
4. Run verification (your project's verify command — from the project's AGENTS.md, or detected
   project conventions), with output captured per the **Verify-output capture rule** below.
   - **PASS** → before promoting, run the **documentation-standard self-check** below on the files
     this task changed. Missing documentation and leaked plan references are invisible to
     build+test, so a green verify is NOT sufficient — the self-check is a hard part of the
     done-criterion. Only when it is clean,
     promote the mark to `[x]` with a completion timestamp
     (`- [x] 1.1.1 … ✅ (completed: YYYY-MM-DD HH:MM)`).
     Immediately derive and show the user the current task progress from the selected plan directory:

     ```bash
     python3 "${CODEOPS_PLUGIN_ROOT}/scripts/codeops_plan.py" --root . --plan "<selected-plan-directory>" --progress-bar
     ```

     Present the command's single `Progress: […] X/Y tasks (Z%)` line in the next commentary update.
     This read-only display is required after every `[x]` promotion; never estimate it or count
     `[~]` as complete.
   - **FAIL** → the mark STAYS `[~]`. Fix the implementation and re-verify; promote only on pass.
     A task is never `[x]` with a failing verify.

   **Documentation-standard self-check (NON-NEGOTIABLE, before every `[x]`).** Read the changed
   code as a junior developer and confirm:

   - every public, exported, or external-facing class, interface, method, function, property, type,
     and constant has a language-appropriate doc comment;
   - every non-trivial internal entity is documented;
   - applicable purpose, parameters, return value, thrown errors, side effects, and important
     invariants are explained;
   - complex logic, invariants, edge cases, and non-obvious decisions have calm comments that
     explain why without narrating obvious syntax;
   - public API has `@example` or the language equivalent wherever practical; and
   - genuinely trivial private code is not padded with comments that only restate its name or type.

   Use the project's documentation linter when one is configured. Lint cannot replace the semantic
   read. Missing required documentation blocks `[x]`.

   Then confirm the code and comments reference no ephemeral CodeOps artifact. Grep the files this
   task changed:

   ```bash
   git diff --name-only | xargs grep -nEI \
     -e '\b(RD|AR|PA|PF|HR|GATE|AC|ST|ADR|DEF)-[0-9]+' \
     -e '\b(codeops|plans|requirements)/[[:alnum:]._/-]*' 2>/dev/null
   ```

   Any hit inside a comment or doc comment is a leak — rewrite it per the standard (keep the
   behavior it annotated, drop the citation; restate any plan rationale in plain language) before
   marking the task `[x]`. Hits inside real code strings/paths the program actually uses are fine.
5. Commit per the active commit mode (see [commit-modes.md](commit-modes.md)) — the commit gate
   keys off `[x]`, never `[~]`.
6. **Post-phase quality step (after each phase, profile-gated):** when the phase's last task has
   verified, run the quality step below before anything else starts.
7. **Techdocs check (after each phase):** if techdocs exist and the just-completed phase
   introduced architectural changes (new components, data entities, API endpoints, integrations,
   or infrastructure), perform an incremental techdocs update via the techdocs skill.
8. Continue until all tasks are complete. OpenCode auto-compacts context, so there is no
   manual context-threshold handling — just keep going.

### Post-phase quality step (profile-gated)

Runs after a phase's last task verifies — and after a T-NN mini-plan's work verifies, on the
whole-task diff. Activation rules, packets, supersession, and caps are defined in
`_shared/quality-profile.md`; this section owns the order of operations:

1. **Determine activation.** Strict defaults review every non-trivial phase. Adaptive mode may
   explicitly disable independent review; announce that choice. Trivial tasks are never reviewed.
   A docs-only diff → phase-reviewer only, and the auditor skip is logged — never silent.
2. **Dispatch in parallel:** the correctness reviewer plus every risk-selected auditor (security,
   financial integrity, concurrency, performance, semantics, or migration), each with the
   dispatch header on line 1 of its prompt and its packet
   Create the review diff with:

   ```bash
   python3 "${CODEOPS_PLUGIN_ROOT}/scripts/codeops_worktree_snapshot.py" diff \
     --root . --baseline <phase-baseline-tree>
   ```

   This includes committed, staged, unstaged, and newly created files while excluding changes that
   existed at phase start.
3. **Merge findings** (RV/SA/PE) and present them in severity-grouped batches (reuse the
   preflight skill's batch pacing). In normal mode, 🔴 CRITICAL / 🟠 MAJOR findings PAUSE
   execution for the user's ruling in ALL commit modes. With active auto-design, an eligible
   technical fix may be selected and recorded, but risk may never be waived and a critical/major
   finding may never be dismissed automatically; reserved decisions pause for the user. 🟡 MINOR
   findings are report-only.
   Before merging, apply `_shared/scope-expansion-control.md`: a necessary correction or blocking
   uncertainty remains a finding, while an optional remediation is omitted in strict scope or
   moved to a separate `SE-*` proposal in exploration mode. A finding ruling never chooses `Keep`.
   For escaped complexity, first dispatch the blind design challenger and then use the complete
   visible packet from `_shared/zero-ambiguity-gate.md`. Explicit approval of the named larger
   machinery resolves the finding without a code change. Choosing the smaller design, revision, or
   deferral stays blocked until the code changes and passes re-review.
   For a T-NN mini-plan, stop before presenting or accepting a complexity decision: mark the task
   `[!]`, preserve the diff without marking it verified, and switch to the full standalone-plan
   path. The new `00-ambiguity-register.md` owns the packet and decision. Resume only after that
   plan's gates pass.
4. **Record decisions durably** in the finding artifact after each ruling batch. When the user
   approves larger machinery, also append a `Technical (complexity escalation)` runtime AR with
   every approval-evidence field required by the shared gate; the RV finding references that AR.
5. **Accepted fixes:** implement → verify → follow-up commit per the commit mode. If any 🔴/🟠
   fix was applied, dispatch ONE re-review scoped to the fix diff — never a third pass. A fix
   the re-review still rejects is reported. Normal mode returns the ruling to the user; active
   auto-design may select one eligible technical correction, but cannot waive the finding.
6. **Record review evidence** in the plan or its review report, optionally record a content-free
   review outcome, then proceed to the next phase.

A dispatch that fails or dies mid-loop is reported — the phase completes UNreviewed only on the
user's explicit say-so.

### Outcome evidence (opt-in)

When `codeops/codeops.json` sets `metrics.enabled` to `true`, record only enumerated, content-free
outcomes through `"${CODEOPS_PLUGIN_ROOT}/scripts/codeops_outcomes.py" emit`. Useful events include
verification results, rework cycles, scope drift, invalidated assumptions, runtime ambiguities,
review completion, escaped findings, and recovery accuracy. Event recording always exits without
changing gate results. Never include prompts, paths, source content, finding prose, or user text.

### Verify-output capture (NON-NEGOTIABLE)

Never let a full verify run's output into the conversation. Every verification run — per-task,
red-phase, green-phase, session wrap-up — executes with output captured to a temp log:

```bash
<verify command> > "$VERIFY_LOG" 2>&1
```

(`$VERIFY_LOG` = a file in the session temp/scratchpad dir, e.g. `verify-<task-id>.log`.)

- **PASS** → surface ONE line: `VERIFY PASS (task N.N.N)`, plus the test count if it is
  extractable from the log tail at no extra cost.
- **FAIL** → surface the **last 50 lines** of the log + the log path, nothing more. Read further
  slices of the log file on demand while fixing — do not re-run verify just to "see the output".
- **Red-phase runs** (spec tests expected to fail) → surface only the failing spec-test
  names/count confirming the red state — never the full dump.

The full log always remains on disk for the session. If the log location is unwritable, fall
back to running verify plainly ONCE and note the fallback in the session summary. This rule is
about CONTEXT, not rigor: the verify command itself, its scope, and pass/fail gating are
unchanged — and the temp log is read-only evidence, never executed.

### Zero-Ambiguity During Execution

If you encounter any implementation detail, behavioral question, edge case, or design choice not
covered by the plan documents or `00-ambiguity-register.md`, first record it and mark affected
tasks `[!]` with `Blocked: <short reason>` until the owning artifact is resolved.

First determine whether the discovery is an ambiguity inside authorized scope, a necessary
correction, or an optional expansion. Optional expansions do not enter the ambiguity register:
they are silent in strict scope or use the Scope Expansion Register during exploration.

1. **STOP** — do not guess, infer, or apply "reasonable defaults".
2. **Classify authority.** With active auto-design, apply the shared auto-design policy: resolve
   and record an eligible technical decision; present a reserved decision to the user. In normal
   mode, present every material ambiguity to the user with options and trade-offs.
3. **Obtain authority.** Wait for the user's explicit decision when normal mode or reserved
   authority applies. An auto-design resolution must include the policy's complete provenance.
4. **Record** it in `00-ambiguity-register.md` with the next sequential AR number, tagged
   `(runtime)` in the Category column. Update the register header to note items added during
   execution.
5. **Only then** update affected plan artifacts, confirm direct entry checks still pass, and
   resume implementation using the authorized decision.

This applies to ALL ambiguities — architectural, behavioral, naming, formatting, UX, error
handling. Never fill gaps by guessing.

A runtime complexity escalation always uses reserved authority. Its required challenger and
visible stop packet come from `_shared/zero-ambiguity-gate.md`. Record an approved larger option as
`Technical (complexity escalation)`. If the user defers it, keep it out of executable work.

---

## Execution mode — inline first (routing-aware)

When `codeops/codeops.json` carries routing policy (see the setup-routing skill), route by PHASE,
not by task, and prefer inline unless isolation, independence, context control, or a capability
match materially improves the result:

1. **Inline for tightly coupled work.** Keep the primary agent responsible for decisions, durable
   state, plan/roadmap updates, and work whose tasks share substantial context.
2. **Dispatch bounded phases.** Use an executor role for a self-contained phase when a fresh
   context, different capability/effort, or isolation from the decision conversation is useful.
3. **Parallelize only independent work.** Read-heavy reconnaissance and independent reviews are
   preferred candidates. Parallel writes require disjoint ownership and an explicit merge plan.
4. **Select reviewers by risk.** Every non-trivial phase gets correctness review; add security,
   financial-integrity, concurrency, performance, semantics, or migration reviewers from tags.

**The phase packet.** When a phase IS dispatched, the parent composes the packet; the executor
receives nothing else and must not need anything else:

- the phase's task lines, Deliverables, and Verify lines verbatim from `99-execution-plan.md`;
- the relevant excerpts of the governing `03-XX` spec documents (the excerpts, not filenames);
- the applicable ST-cases from `07-testing-strategy.md`;
- the AR decisions that bear on the phase and any relevant approved complexity PF/RV decisions
  (quoted entries, not whole reports);
- the original goal and smallest viable design from `00-index.md`, or the session-derived legacy
  baseline when the plan predates that section;
- the scope mode (`strict` or `explore`) and confirmed product scope baseline; missing or invalid
  scope context fails closed to strict mode. Missing or invalid original-goal or smallest-design
  context blocks dispatch;
- the target file paths and the project's verify command.

Excerpting owned content into a packet is the intended retrieval mechanism, not restatement. The
quoted AR/ST/spec content is context for the executor's *understanding* — it must not surface as a
citation in shipped code (the executor carries the same doc-standard ban and self-check).

**Division of labor.** The PARENT — never the executor — updates `99-execution-plan.md`
(two-stage marks), the Progress header, and the roadmap. The executor implements task-by-task,
runs verify per the Verify-output capture rule, and reports per task. Mark `[~]` as the executor
reports each implementation; verify (or trust the executor's verify run and spot-check it);
promote to `[x]` on pass.

**Blocker path.** On ambiguity, missing packet context, or a failing SPEC test, the executor
stops and returns a blocker report. The parent then runs the zero-ambiguity loop above with the
applicable authority: normal mode or a reserved decision uses STOP → options → user decision →
AR `(runtime)` entry; active auto-design resolves and records an eligible technical decision under
the shared policy. The parent re-dispatches with the enriched packet. An executor never asks the
user directly, widens delegated authority, or guesses.

**Missing-executor guard.** If a named role is unavailable, spawn a generic subagent with the
complete packet or run the phase inline and report why. Dispatch is an optimization — the
protocol's guarantees hold either way.

---

## Specification-First Task Ordering (NON-NEGOTIABLE)

The ordering `spec tests → red phase → implement → green phase → impl tests → verify` is defined
ONCE in **[../../_shared/spec-first-ordering.md](../../_shared/spec-first-ordering.md)** — read it
before executing the first implementation task. Enforce it exactly as written there: never start
implementation before that feature's spec tests exist and have a recorded red phase, and apply the
immutable-oracle rule — a failing spec test means the implementation is wrong, never the test.

---

## Real-Time Execution Plan Update Mandate (ULTRA-CRITICAL)

`99-execution-plan.md` is the SINGLE SOURCE OF TRUTH for progress and the user's lifeline if a
session ends unexpectedly. Update it after completing EACH task. No exceptions.

### Update-first order (two-stage)

```
Implement task → 🚨 MARK [~] IN THE PLAN → verify → PASS: promote to [x] / FAIL: fix, stays [~] → commit → next task
```

NOT: batch-updating later, updating only at the end, or "maybe update and maybe forget". If the
agent crashes during verify or commit, the plan already reflects exactly how far the work got —
`[~]` says "implemented, verification not yet passed"; `[x]` says "verified complete".

### Update procedure

1. On implementation: change `[ ]` → `[~]` with an implemented-timestamp in the plan's task
   list — the **phase checkbox lists** (3.3.0 format) or the **Master Progress Checklist**
   (legacy format); on verify pass: promote `[~]` → `[x]` with a completion timestamp.
2. Update the Progress counter in the header (e.g., `3/12 tasks (25%)`) — only `[x]` tasks count
   as complete.
3. Update the Last Updated timestamp (obtain timestamps via `date '+%Y-%m-%d %H:%M'` — never
   invent them).

Task mark formats:

```markdown
- [~] 1.1.1 Task description ⏳ (implemented: YYYY-MM-DD HH:MM)
- [x] 1.1.1 Task description ✅ (completed: YYYY-MM-DD HH:MM)
```

### Native progress mirror (visibility aid)

After every `[x]` promotion, show the deterministic progress line required by the per-task loop.
Where the session also provides a plan or goal UI, mirror the current phase's tasks and update their
statuses alongside the Markdown marks. Both displays are convenience layers only —
**`99-execution-plan.md` remains the durable source of truth**. Skip silently when unavailable.

### Task-list format detection (dual-format)

After loading the plan, detect its task-list format — both formats execute identically otherwise:

- A `## 🚨 Master Progress Checklist` section present → **legacy format (≤3.2.0)**: the checklist
  remains the single source of truth. Maintain it exactly as before — if it is missing task
  entries, or the section is absent while phase sections carry task TABLES, reconstruct it from
  the phase/session/task details (`- [ ] X.X.X [desc]`, grouped by phase) before any task
  execution begins.
- No such section AND the phase sections carry task checkboxes → **3.3.0 format**: the phase
  checkbox lists are the single source of truth. Do NOT create a Master Progress Checklist.
- Neither found → STOP (empty plan — see the load table).

Never suggest an upgrade on format grounds (AR-5, plans/plan-token-efficiency).

### Hard gate

Before running verification you MUST have already marked the task `[~]` with a timestamp. Before
committing, proceeding to the next task, ending a session, or presenting a session summary, the
task's final state MUST be recorded truthfully — `[x]` (with timestamp) only if its verify passed,
otherwise still `[~]` — with the progress counter and Last Updated stamp current.

---

## Step 3: Session Wrap-Up

1. Complete the current task before stopping.
2. **🚨 First: update `99-execution-plan.md`** with ALL completed tasks (before anything else).
3. Run the verify command (output captured per the Verify-output capture rule).
4. Handle the commit per the active commit mode (see [commit-modes.md](commit-modes.md)).
5. Report the session summary (must include `Execution Plan Updated: ✅`).

### Session Summary Template

```markdown
## Session Complete

**Feature:** [feature-name]
**Execution Plan:** `plans/[feature-name]/99-execution-plan.md`

**Completed This Session:**
- [x] Phase X, Task X.X.X: [description]
- [x] Phase X, Task X.X.X: [description]

**Remaining Work:**
- [ ] Phase X, Task X.X.X: [description]
- [ ] Phase Y: [phase description]

**Execution Plan Updated:** ✅ `99-execution-plan.md` reflects all completed work
**Verification:** [Status — e.g., "All tests passing", "Build successful"]
**Commit Mode:** [ask-commit | no-commit | auto-commit]
**Commit:** [hash] / "Committed successfully" / "Uncommitted — user deferred" / "No-commit mode"

**To Continue:**
Run `/exec-plan [feature-name]` again in a new session.
```

---

## Error Handling During Execution

### If verification fails

1. The task's mark stays `[~]` (it was set at implementation time — never promote on a failing
   verify).
2. Fix the failing tests/build (for a failing SPEC test, fix the implementation — never the test).
3. Re-run verification until all checks pass.
4. Only then promote the mark to `[x]`.

**Convergence guard:** after three consecutive failures with the same failure signature (the same
failing tests, compiler errors, or command failure), stop retrying. Classify the blocker as one of:
implementation defect, stale/impossible plan, pre-existing repository failure, or environment/tool
failure. Present evidence and the viable next action to the user. A materially different failure
signature resets the counter; expected red-phase failures do not count.

### If implementation deviates from the plan

A deviation is by definition territory the plan doesn't cover — route it by materiality:

- **Material deviation** (different approach, different files, different behavior than the plan
  specifies): run the Zero-Ambiguity loop above — STOP, present the deviation with options in
  normal mode, or apply active auto-design to an eligible technical choice and escalate a reserved
  choice. Record the authorized resolution in `00-ambiguity-register.md` tagged `(runtime)` and
  update the task description. If it changes artifacts outside the selected plan, obtain approval
  for the exact expanded modification set before editing, then continue.
- **Mechanical correction** (typo'd path, renamed symbol, an import the plan forgot): note it in
  the execution plan and continue — no user round-trip needed.

When unsure which it is, treat it as material.

### If a session is interrupted mid-task

1. Save progress so far.
2. Ensure the task is marked `[~]` with a clear partial-completion note (what is done, what
   remains, what to verify).
3. Do NOT commit the half-done task (the commit gate keys off `[x]`).
4. Resume later by running `/exec-plan [feature-name]` again — Step 1 finds the `[~]` task,
   resumes it first, and re-verifies before promoting.
