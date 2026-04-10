# YOLO v2 Loop Orchestrator

## What This Is

You are the orchestrator — the Claude Code session coordinating the adaptive loop.
You call yolo-cli scripts for deterministic work and spawn agents via the Task tool for creative work.

**Invariant:** yolo-cli enforces correctness (commit prefixes, plan validation, reconciliation).
You handle routing, context passing, and user interaction. Never duplicate what the CLI does.

## Prerequisites

- `.planning/features/` directory exists — create if missing: `mkdir -p .planning/features/done`
- yolo-cli scripts at `scripts/yolo-cli/` (commit.sh, reconcile.sh, run-tests.sh, validate-plan.sh)
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
lint_commands:
  - {discovered lint command, e.g. "npm run lint"}
test_commands:
  - {discovered test command, e.g. "npm test"}
---
```

4. Create worktree: `git worktree add {worktree} -b {branch}`
5. Confirm to user: "Created feature `{slug}` with worktree at `{worktree}`."

### Step 2: Think (Phase 2 stub)

Phase 1 behavior:
1. Read relevant files in the codebase to understand patterns and architecture
2. Confirm with user: "I'll {description}. The codebase uses {patterns}. Correct?"
3. On confirmation, write `## Context` and `## Criteria` sections to `{feature_file}`

```markdown
## Context
{Approach rationale, relevant patterns found, key files}

## Criteria
- {Success criterion 1}
- {Success criterion 2}
```

Phase 2: full think agent spawned via Task tool (not yet implemented).

### Step 3: Plan (Phase 2 stub)

Phase 1 behavior:
1. User provides plan OR orchestrator writes plan based on discussion
2. Write `## Plan` section to `{feature_file}` using this format:

```markdown
## Plan
- [ ] **Task 1: {title}** — {20+ word description}
  - files: {file1}, {file2}
  - test: {test file and what it tests} OR none ({justification})
  - depends: none
- [ ] **Task 2: {title}** — {description}
  - files: {file3}
  - test: {test file}
  - depends: task-1
```

3. Validate: `{cli}/validate-plan.sh {feature_file}`
4. If validation fails: read errors, fix the plan, retry validation
5. Confirm with user: "Plan has {N} tasks. Ready to execute?"

Phase 2: full plan agent spawned via Task tool (not yet implemented).

### Step 4: Do

Parse tasks from `## Plan` section of `{feature_file}`. Execute in dependency order.

**For each task N:**

1. Read task description, files, test_spec, dependencies from `## Plan`
2. Build predecessor context: if task depends on task-M, gather task-M's `files_changed` and `commit_message` from its output
3. Spawn execute agent via Task tool:
   - **prompt:** contents of `.claude/yolo/v2/agents/execute.md`
   - **input fields:**
     - `working_directory`: `{worktree}`
     - `task`: `{id, title, description, files, test_spec, depends_on}`
     - `predecessor_output`: (if applicable) `{files_changed, commit_message}` from dependency
     - `lint_commands`: from feature file frontmatter
     - `test_commands`: from feature file frontmatter
4. Parse agent's output YAML (status, files_changed, commit_message, issue)
5. **If `status: major_issue`:**
   - Show the issue to user
   - User picks: (a) re-plan — go to Step 3, (b) skip task — continue, (c) manual fix — pause for user
6. **If `status: completed`:**
   - Commit: `{cli}/commit.sh task {N} "{commit_message}" --repo {worktree}`
   - Reconcile: `{cli}/reconcile.sh {feature_file} {branch} --fix --repo {worktree}`
7. Store task output (files_changed, commit_message) for use as predecessor context

**After all tasks complete:** proceed to Step 5.

### Step 5: Check

1. Run tests: `{cli}/run-tests.sh {feature_file} --workdir {worktree}`
2. Capture full output and exit code
3. Collect changed files: `git diff --name-only main...{branch}` (in worktree)
4. Read criteria from `## Criteria` section of `{feature_file}`
5. Spawn check agent via Task tool:
   - **prompt:** contents of `.claude/yolo/v2/agents/check.md`
   - **input fields:**
     - `working_directory`: `{worktree}`
     - `criteria`: list of criteria strings from feature file
     - `test_output`: full captured test/lint output
     - `test_exit_code`: exit code from run-tests
     - `changed_files`: list of changed files
6. Parse agent's output YAML (passed, results, issues)
7. Write `## Verification` section to `{feature_file}` from check output
8. **If `passed: true`:** proceed to Step 6
9. **If `passed: false`:**
   - Show failed criteria and issues to user
   - User picks:
     - (a) fix — write a fix task, append to `## Plan`, return to Step 4 (Do) for that task only
     - (b) re-plan — go to Step 3 with current progress preserved
     - (c) accept partial — proceed to Step 6 with noted gaps

### Step 6: Ship

1. Final reconcile: `{cli}/reconcile.sh {feature_file} {branch} --fix --repo {worktree}`
2. Show summary to user:
   - Files changed (from `git diff --stat main...{branch}`)
   - Test results (pass/fail counts)
   - Criteria status (from `## Verification`)
3. User picks merge strategy:
   - **(a) Squash merge:** `git checkout main && git merge --squash {branch} && git commit`
   - **(b) Merge commit:** `git checkout main && git merge --no-ff {branch}`
   - **(c) Create PR:** `gh pr create --head {branch} --title "{goal}" --body "{summary}"`
   - **(d) Keep branch:** leave as-is for manual handling
4. Move feature file: `mv {feature_file} .planning/features/done/`
5. Remove worktree (unless option d): `git worktree remove {worktree}`
6. Confirm: "Feature `{slug}` shipped."

---

## Resuming a Feature

When user says "resume {name}" or `/yolo:start` detects an existing feature file:

1. Read `{feature_file}` — extract goal, branch, worktree path
2. Verify worktree exists; recreate if missing: `git worktree add {worktree} {branch}`
3. Reconcile: `{cli}/reconcile.sh {feature_file} {branch} --fix --repo {worktree}`
4. Derive current step from reconcile output:
   - No `## Context` or `## Criteria` → resume at Step 2 (Think)
   - No `## Plan` → resume at Step 3 (Plan)
   - Unchecked tasks in `## Plan` → resume at Step 4 (Do)
   - All tasks checked, no `## Verification` → resume at Step 5 (Check)
   - `## Verification` exists with `passed: true` → resume at Step 6 (Ship)
5. Show status to user: "Feature `{slug}` — resuming at {step}. {N}/{M} tasks done."
6. Jump to the appropriate step

---

## Natural Language Routing

| User says | Action |
|-----------|--------|
| "re-plan this" / "start over" | Reconcile, show completed tasks, go to Step 3 |
| "check this" / "verify" | Go to Step 5 (Check) |
| "ship it" / "merge" | Go to Step 6 (Ship) |
| "park this" / "stop" | `{cli}/commit.sh wip --repo {worktree}`, switch to main |
| "skip this task" | Mark current task skipped, continue to next |
| "full check" | Force full check mode in Step 5 |
| "status" | Run reconcile, show current step + task progress |

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
