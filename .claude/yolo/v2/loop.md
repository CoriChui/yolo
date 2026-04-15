# YOLO v2 Loop Orchestrator

## What This Is

You are the orchestrator — the Claude Code session coordinating the adaptive loop.
You call yolo-cli scripts for deterministic work and spawn agents via the Task tool for creative work.

**Invariant:** yolo-cli enforces correctness (commit prefixes, plan validation, reconciliation).
You handle routing, context passing, and user interaction. Never duplicate what the CLI does.

## Prerequisites

- `.planning/features/` directory exists — create if missing: `mkdir -p .planning/features/done .planning/decisions .planning/debug-sessions`
- yolo-cli scripts at `scripts/yolo-cli/` (commit.sh, reconcile.sh, run-tests.sh, validate-plan.sh, verify-commit.sh)
- Agent prompts at `.claude/yolo/v2/agents/` (execute.md, check.md)

## Variables

Throughout this document, these variables are used:

| Variable | Value |
|----------|-------|
| `{slug}` | Slugified feature description (lowercase, hyphens, max 50 chars) |
| `{feature_file}` | `.planning/features/{slug}.md` |
| `{worktree}` | `../.yolo-worktrees/{slug}` |
| `{branch}` | `feature/{slug}` |
| `{cli}` | `bash scripts/yolo-cli` |
| `{N}` | Numeric task index from the plan (e.g., 1, 2, 3) — the integer, not the `task-N` string |

---

## Starting a Feature (`/yolo:start "description"`)

### Step 1: Create Feature File

1. Slugify the description: lowercase, replace spaces/special chars with hyphens, truncate to 50 chars
2. Discover lint/test commands from project config (package.json scripts, Makefile targets, etc.)
3. Create `{feature_file}` with this template:

```yaml
---
goal: "{description}"
branch: feature/{slug}
worktree: ../.yolo-worktrees/{slug}
created: {ISO date}
lint_commands: ["{discovered lint command, e.g. npm run lint}"]
test_commands: ["{discovered test command, e.g. npm test}"]
---
```

4. Create worktree: `git worktree add {worktree} -b {branch}`
5. Confirm to user: "Created feature `{slug}` with worktree at `{worktree}`."

### Step 2: Think (Phase 2 stub)

Phase 1 behavior (if `--just-do-it` flag: skip to Step 3 after writing minimal criteria — "Feature works as described in the goal, all tests pass"):
1. If `--just-do-it`: write minimal `## Criteria` section to `{feature_file}` (see below), then skip to Step 3
2. Read relevant files in the codebase to understand patterns and architecture
3. Confirm with user: "I'll {description}. The codebase uses {patterns}. Correct?"
4. On confirmation, write `## Context` and `## Criteria` sections to `{feature_file}`

```markdown
## Context
{Approach rationale, relevant patterns found, key files}

## Criteria
- {Success criterion 1}
- {Success criterion 2}
```

For `--just-do-it`, write this minimal Criteria section:
```markdown
## Criteria
- Feature works as described in the goal
- All tests pass
```

Phase 2: full think agent spawned via Task tool (not yet implemented).

### Step 3: Plan (Phase 2 stub)

Phase 1 behavior:
1. User provides plan OR orchestrator writes plan based on discussion
2. Write `## Plan` section to `{feature_file}` using this format:

```markdown
## Plan
1. [ ] Task 1: {title} — {20+ word description}
  - files: {file1}, {file2}
  - test: {test file and what it tests} OR none ({justification})
  - depends: none
2. [ ] Task 2: {title} — {description}
  - files: {file3}
  - test: {test file}
  - depends: task-1
```

3. Validate: `{cli}/validate-plan.sh {feature_file}`
   - **Quality gates enforced by validate-plan.sh:** Each task description must be >=20 words. Min 2 tasks, max 12 tasks. >=50% of tasks must have `test:` annotations (not `test:none`). No directory paths in `files:` lists. No empty `test:` annotations.
4. If validation fails: read errors, fix the plan, retry validation
5. Confirm with user: "Plan has {N} tasks. Ready to execute?"

Phase 2: full plan agent spawned via Task tool (not yet implemented).

### Step 4: Do

Parse tasks from `## Plan` section of `{feature_file}`. Execute in dependency order.

**For each task N:**

1. Read task description, files, test_spec, dependencies from `## Plan`
2. Build predecessor context: if task depends on task-M, gather task-M's `files_changed` and `commit_message` from its output
3. **Pre-execute snapshot:** Record HEAD before spawning: `pre_exec_head=$(git -C {worktree} rev-parse HEAD)`
4. Spawn execute agent via Task tool:
   - **prompt:** contents of `.claude/yolo/v2/agents/execute.md`
   - **input fields:**
     - `working_directory`: `{worktree}`
     - `task`: `{id, title, description, files, test_spec, depends_on}`
     - `predecessor_output`: (if applicable) `{files_changed, commit_message}` from dependency
     - `lint_commands`: from feature file frontmatter
     - `test_commands`: from feature file frontmatter
5. **Post-execute mutation guard:** Verify `git -C {worktree} rev-parse HEAD` equals `$pre_exec_head` (agent must not commit directly). If HEAD changed, abort and report: "Execute agent made unauthorized commits."
6. Parse agent's output YAML (status, files_changed, commit_message, issue)
7. **If `status: major_issue`:**
   - Show the issue to user
   - User picks: (a) re-plan — go to Step 3, (b) skip task — continue, (c) manual fix — pause for user
8. **If `status: completed`:**
   - **Per-task test verification:** If the task's `test_spec` is not `none`, run the specific test command from the `test_spec` field directly in the worktree (e.g., `cd {worktree} && npx jest path/to/test.ts` or `cd {worktree} && pytest tests/test_feature.py`). Do NOT use `run-tests.sh` here — that runs the full suite. If the test fails, reject the completion — re-assign the task to the execute agent with the test failure output appended to the prompt, and do not proceed to commit.
   - Commit: `{cli}/commit.sh task {N} "{commit_message}" --repo {worktree} --stage`
   - **Transform `files_changed`:** Extract `path` values from the agent's `files_changed` YAML list and join with commas (e.g., `src/a.ts,src/b.ts`) before passing to verify-commit.sh. Example: if the agent outputs `files_changed:\n  - src/app.ts\n  - src/utils.ts\n  - tests/app.test.ts`, transform to `src/app.ts,src/utils.ts,tests/app.test.ts`.
   - Verify: `{cli}/verify-commit.sh task-{N} "{files_changed}" --repo {worktree}`
     - If verify fails with test integrity warnings (test count decrease, skip markers): **rollback the commit** with `git -C {worktree} reset HEAD~1`, then show the issue and ask the user to approve with `--allow-test-reduction` or fix the code. If approved, re-commit with `{cli}/commit.sh task {N} "{commit_message}" --repo {worktree} --stage --allow-test-reduction` and re-verify with `{cli}/verify-commit.sh task-{N} "{files_changed}" --repo {worktree} --allow-test-reduction`.
     - If verify fails with file mismatch warnings only: show warnings to user but continue (advisory in Phase 1)
   - Reconcile: `{cli}/reconcile.sh {feature_file} {branch} --fix --repo {worktree}`
9. Store task output (files_changed, commit_message) for use as predecessor context
10. **Capture test output for fast-check:** After the final task completes, store the last task's test output and exit code in variables `last_test_output` and `last_test_exit_code` for potential reuse in Step 5 fast-check mode.
11. **Iteration tracking:** if the same task fails 3 consecutive times (agent returns `major_issue` or tests fail repeatedly), stop and escalate to the user instead of retrying

**After all tasks complete:** proceed to Step 5.

### Step 5: Check

**Mode selection:** If ALL tasks passed TDD (no `major_issue`, no `test:none` tasks, and no pre-commit hook failures during Do step), use fast check (pass existing test output to check agent — no re-run needed, agent validates against criteria only). Otherwise, use full check. Announce the mode: "Running {fast|full} check."

1. **If full check mode:** Run tests: `{cli}/run-tests.sh {feature_file} --repo {worktree}`. Capture full output and exit code.
   **If fast check mode:** Reuse test output from the last Do step task. Skip re-running tests.
2. Collect changed files: `git diff --name-only main...{branch}` (in worktree)
3. Read criteria from `## Criteria` section of `{feature_file}`
4. **Pre-check snapshot:** Record HEAD before spawning: `pre_check_head=$(git -C {worktree} rev-parse HEAD)`
5. Spawn check agent via Task tool:
   - **prompt:** contents of `.claude/yolo/v2/agents/check.md`
   - **input fields:**
     - `working_directory`: `{worktree}`
     - `criteria`: list of criteria strings from feature file
     - `test_output`: full captured test/lint output
     - `test_exit_code`: exit code from run-tests
     - `changed_files`: list of changed files
6. Parse agent's output YAML (passed, results, issues)
7. **Post-check mutation guard:** After the agent returns, run ALL of these checks:
     - `git -C {worktree} diff --quiet` (no unstaged changes to tracked files)
     - `git -C {worktree} diff --cached --quiet` (no staged changes)
     - `git -C {worktree} rev-parse HEAD` equals `$pre_check_head` (no new commits)
     - `test -z "$(git -C {worktree} ls-files --others --exclude-standard)"` (no new untracked files)
     If any check fails, abort and report the violation.
8. Write `## Verification` section to `{feature_file}` from check output
9. **If `passed: true`:** proceed to Step 6
10. **If `passed: false`:**
   - Show failed criteria and issues to user
   - User picks:
     - (a) fix — write a fix task, append to `## Plan`, return to Step 4 (Do) for that task only
     - (b) re-plan — go to Step 3 with current progress preserved
     - (c) accept partial — proceed to Step 6 with noted gaps

### Step 6: Ship

1. **Pre-ship gate:** Read `## Verification` section from `{feature_file}`. If it does not contain `passed: true`, warn the user: "Verification hasn't passed. Ship anyway?" Require explicit confirmation before proceeding.
2. Final reconcile: `{cli}/reconcile.sh {feature_file} {branch} --fix --repo {worktree}`
3. Show summary to user:
   - Files changed (from `git diff --stat main...{branch}`)
   - Test results (pass/fail counts)
   - Criteria status (from `## Verification`)
4. User picks merge strategy:
   - **(a) Squash merge:** Safety check: `git -C {worktree} diff --quiet && git -C {worktree} diff --cached --quiet` (abort if uncommitted changes). Then: verify the main repo working directory is clean: `git diff --quiet && git diff --cached --quiet` (without -C, on the main repo). Abort ship if uncommitted changes exist. Then: `git checkout main && git merge --squash {branch}`. **If `git merge --squash` fails (exit non-zero), run `git merge --abort` to restore main to a clean state, then inform the user about conflicting files.** On success: `{cli}/commit.sh squash "{goal}" --repo . --stage`
   - **(b) Merge commit:** `git checkout main && git merge --no-ff {branch}`
   - **(c) Create PR:** `gh pr create --head {branch} --title "{goal}" --body "{summary}"`
   - **(d) Keep branch:** leave as-is for manual handling
5. Move feature file: `mv {feature_file} .planning/features/done/`
6. Remove worktree (unless option d): `git worktree remove {worktree}`
7. Confirm: "Feature `{slug}` shipped."

---

## Resuming a Feature

When user says "resume {name}" or `/yolo:start` detects an existing feature file:

1. Read `{feature_file}` — extract goal, branch, worktree path
2. Verify worktree exists; recreate if missing: `git worktree add {worktree} {branch}`
3. **Check for [wip] commit as HEAD:** `git -C {worktree} log -1 --oneline | grep -F '[wip]'`. If found: `git -C {worktree} reset HEAD~1` to restore uncommitted state.
4. Reconcile: `{cli}/reconcile.sh {feature_file} {branch} --fix --repo {worktree}`
5. Parse the "Current Step" line from reconcile output to derive resume point:
   - `think` → resume at Step 2 (Think)
   - `plan` → resume at Step 3 (Plan) — plan already exists, validate it with `{cli}/validate-plan.sh {feature_file}`. If valid, skip to Step 4 (Do). If invalid, show errors and let user fix the plan.
   - `do` → resume at Step 4 (Do) for remaining uncompleted tasks
   - `do-fix` → resume at Step 4 (Do). The `do-fix` step means a previous verification failed — pass this context when dispatching: "Previous verification failed — execute agent should fix the failing check criteria before proceeding, not re-execute already-completed tasks."
   - `check` → resume at Step 5 (Check)
   - `ship` → resume at Step 6 (Ship)
   - `done` → inform user feature is already complete
6. Show status to user: "Feature `{slug}` — resuming at {step}. {N}/{M} tasks done."
7. Jump to the appropriate step

---

## Natural Language Routing

| User says | Action |
|-----------|--------|
| "re-plan this" / "start over" | Reconcile, show completed tasks with keep/revert options. For each completed task: ask user to keep (still valid) or revert. Batch-confirm reverts, execute `git -C {worktree} revert <hash>` for each, then go to Step 3. |
| "check this" / "verify" | Go to Step 5 (Check) |
| "ship it" / "merge" | Go to Step 6 (Ship) |
| "park this" / "stop" | Check `git status` in worktree; if uncommitted changes: `{cli}/commit.sh wip --repo {worktree} --stage`, then switch to main |
| "skip this task" | Mark current task skipped, continue to next |
| "full check" | Force full check mode in Step 5 |
| "status" | Run reconcile, show current step + task progress |

> **Phase 1 note:** "park" and "resume" are handled inline by the orchestrator above. Phase 3 will replace these with dedicated CLI scripts (`park.sh`, `resume.sh`) for deterministic enforcement.

---

## Context Compaction

After each step completes and its output is written to `{feature_file}`:
1. Summarize what happened in one line (e.g., "Step 4 complete: 5/5 tasks committed")
2. The feature file holds the durable output — do not retain step working data in memory
3. On resume or step transition, re-read `{feature_file}` for current state

---

## Error Handling

| Error | Recovery |
|-------|----------|
| Worktree missing | Recreate: `git worktree add {worktree} {branch}` |
| Branch already exists | Reuse it; reconcile to derive state |
| Feature file missing | If branch exists, reconstruct from git log; else start fresh |
| Agent timeout / crash | Retry once; if second failure, ask user |
| yolo-cli script fails | Show stderr to user, do not retry silently |
| Merge conflict | Show conflict files, ask user to resolve manually |

---

## Deferred to Phase 2+

- **Direct commit path:** Small changes (<=3 files AND <=20 lines) should skip worktree and plan. Not yet implemented.
- **Session locking:** `locked_by: session-{id}` in feature file frontmatter. Not yet implemented.
- **Full think agent:** Currently a manual stub. Phase 2 will spawn a dedicated think agent.
- **Full plan agent:** Currently a manual stub. Phase 2 will spawn a dedicated plan agent.
