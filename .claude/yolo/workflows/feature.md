# Feature Workflow
# Commands: /feature add, /feature start, /feature plan, /feature verify, /feature complete, /feature status

Read `.planning/state.yaml` before any operation. Validate it exists and is valid YAML — if missing, error: "Run `/yolo:init` first."
**Rule:** Every state.yaml or feature.yaml mutation must update `updated_at` to current ISO 8601 UTC timestamp.
**Rule:** Workflows are single-threaded — only one workflow operates on a feature at a time. No concurrent access guards are needed.

---

## /feature start <id> [--prompt "<text>"]

Full pipeline: research → plan → execute → verify-fix → verify → complete.

**Mandatory:** Every feature MUST create a git worktree, implement changes there, ensure all lint and test checks pass (including any pre-commit hooks), and commit changes. This project may have pre-commit hooks configured with linting and tests. All lint errors and test failures must be resolved before completing.

### Phase 1: Setup

1. **Resolve feature:** Find feature directory in focused release (`releases/{release}/features/{id}-*`). If no ID, start next pending feature.

2. **Check preconditions:**
   - If feature is `completed`: reject with error — terminal state cannot be restarted
   - No other feature currently in progress (unless resuming this one) — if `focus.feature` in state.yaml points to a different feature, read that feature's `feature.yaml` to get its actual status; if it is `researching`, `planning`, `in_progress`, or `verifying`, reject
   - If feature is already `researching`: re-validate `depends_on` (all must be `completed`), resume from Phase 2
   - If feature is already `planning`: re-validate `depends_on` (all must be `completed`), resume from Phase 2 (plan step)
   - If feature is already `in_progress`: re-validate `depends_on`, resume from Phase 3
   - If feature is already `verifying`: re-validate `depends_on` (all must be `completed`), resume from Phase 5
   - If feature is `pending`: all `depends_on` features must be `completed`

3. **Load feature.yaml:** Extract title, goal, success_criteria.

4. **Validate criteria:** At least 1 criterion, no empty strings, no duplicates. Warn on vague/untestable/too-broad criteria — let user accept or edit.

5. **Create worktree** (skip if already exists):
   ```bash
   REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
   WORKTREE_DIR="../.${REPO_NAME}-worktrees/${feature_id}"
   git worktree add "$WORKTREE_DIR" -b "feature/${feature_id}"
   ```

6. **Update feature.yaml:** Set `status: researching`, `started_at: {timestamp}`, `updated_at: {timestamp}`.
   **Update state.yaml:** Set `focus.feature`, `updated_at`, `session.last_action`, `session.resume`.

### Phase 2: Plan (research + plan agents)

Follow `/feature plan` process below. Skip if plan.md already exists — in that case:
1. Validate plan.md has parseable `### Task N:` sections and task count matches `feature.yaml` `tasks.total`. If mismatch: warn user. If `tasks.total` is 0, ask user to confirm using existing plan before updating `tasks.total` from plan.md task count — if rejected, delete plan.md and re-plan. **Invariant check:** If `status` is `pending` and plan.md exists, warn user: "Plan exists but feature is pending — this is inconsistent. Confirm to use existing plan, or delete plan.md and re-plan." If `plan.md` is missing but `tasks.total > 0`, warn user: "Feature has task count but no plan. Reset tasks.total to 0 before proceeding."
2. **Re-read feature.yaml** to confirm current status. Only `researching`, `planning`, or `in_progress` may transition here — if status is `completed`, reject with error. If status is `planning`, require user re-approval of the existing plan before advancing (present plan summary, ask approve/reject/amend). If status is not `in_progress`, Update feature.yaml: Set `status: in_progress`, `updated_at: {timestamp}`; **Update state.yaml:** `updated_at`.
3. **Always** update state.yaml `session.last_action` and `session.resume` (regardless of whether status changed).
4. Proceed to Phase 3.

### Phase 3: Execute (agent team)

**Note:** Feature status remains `in_progress` throughout Phase 3.

1. **Parse tasks** from plan.md (each `### Task N:` section).

2. **Validate focus:** Re-read `feature.yaml` and `state.yaml`. Confirm `focus.feature` still matches this feature. If not, abort with error: "Feature focus has changed. Restart with `/yolo:feature start <id>`."

3. **Create agent team** via TeamCreate.

4. **Create shared task list** via TaskCreate for each task, with blockedBy from dependencies.

5. **Spawn teammates** (model from `config.yaml` `agents.execute`, max 4) — each gets:
   - Execute role instructions (read `.claude/yolo/agents/execute.md`)
   - Domain context (nearest CLAUDE.md files)
   - Assigned task IDs
   - Working directory: `{worktree_dir}`

6. **Lead monitors:** Wait for task completions, handle failures. Lead never implements — only coordinates. Lead handles all git operations (execute agents do not run git commands). After each task completion: re-read `feature.yaml` and `state.yaml` to get current values, then update `feature.yaml` (`tasks.completed += 1`, `tasks.current`) and `state.yaml` (`updated_at`), then commit changes in the worktree (use the agent's `commit_message` from its output YAML).

7. **Shutdown teammates** when all tasks done.

### Phase 4: Verify-fix loop

```
Max 3 iterations:
  1. Run checks: type checking, tests, linting (use project's configured commands)
  2. If all pass → **Re-read feature.yaml** to confirm status is still `in_progress`. Update feature.yaml: Set `status: verifying`, `updated_at: {timestamp}`.
     **Re-read state.yaml**, then update: `updated_at`, `session.last_action: "Verify-fix loop passed"`, `session.resume`. Proceed to Phase 5
  3. If fail →
     - Collect error output + failing file paths
     - Spawn execute agent (model from `config.yaml` `agents.execute`) with:
       task: "fix test/type/lint failures"
       context: error output from failed checks
       files: failing files + related source
       previous_attempt: {attempt number}
     - Commit fixes, go to step 1
  4. If max iterations exhausted → Stop pipeline, report errors.
     Feature remains `in_progress`. User can re-run `/yolo:feature start <id>`.
```

Note: The project may have pre-commit hooks configured with linting and tests.
If a commit is rejected by pre-commit hooks, treat the hook failures as lint/test errors and
include them in the verify-fix loop iterations.

### Phase 5: Verify (verify agent)

1. **Spawn verify agent** (model from `config.yaml` `agents.verify`):
   ```
   Task(subagent_type: "general-purpose", model: config.agents.verify)
   ```
   Read `.claude/yolo/agents/verify.md` for agent instructions.
   Input: criteria (from feature.yaml `success_criteria`), files (changed files), business_rules.

2. **If passed:** Proceed to Phase 6.
3. **If failed:** Stop pipeline, report failing criteria. Feature remains `verifying`. User can re-run `/yolo:feature start <id>` to resume.

### Phase 6: Complete

Follow `/feature complete` process below.

---

## /feature add <name> [--prompt "<goal>"]

Add a new feature to the active release. Creates a `feature.yaml` with the same schema as features produced by the feature-breakdown agent during `/yolo:release start`.

### Process

1. **Validate state:** Read `state.yaml`, resolve `focus.release`. Release must be `active`. If no active release, error: "No active release. Run `/yolo:release start` first."

2. **Read release.yaml:** Load `features.list` to determine the next sequential ID. If the last feature is `"06"`, the next is `"07"`. Zero-pad to 2 digits.

3. **Parse arguments:**
   - `<name>` (required) — kebab-case feature name (e.g., `fix-auth-redirect`). Validate: must be kebab-case (`/^[a-z0-9]+(-[a-z0-9]+)*$/`), must not already exist in `features.list`.
   - `--prompt "<goal>"` — the feature goal. If not provided, collect via AskUserQuestion.

4. **Collect feature metadata** via AskUserQuestion (skip fields already provided via flags):
   - `goal` (required) — what the feature delivers. Pre-filled from `--prompt` if provided.
   - `success_criteria` (required) — 3-8 testable criteria. Ask user to provide as a list.
   - `scope.directories` (optional) — directories this feature touches.
   - `depends_on` (optional) — list of existing feature IDs this depends on (format: `"{id}-{name}"`).

5. **Validate collected data:**
   - `success_criteria`: 3-8 items, no empty strings.
   - `depends_on`: all referenced features exist in `features.list`. No circular dependencies introduced.

6. **Create feature directory:** `.planning/releases/{release-id}/features/{id}-{name}/`

7. **Write `feature.yaml`** with the full schema:
   ```yaml
   id: "{next_id}"
   name: "{name}"
   title: "{title}"           # derived from name (kebab-to-title-case) or first line of goal
   goal: |
     {goal from user}
   success_criteria:
     - "Criterion 1"
     - ...
   scope:
     directories: [...]       # from user input, or empty list
     patterns: ["*.ts", "*.tsx"]
   depends_on: [...]           # format: "{id}-{name}", or empty list
   estimated_tasks: 0
   services_touched: [...]     # inferred from scope.directories (e.g., "apps/web" → "apps/web")
   domain_entities: []
   business_rules: []
   status: pending
   started_at: null
   completed_at: null
   updated_at: "{timestamp}"
   tasks:
     total: 0
     completed: 0
     current: null
   ```

   **Inferring `services_touched`:** Extract the top-level service path from each directory in `scope.directories`. For example, `apps/web/src/components/` → `apps/web`, `services/api/src/auth/` → `services/api`. Deduplicate.

8. **Update release.yaml:** Append `"{id}-{name}"` to `features.list`, increment `features.total`, update `updated_at`.

9. **Update state.yaml:** Update `updated_at`, `session.last_action: "Added feature {id}-{name}"`, `session.resume: "New feature added. Start with /yolo:feature start {id}-{name}"`.

10. **Report** the created feature:
    ```
    FEATURE ADDED: {id}-{name}
    ─────────────────────────────
      Title:    {title}
      Release:  {release-id}
      Goal:     {goal summary}
      Criteria: {count} items
      Depends:  {depends_on or "none"}

    NEXT STEP
      /yolo:feature start {id}-{name}
    ```

---

## /feature plan [--amend]

Create plan.md for the current feature.

### Process

1. **Validate:** Feature must be `pending`, `researching`, or `planning` (or `in_progress` for `--amend`). Check that all features in `depends_on` are `completed`. If not, reject with error: "Cannot plan feature; unmet dependencies: {list}. Complete those features first."

2. **Check intake:** Load intake version from release for context.

3. **Research (if not amending):**
   - **If** release `research.md` exists **and** feature has `scope.directories` → reuse release research (skip agent spawn).
   - **Else** → spawn research agent (model from `config.yaml` `agents.research`):
     ```
     Task(subagent_type: "general-purpose", model: config.agents.research)
     ```
     Read `.claude/yolo/agents/research.md` for agent instructions.
     Input: goal (feature goal), scope (feature scope.directories), intake (release intake path), release_context (release ID and goal).
     If research returns `open_questions` with `blocking: true`, present each to user via AskUserQuestion before proceeding.

4. **Read feature.yaml** to confirm current status. **Update feature.yaml:** Set `status: planning`, `updated_at: {timestamp}`. **Update state.yaml:** `updated_at`, `session.last_action: "Planning feature"`, `session.resume`.

5. **Spawn plan agent** (model from `config.yaml` `agents.plan`):
   ```
   Task(subagent_type: "general-purpose", model: config.agents.plan)
   ```
   Read `.claude/yolo/agents/plan.md` for agent instructions.
   Input: goal (feature title/goal), context (research `findings` output), intake_insights, gaps, domain_entities, business_rules, integration_map, lint_commands (discovered from package.json), test_commands (discovered from package.json), max_tasks: (from `config.yaml` `limits.max_tasks_per_feature`, default 5).
   If `--prompt`: inject as constraint.
   If `--amend`: pass existing plan with instruction to preserve completed tasks.

6. **Write plan.md** with tasks, files, verification criteria, execution order.

7. **Present for review:** User approves or rejects.
   - Approved → Update feature.yaml: Set `status: in_progress`, `updated_at: {timestamp}`, update task count. **Update state.yaml:** `updated_at`, `session.last_action: "Plan approved"`, `session.resume`.
   - Rejected → Update feature.yaml: Set `status: pending`, `updated_at: {timestamp}`, delete plan.md, reset `tasks.total` and `tasks.completed` to 0. **Update state.yaml:** `updated_at`, `session.last_action: "Plan rejected"`, `session.resume`. Feature can be re-planned via `/yolo:feature plan` or restarted via `/yolo:feature start`. Note: `/feature start` will re-validate `depends_on` upon restart.

---

## /feature verify

Verify feature meets success criteria.

### Process

1. **Validate:** Feature must be `in_progress` or `verifying`. If `completed`, reject — terminal state cannot be re-verified. Verify `tasks.total > 0` — if not, error: "No tasks planned. Run `/yolo:feature plan` first." Verify `tasks.completed > 0` and `started_at` is set. If no tasks completed or not started, error: "No tasks executed. Run `/yolo:feature start <id>` first."

2. **Compile check:** Run the project's type checker. If fails → report errors, stop.

3. **Re-read feature.yaml** to confirm status is still `in_progress` or `verifying`. If status has changed unexpectedly, error: "Feature status changed. Re-run `/yolo:feature start <id>` to refresh." **If status is `in_progress`:** Update feature.yaml: Set `status: verifying`, `updated_at: {timestamp}`. **Update state.yaml:** `updated_at`, `session.last_action`, `session.resume`.

4. **Spawn verify agent (haiku):**
   Read `.claude/yolo/agents/verify.md` for agent instructions.
   Input: criteria (from feature.yaml `success_criteria`), files (changed files), business_rules.

5. **Determine result:**
   - All criteria pass → proceed to step 6
   - Blocker failures → **Re-read feature.yaml** to confirm status is still `verifying` before writing. Update feature.yaml: Set `status: in_progress`, `updated_at: {timestamp}`. **Update state.yaml:** `updated_at`, `session.last_action: "Verify failed with blockers"`, `session.resume: "Resume from Phase 4 (verify-fix loop). Failed check: {check_type}. Error: {error_summary}."`. Write verification.md with results. Report with next steps: user should fix blockers, then re-run `/yolo:feature start <id>` to resume from Phase 4. Stop.
   - Warning-only failures → proceed to step 6 (warnings reported)

6. **Write verification.md** with results, evidence, issues.

7. **Run `/feature complete` process** to finalize: merge worktree, create summary.md, update release progress, and update state.yaml.

---

## /feature complete

Mark feature as completed, merge worktree.

### Process

1. **Validate:** Feature must be `verifying`. If already `completed`, reject — terminal state cannot be re-completed. Verification must have passed.

2. **Update feature.yaml:** Set `status: completed`, `completed_at`, `updated_at`.

3. **Create summary.md** in feature directory with: goal, success criteria results, tasks completed, files changed, verification outcome.

4. **Merge worktree:**
   ```bash
   git merge "feature/{feature_id}" --no-ff -m "merge: feature/{feature_id}"
   git worktree remove "{worktree_dir}"
   git branch -d "feature/{feature_id}"
   ```
   If merge conflicts: stop, let user resolve, retry.

5. **Update release progress:** Re-read state.yaml to confirm `focus.release` still matches this feature's release ID — if mismatch, abort with error. Load release.yaml, read current `features.completed`, increment, update `updated_at`, write back.

6. **Update state.yaml:** Set `updated_at: {timestamp}`, clear `focus.feature`, update release progress, update `session.last_action` and `session.resume`.

7. **Determine next:** Show next pending feature or release completion status.

---

## /feature status [id]

Show feature progress (read-only). Read the feature's `feature.yaml` directly for current status.

### Display

```
FEATURE STATUS: {id}
─────────────────────────────
  Title:    {title}
  Status:   {status}
  Release:  {release}

LIFECYCLE
  pending → researching → planning → in_progress → verifying → completed
                                                      ^ HERE

TASKS                                    {completed}/{total}
  [v] Task 1 title
  [>] Task 2 title (current)
  [ ] Task 3 title

SUCCESS CRITERIA
  - Criterion 1
  - Criterion 2

NEXT STEP
  {suggested action based on status}
```

---

## Notes

- Features are always release-scoped
- Features can be added manually via `/yolo:feature add` — creates the same `feature.yaml` structure as the feature-breakdown agent
- Each feature gets its own git worktree + branch
- Pipeline: research → plan → execute → verify-fix → verify → complete
- Individual commands (`/yolo:feature plan`, `/yolo:feature verify`, etc.) are override entry points for specific stages
- Verify-fix loop runs between execute and verify — catches type/test/lint errors automatically
- Pre-commit hooks may be configured with linting and tests — all changes must pass
- Worktree creation and committed changes are mandatory for every feature
- Worktree removed after merge; preserved on failure for manual fix
- Lead never implements tasks — always delegates to teammates
- Lead handles all git operations (execute agents do not run git commands)
- Max 4 teammates per feature execution
