# Feature Workflow
# Commands: /yolo:feature add, /yolo:feature start, /yolo:feature plan, /yolo:feature verify, /yolo:feature complete, /yolo:feature status

Read `workspace/state.yaml` before any mutating operation. Validate it exists and is valid YAML — if missing, error: "Run `/yolo:init` first." For read-only commands (`/feature status`), fall back to reading `feature.yaml` directly if state.yaml is unavailable.
**Rule:** Every state.yaml or feature.yaml mutation must update `updated_at` to current ISO 8601 UTC timestamp.
**Rule:** Workflows are single-threaded — only one workflow operates on a feature at a time. Multi-session concurrent operation on the same feature is explicitly unsupported and may cause state corruption.

---

## /feature start <id> [--force] [--prompt "<text>"]

Full pipeline: research → plan → execute → hook gate → verify → complete.

**Mandatory:** Every feature MUST create a git worktree, implement changes there, ensure all lint and test checks pass (including any pre-commit hooks), and commit changes. This project may have pre-commit hooks configured with linting and tests. All lint errors and test failures must be resolved before completing.

### Phase 1: Setup

1. **Resolve feature:** Find feature directory in focused release (`releases/{release}/features/{id}-*`). If no ID, start next pending feature.

2. **Check preconditions:**
   - **Parent release must be `active`** — read `release.yaml` status. If `pending`, error: "Release not started. Run `/yolo:release start` first." If `completed`, error: "Release is completed."
   - If feature is `completed`: reject with error — terminal state cannot be restarted
   - No other feature currently in progress (unless resuming this one) — if `focus.feature` in state.yaml points to a different feature, read that feature's `feature.yaml` to get its actual status; if it is `researching`, `planning`, `in_progress`, or `verifying`, reject. **Additional check:** scan all features in the release for active non-terminal statuses (`researching`, `planning`, `in_progress`, `verifying`) to catch orphaned in-progress features. If found, reject with error: "Feature {orphaned_id} is in '{status}'. Resume it with `/yolo:feature start {orphaned_id}`, or reset it manually in feature.yaml before starting a new feature." Features in failure states (`hook_gate_failed`, `verify_failed`) only block features that depend on them via `depends_on` — they do not block unrelated features.
   - **Concurrency guard:** If `session.run_active` is `true` in state.yaml, warn user: "A `/release run` is in progress (started at {run_started_at}). Starting a feature manually may cause conflicts. Continue?" via AskUserQuestion. If rejected, stop.
   - If feature is already `researching`: re-validate `depends_on` (all must be `completed`). **Worktree check:** Verify worktree exists at `{worktree_dir}` — if missing, warn: "Worktree was removed while feature was in 'researching'. Recreating." and recreate via `git worktree add "$WORKTREE_DIR" "feature/${feature_id}"` (reuse existing branch). If the branch also doesn't exist, reset feature to `pending` and restart from Phase 1. **Branch point check:** After recreating worktree, verify `branch_point` is still an ancestor of the branch HEAD (`git merge-base --is-ancestor {branch_point} HEAD` in the worktree). If not, update `branch_point` to the current merge-base with main (`git merge-base main HEAD`) and warn user: "branch_point updated — main has diverged since worktree was created." **Staleness check:** if `updated_at` is older than 2 hours, warn user: "Feature has been in 'researching' since {updated_at} — it may be stuck. Reset to pending and restart? Or resume?" via AskUserQuestion. **Retry escalation:** Read `research_retry_count` from `feature.yaml` (default 0 if field missing). Increment `research_retry_count` and write back to `feature.yaml`. If `research_retry_count >= 3`, suggest: "Feature has been retried from 'researching' {count} times. Consider: (1) reset to pending and use `/yolo:feature plan` to skip research, or (2) investigate research agent failures." via AskUserQuestion. Check whether research output exists (release research.md with applicable scope, or feature-level research artifact). If research is incomplete, re-run from Phase 2 (will spawn research agent). Otherwise resume from Phase 2 (plan step). **Update feature.yaml:** Set `updated_at: {timestamp}`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `focus.feature`, `updated_at`, `session.last_action: "Resuming feature {id} from researching"`, `session.resume`.
   - If feature is already `planning`: re-validate `depends_on` (all must be `completed`). **Worktree check:** Verify worktree exists at `{worktree_dir}` — if missing, warn: "Worktree was removed while feature was in 'planning'. Recreating." and recreate via `git worktree add "$WORKTREE_DIR" "feature/${feature_id}"` (reuse existing branch). If the branch also doesn't exist, reset feature to `pending` and restart from Phase 1. **Staleness check:** if `updated_at` is older than 2 hours, warn user: "Feature has been in 'planning' since {updated_at} — it may be stuck. Reset to pending and restart? Or resume?" via AskUserQuestion. **Check plan.md:** if plan.md does not exist, warn user: "Planning may have been interrupted (no plan.md found). Resuming will re-run the plan agent." Resume from Phase 2 (plan step). **Update feature.yaml:** Set `updated_at: {timestamp}`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `focus.feature`, `updated_at`, `session.last_action: "Resuming feature {id} from planning"`, `session.resume`.
   - If feature is already `in_progress`: re-validate `depends_on` — if any dependency is no longer `completed`, reject resume with error: "Dependency {id} is no longer completed. Fix dependencies before resuming: /yolo:feature start {dep_id}." **Worktree check:** Verify worktree exists at `{worktree_dir}` — if missing, error: "Worktree was removed while feature was in_progress. Code changes may be lost. Recreate worktree from branch? (branch may still contain commits)" via AskUserQuestion. If approved and branch exists, recreate via `git worktree add "$WORKTREE_DIR" "feature/${feature_id}"`. If branch doesn't exist, error: "Both worktree and branch are gone — cannot recover. Reset feature to pending?" via AskUserQuestion. If approved, reset to `pending` and restart from Phase 1. **Check `previous_failure`:** If `previous_failure` is `verify_failed`, resume from Phase 4 (fixes need re-validation by hooks). If `previous_failure` is `hook_gate_failed`, resume from Phase 4. Otherwise, **check task completion:** if `tasks.completed >= tasks.total` and `tasks.total > 0`, all tasks were completed before the crash — skip Phase 3 and resume directly from Phase 4 (hook gate). If tasks remain (`tasks.completed < tasks.total` or `tasks.total == 0`), resume from Phase 3. **Clean up stale team:** Before creating a new agent team in Phase 3, attempt TeamDelete to remove any stale team from a prior crashed run. **Update feature.yaml:** Set `updated_at: {timestamp}`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `focus.feature`, `updated_at`, `session.last_action: "Resuming feature {id} from in_progress"`, `session.resume`.
   - If feature is already `verifying`: re-validate `depends_on` (all must be `completed`). **Worktree check:** Verify worktree exists at `{worktree_dir}` — if missing, error: "Worktree was removed while feature was in 'verifying'. Recreate from branch?" via AskUserQuestion. If approved and branch exists, recreate via `git worktree add "$WORKTREE_DIR" "feature/${feature_id}"`. If branch doesn't exist, reset to `pending` and restart from Phase 1. **Staleness check:** if `updated_at` is older than 2 hours, warn user: "Feature has been in 'verifying' since {updated_at} — it may be stuck. Re-verify or reset?" via AskUserQuestion. **Check prior verification:** if `verification.md` does not exist, warn user: "Verification may have been interrupted (no verification.md found). Re-running verification." If `verification.md` exists and contains `passed: false`, inform user: "Prior verification failed with these issues: {summary}. Re-running verification." via AskUserQuestion — user can choose to re-verify or fix issues first. **Update feature.yaml:** Set `updated_at: {timestamp}`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `focus.feature`, `updated_at`, `session.last_action: "Resuming feature {id} from verifying"`, `session.resume`. Resume from Phase 5
   - If feature is `hook_gate_failed`: re-validate `depends_on` — if any dependency is no longer `completed`, reject resume with error: "Dependency {id} is no longer completed. Fix dependencies before resuming: /yolo:feature start {dep_id}." **Worktree check:** Verify worktree exists at `{worktree_dir}` — if missing, error: "Worktree was removed while feature had hook_gate_failed. Recreate from branch?" via AskUserQuestion. If approved and branch exists, recreate. If branch doesn't exist, reset to `pending` and restart. **Retry escalation:** Check `previous_failure` — if it is already `hook_gate_failed` (meaning this is at least the 2nd consecutive retry), warn user: "Hook gate has failed multiple times. Consider: (1) `/yolo:feature verify --force` to bypass hook gate, or (2) fix issues manually in the worktree at {worktree_dir}." via AskUserQuestion. User can choose to continue retry, bypass via --force, or stop. Update feature.yaml: Set `previous_failure: hook_gate_failed`, `updated_at` (keep `status: hook_gate_failed` — Phase 4 will set the appropriate status on success or failure). **Note:** This is intentionally asymmetric with `verify_failed` resume (which sets `status: in_progress`) — `hook_gate_failed` lets Phase 4 handle the status transition internally. Re-read `state.yaml` to get current values before writing. Update state.yaml: Set `focus.feature`, `updated_at`, `session.last_action: "Resuming feature {id} from hook_gate_failed"`, `session.resume`. Resume from Phase 4 (hook gate)
   - If feature is `verify_failed`: re-validate `depends_on` — if any dependency is no longer `completed`, reject resume with error: "Dependency {id} is no longer completed. Fix dependencies before resuming: /yolo:feature start {dep_id}." **Worktree check:** Verify worktree exists at `{worktree_dir}` — if missing, error: "Worktree was removed while feature had verify_failed. Recreate from branch?" via AskUserQuestion. If approved and branch exists, recreate. If branch doesn't exist, reset to `pending` and restart. **Retry escalation:** Read `verify_retry_count` from `feature.yaml` (default 0 if field missing). Increment `verify_retry_count` and write back to `feature.yaml`. If `verify_retry_count >= 3`, warn user: "Verification has failed {count} times. Consider: (1) `/yolo:feature verify --force` to bypass verification, (2) manually fix issues in the worktree at {worktree_dir}, or (3) reset feature to pending and re-plan." via AskUserQuestion. User can choose to continue retry, bypass, reset-and-replan, or stop. If user chooses reset-and-replan: reset feature.yaml to `status: pending`, `started_at: null`, `previous_failure: null`, `branch_point: null`, `research_skipped: false`, `verify_retry_count: 0`, `tasks.total: 0`, `tasks.completed: 0`, `tasks.completed_ids: []`, `tasks.current: null`; delete `plan.md` and `features/{id}/research.md` if they exist; clean up worktree and branch; stop pipeline. Update feature.yaml `status: in_progress`, `previous_failure: verify_failed`, and `updated_at`. **Note (asymmetry with hook_gate_failed resume):** `verify_failed` sets status to `in_progress` before Phase 4, while `hook_gate_failed` keeps its status and lets Phase 4 manage transitions. This means a crash between this status update and Phase 4 entry leaves the feature as `in_progress` with `previous_failure: verify_failed` — the in_progress resume handler (above) routes this correctly to Phase 4 via the `previous_failure` check. Re-read `state.yaml` to get current values before writing. Update state.yaml: Set `focus.feature`, `updated_at`, `session.last_action: "Resuming feature {id} from verify_failed"`, `session.resume`. Resume from Phase 4 (fixes need re-validation by hooks)
   - If feature is `pending`: all `depends_on` features must be `completed`. **Bypass check:** If any completed dependency has `bypass_reason` set, warn: "Dependency {id} was force-completed: {bypass_reason}. Its code changes may not be on main. Proceed?" via AskUserQuestion. **Unmerged worktree check:** For each completed dependency with `bypass_reason` set, check if a worktree still exists at the expected path (`../.${REPO_NAME}-worktrees/${dep_feature_id}`). If it does, additionally warn: "Dependency {id} has an unmerged worktree at {path}. Its code changes are NOT on main. Consider merging manually before proceeding." via AskUserQuestion.
   - **Else** (unknown status value): error: "Unknown feature status: {status}. feature.yaml may be corrupted."
   - **Dependency validation:** When checking `depends_on`, if a referenced feature's directory or `feature.yaml` does not exist, error: "Dependency {id} not found — it may have been removed. Update `depends_on` in feature.yaml to remove stale references, or use `/yolo:feature start {id} --force` to bypass missing dependency checks." **`--force` flag handling:** If `--force` is set, skip all `depends_on` validation (both existence and completion checks). Warn user: "⚠ Bypassing dependency checks via --force. Unmet dependencies may cause issues." via AskUserQuestion. If rejected, stop.

3. **Load feature.yaml:** Extract title, goal, success_criteria.

4. **Validate criteria:** At least 1 criterion, no empty strings, no duplicates. Warn on vague/untestable/too-broad criteria — let user accept or edit.

5. **Create worktree** (uses raw `git worktree add` instead of EnterWorktree — custom path convention needed for feature isolation across sessions, and EnterWorktree's auto-cleanup is undesirable since worktrees must persist on failure):
   **Orphaned worktree check:** If the worktree directory already exists but feature status is `pending` (possible from a failed plan rejection cleanup), warn user: "Worktree exists at {worktree_dir} but feature is pending — likely orphaned from a previous run. Remove and recreate?" via AskUserQuestion. If approved, run `git worktree remove "{worktree_dir}" --force` and `git branch -d "feature/{feature_id}" 2>/dev/null` before proceeding. If rejected, skip worktree creation and reuse existing.
   ```bash
   REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
   WORKTREE_DIR="../.${REPO_NAME}-worktrees/${feature_id}"
   BRANCH_POINT=$(git rev-parse HEAD)
   git worktree add "$WORKTREE_DIR" -b "feature/${feature_id}"
   ```
   **Store branch point:** Write `branch_point: "{BRANCH_POINT}"` to feature.yaml — used for accurate diffs in Phase 5 and `/feature verify`.

6. **Update feature.yaml:** Re-read `feature.yaml` to confirm status is still `pending` — if status has changed, error: "Feature status changed during start. Another session may have started this feature." Set `status: researching`, `started_at: {timestamp}`, `updated_at: {timestamp}`.
   **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Validate that `focus.release` matches the feature's `release` field from `feature.yaml` — if mismatch, update `focus.release` to match. Set `focus.feature`, `updated_at`, `session.last_action`, `session.resume`.

### Phase 2: Plan (research + plan agents)

Follow `/feature plan` process below. Skip if plan.md already exists — in that case:
1. **Validate research exists (if status is `researching`):** Check for release `research.md` or feature-level `features/{id}/research.md`. If neither exists and `research_skipped` is not `true`, warn user: "Plan exists but no research output found. The plan may be based on incomplete context. Re-plan with research? Or proceed with existing plan?" via AskUserQuestion. If user chooses re-plan, delete plan.md and re-run Phase 2 from research step.
   Validate plan.md has parseable YAML with a `tasks:` array and task count matches `feature.yaml` `tasks.total`. **Combined invariant + validation check:** Collect all inconsistencies before prompting the user — present them in a single AskUserQuestion: (a) If `status` is `pending` and plan.md exists: "Plan exists but feature is pending — inconsistent." (b) If `tasks.total` is 0 but plan.md has tasks: "Task count is 0 but plan has {N} tasks." (c) If plan.md is older than 24 hours: "Plan was created over 24 hours ago and may be based on outdated research." Present all applicable issues together: "Found {N} inconsistencies: {list}. Use existing plan anyway, or delete and re-plan?" via AskUserQuestion. If user accepts, update `tasks.total` from plan.md task count. If rejected, delete plan.md and re-plan. If `plan.md` is missing but `tasks.total > 0`, warn user: "Feature has task count but no plan. Resetting task counters before proceeding." Reset `tasks.total` to 0, `tasks.completed` to 0, and `completed_ids` to `[]`.
2. **Re-read feature.yaml** to confirm current status. Only `pending`, `researching`, `planning`, or `in_progress` may transition here — if status is `completed`, `hook_gate_failed`, or `verify_failed`, reject with error (failure statuses must be handled by the resume logic in Phase 1, not the Phase 2 skip path). If status is `planning`, require user re-approval of the existing plan before advancing (present plan summary, ask approve/reject/amend). If status is not `in_progress`, Update feature.yaml: Set `status: in_progress`, `updated_at: {timestamp}`.
   **Worktree check:** Verify worktree exists at `{worktree_dir}`. If missing, error: "Worktree was removed. Recreate from branch or reset to pending before proceeding." Offer to recreate via AskUserQuestion.
3. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Update `updated_at`, `session.last_action`, and `session.resume` (always — regardless of whether status changed).
4. Proceed to Phase 3.

### Phase 3: Execute (agent team)

**Note:** Feature status remains `in_progress` throughout Phase 3.

1. **Parse tasks** from plan.md (YAML `tasks:` array).

2. **Validate focus:** Re-read `feature.yaml` and `state.yaml`. Confirm `focus.feature` still matches this feature. If not, abort with error: "Feature focus has changed. Restart with `/yolo:feature start <id>`."

3. **Create agent team** via TeamCreate.

4. **Create shared task list** via TaskCreate for each task, with blockedBy from dependencies. **On resume (status was `in_progress`):** check `feature.yaml` `tasks.completed` — skip tasks that were already completed (by index or ID) to avoid duplicating work. **Crash-safe duplicate detection:** On resume, also scan the worktree for a `.task-locks/` directory. If it exists, read lock files (one per assigned task ID). Tasks found in `.task-locks/` but not in `tasks.completed_ids` were assigned but their completion was not recorded — **auto-check worktree for changes:** run `git diff --name-only` in the worktree to get uncommitted changes, **and also** run `git diff --name-only {branch_point}..HEAD` to check committed-but-unrecorded changes (handles the case where the code was committed in the worktree but the YAML update in the main tree was not recorded). Compare both sets of changed files against the task's `files` list from plan.md. If the task's expected files have changes in either set, auto-mark the task as completed (add to `completed_ids`, increment `tasks.completed`, delete the lock file) and inform user: "Task {id} was recovered from crash — code changes detected in worktree, marking as completed." If no matching changes are found, warn user: "Task {id} was assigned but no code changes found (possible crash before implementation). Re-assign?" via AskUserQuestion.

5. **Validate `max_teammates`:** Read `config.yaml` `limits.max_teammates`. If missing or <= 0, error: "Invalid max_teammates in config.yaml. Must be >= 1." **Guard against zero remaining tasks:** If `remaining_tasks == 0` after crash recovery in step 4 (all tasks already completed), skip Phase 3 entirely and proceed directly to Phase 4 (hook gate). **Spawn teammates** (model from `config.yaml` `agents.execute`, count: `min(remaining_tasks, config.yaml limits.max_teammates)`) — each gets:
   - Execute role instructions: read `.claude/yolo/agents/execute.md` and pass its content as the `prompt` parameter in the Task tool call
   - Domain context (CLAUDE.md files discovered by walking up from each directory in `scope.directories` to the repository root, collecting all CLAUDE.md files found at each level, deduplicated by path. **If `scope.directories` is empty:** fall back to repository root CLAUDE.md only.)
   - Assigned task IDs
   - Working directory: `{worktree_dir}`

6. **Lead monitors:** Wait for task completions, handle failures. Lead never implements — only coordinates. Lead handles all git operations (execute agents do not run git commands). After each task completion: re-read `feature.yaml` and `state.yaml` to get current values, **verify feature status is still `in_progress`** (if changed, abort with error: "Feature status changed unexpectedly to {status}. Restart with `/yolo:feature start <id>`."), then update `feature.yaml`: **track completed task IDs** in `tasks.completed_ids` array (append the completed task's ID); **guard against duplicates:** if the task ID is already in `tasks.completed_ids`, log warning: "Duplicate task completion detected for {task_id}" and do not increment; otherwise increment `tasks.completed += 1` (cap at `tasks.total`). Update `tasks.current`. Update `state.yaml` (`updated_at`, `session.last_action`, `session.resume`). **Task lock:** Before spawning each teammate, write a lock file at `{worktree_dir}/.task-locks/{task_id}` to mark the task as assigned. After confirming task completion and updating `tasks.completed_ids`, delete the lock file. Then commit changes in the worktree with `--no-verify` (use the agent's `commit_message` from its output YAML).

   > **Note:** `workspace/` is tracked in git and exists in both main tree and worktree. The lead operates from the main tree; state/feature YAML changes are made in the main tree and committed there with `--no-verify` (metadata-only commits — Phase 4 hook gate validates the full codebase later). Worktree commits contain only code changes. **Dual-commit ordering:** (1) write task lock in worktree, (2) commit code changes in worktree with `--no-verify`, (3) update `feature.yaml`/`state.yaml` in main tree, (4) commit metadata in main tree with `--no-verify`, (5) delete task lock. If step 3 or 4 fails, the lock file persists — crash recovery in step 4 of Phase 3 detects this via `.task-locks/` and reconciles by checking worktree for code changes.

7. **Shutdown teammates** when all tasks done.

8. **Clean up team** via TeamDelete to remove team and task directories. **Reset `tasks.current`:** Set `tasks.current: null` in `feature.yaml` and update `updated_at`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `updated_at`, `session.last_action: "All tasks completed for feature {id}"`, `session.resume: "Proceeding to hook gate (Phase 4)"`.

### Phase 4: Hook gate

1. **Re-read feature.yaml and state.yaml to get current values before writing.** **Status guard:** Verify feature status is `in_progress`, `hook_gate_failed`, or `verify_failed` — if status is any other value, abort with error: "Unexpected feature status '{status}' at hook gate. Expected 'in_progress', 'hook_gate_failed', or 'verify_failed'. Re-run `/yolo:feature start <id>` to refresh." (Note: `verify_failed` is accepted as a safety net for the resume path that routes through Phase 4.) **Dependency re-validation:** Re-check `depends_on` — all dependencies must still be `completed`. If any dependency is no longer `completed`, abort with error: "Dependency {id} is no longer completed. Fix dependencies before proceeding." (Guards against manual YAML edits between phases.) Update feature.yaml `updated_at` only — do NOT change status yet.
2. **Stage all uncommitted changes** (including any manual fixes from user) and **attempt to commit without** `--no-verify` — pre-commit hooks fire against the full worktree.
3. **If commit succeeds** (hooks pass) →
   Update feature.yaml: Set `status: verifying`, `updated_at`. **Clear `previous_failure` conditionally:** if `previous_failure` is `hook_gate_failed` or null, set `previous_failure: null`; if `previous_failure` is `verify_failed`, preserve it for Phase 5 diagnostics. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `updated_at`, `session.last_action: "Hook gate passed"`, `session.resume`.
   Proceed to Phase 5.
4. **If commit fails** (hooks reject) →
   Read `.claude/yolo/agents/execute.md` for agent instructions. Spawn execute agent via Task tool:
   ```
   Task(subagent_type: "general-purpose", model: config.agents.execute)
   ```
   With:
     - prompt: execute agent instructions from the file above
     - task: "Fix all pre-commit hook failures and make a successful commit in the worktree without `--no-verify`. Keep fixing and retrying until the commit passes."
     - context: hook error output, list of changed files
     - working directory: `{worktree_dir}`
   The agent handles iteration internally — fixes issues, retries the commit, repeats until success or its turn limit. **Implicit timeout:** The Task tool has an internal turn limit — if the agent exhausts its turn limit without a successful commit, the Task tool returns with a failure result. The workflow MUST check the Task tool's return status. If the Task tool returns a failure/incomplete result, treat it as "agent failed" and proceed to step 6.
5. **If agent succeeds** →
   Update feature.yaml: Set `status: verifying`, `updated_at`. **Clear `previous_failure` conditionally:** if `previous_failure` is `hook_gate_failed` or null, set `previous_failure: null`; if `previous_failure` is `verify_failed`, preserve it for Phase 5 diagnostics. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `updated_at`, `session.last_action: "Hook gate passed"`, `session.resume`.
   Proceed to Phase 5.
6. **If agent fails** (could not resolve) →
   Update feature.yaml: Set `status: hook_gate_failed`, `updated_at`. **Set `previous_failure` with history preservation:** if `previous_failure` was `verify_failed`, keep `previous_failure: verify_failed` to retain the original failure context; otherwise set `previous_failure: hook_gate_failed`.
   **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `session.last_action: "Hook gate failed"`, `session.resume: "Hook gate failed for feature {id}. Fix issues in worktree at {worktree_dir}, then re-run: /yolo:feature start <id>"`, `updated_at`. **Reconcile `releases[].progress`:** read release.yaml and count actual completed features to refresh the cached progress in state.yaml.
   **Git commit:** Check `git status` for changes in `workspace/`. If changes exist, stage `workspace/` files and commit: `"chore: hook gate failed for feature {id}"`.
   Report failure prominently:
   ```
   ⛔ PIPELINE FAILED
   Feature {id}: {name}
   Phase: Hook gate (Phase 4)
   Reason: Pre-commit hooks could not be resolved
   Last error: {hook error output}
   Worktree preserved at: {worktree_dir}
   Fix manually, then re-run: /yolo:feature start <id>
   ```
   Stop pipeline.

### Phase 5: Verify (verify agent)

0. **Dependency re-validation:** Re-read `feature.yaml` and re-check `depends_on` — all dependencies must still be `completed`. If any dependency is no longer `completed`, abort with error: "Dependency {id} is no longer completed. Fix dependencies before verifying."

1. **Determine changed files:** Read `branch_point` from feature.yaml. Run `git diff --name-only {branch_point}..HEAD` in the worktree to get the list of files changed by this feature. If `branch_point` is not set (legacy feature), fall back to `git diff --name-only main...HEAD`.

2. **Spawn verify agent** (model from `config.yaml` `agents.verify`):
   ```
   Task(subagent_type: "general-purpose", model: config.agents.verify)
   ```
   Read `.claude/yolo/agents/verify.md` for agent instructions.
   Input: criteria (from feature.yaml `success_criteria`), files (changed files from step 1), business_rules, lint_commands (from `feature.yaml` `lint_commands` — persisted during Phase 2 planning; if empty, let the verify agent discover from project config), test_commands (from `feature.yaml` `test_commands` — persisted during Phase 2 planning; if empty, let the verify agent discover).
   Working directory: `{worktree_dir}`
   **Persist `rule_results`** (if provided by the verify agent) to verification.md alongside `results` and `issues`. **Exclude `type_check_results`** from verification.md output — this field is agent-internal and must not be persisted.

3. **If passed:** Proceed to Phase 6.
4. **If failed:** Update feature.yaml: Set `status: verify_failed`, `previous_failure: verify_failed`, `updated_at`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `session.last_action: "Verification failed with blockers"`, `session.resume: "Verification failed for feature {id}. Fix failing criteria, then re-run: /yolo:feature start <id>"`, `updated_at`. **Reconcile `releases[].progress`:** read release.yaml and count actual completed features to refresh the cached progress in state.yaml. **Git commit:** Check `git status` for changes in `workspace/`. If changes exist, stage `workspace/` files and commit: `"chore: verify failed for feature {id}"`. Write `verification.md` with results (excluding `type_check_results`). Report failure prominently:
   ```
   ⛔ PIPELINE FAILED
   Feature {id}: {name}
   Phase: Verify (Phase 5)
   Reason: Success criteria not met
   Failing criteria: {list}
   Worktree preserved at: {worktree_dir}
   Fix manually, then re-run: /yolo:feature start <id>
   ```
   Stop pipeline.

### Phase 6: Complete

> **TOCTOU note:** The single-threaded workflow rule is the guard between Phase 5 setting `status: verifying` and Phase 6 reading it. No additional TOCTOU check is needed — concurrent modification is explicitly unsupported.

Follow `/feature complete` process below.

---

## /feature add <name> [--prompt "<goal>"]

Add a new feature to the active release. Creates a `feature.yaml` with the same schema as features produced by the feature-breakdown agent during `/yolo:release start`.

### Process

1. **Validate state:** Read `state.yaml`, resolve `focus.release`. Release must be `active`. If no active release, error: "No active release. Run `/yolo:release start` first." **Concurrency guard:** If `session.run_active` is `true` in state.yaml, warn user: "A `/release run` is in progress (started at {run_started_at}). Adding a feature during a run may not be picked up correctly — the run may have already passed the position where this feature should execute. You will need to re-run with `/yolo:release run` after adding. Continue?" via AskUserQuestion. If rejected, stop.

2. **Read release.yaml:** Load `features.list` to determine the next sequential ID. If the last feature is `"06"`, the next is `"07"`. Zero-pad to 2 digits.

3. **Parse arguments:**
   - `<name>` (required) — kebab-case feature name (e.g., `fix-auth-redirect`). Validate: must be kebab-case (`/^[a-z0-9]+(-[a-z0-9]+)*$/`), must not already exist in `features.list`.
   - `--prompt "<goal>"` — the feature goal. If not provided, collect via AskUserQuestion.

4. **Collect feature metadata** via AskUserQuestion (skip fields already provided via flags):
   - `goal` (required) — what the feature delivers. Pre-filled from `--prompt` if provided.
   - `success_criteria` (required) — testable criteria. Ask user to provide as a list.
   - `scope.directories` (optional) — directories this feature touches.
   - `depends_on` (optional) — list of existing feature IDs this depends on (format: `"{id}-{name}"`).

5. **Validate collected data:**
   - `success_criteria`: at least 1 item, no empty strings.
   - `depends_on`: all referenced features exist in `features.list`. No circular dependencies introduced.

6. **Create feature directory:** `workspace/releases/{release-id}/features/{id}-{name}/`

7. **Write `feature.yaml`** with the full schema:
   ```yaml
   id: "{next_id}"
   name: "{name}"
   title: "{title}"           # derived from name (kebab-to-title-case) or first line of goal
   release: "{release-id}"
   goal: |
     {goal from user}
   success_criteria:
     - "Criterion 1"
     - ...
   scope:
     directories: [...]       # from user input, or empty list
     patterns: []              # Reserved for future use
   depends_on: [...]           # format: "{id}-{name}", or empty list
   services_touched: [...]     # inferred from scope.directories (e.g., "apps/web" → "apps/web")
   domain_entities: []
   business_rules: []
   integration_map: []
   research_skipped: false
   branch_point: null             # Commit hash at worktree creation — used for accurate diffs
   previous_failure: null         # Previous failure status (hook_gate_failed/verify_failed) preserved for diagnostics
   status: pending
   created_at: "{timestamp}"
   started_at: null
   completed_at: null
   updated_at: "{timestamp}"
   bypass_reason: null
   run_failure_count: 0
   research_retry_count: 0
   verify_retry_count: 0
   tasks:
     total: 0
     completed: 0
     completed_ids: []
     current: null
   ```

   **Inferring `services_touched`:** Extract the top-level service path from each directory in `scope.directories`. For example, `apps/web/src/components/` → `apps/web`, `services/api/src/auth/` → `services/api`. Deduplicate.

8. **Update release.yaml:** Re-read `release.yaml` to get current values before writing (TOCTOU guard — verify `features.list` and `features.total` match expectations from step 2; if changed, warn user: "release.yaml was modified externally. Continue with updated values?" via AskUserQuestion). Append `"{id}-{name}"` to `features.list`, increment `features.total`, update `updated_at`.

9. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. **Reconcile progress:** re-read `release.yaml` and count actual completed features from `features.list` (read each feature's `feature.yaml` status) to get `features_completed`. Update `releases[].progress.features_total` to match `release.yaml` `features.total`, set `releases[].progress.features_completed` to the reconciled count. Recompute `releases[].progress.percentage` as `features_total > 0 ? (features_completed / features_total) * 100 : 0`. Update `updated_at`, `session.last_action: "Added feature {id}-{name}"`, `session.resume: "New feature added. Start with /yolo:feature start {id}-{name}"`.

10. **Git commit:** Check `git status` for changes in `workspace/`. If changes exist, stage `workspace/` files and commit: `"chore: add feature {id}-{name} to release {release-id}"`.

11. **Report** the created feature:
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

## /feature plan [--amend] [--force] [--prompt "<text>"]

Create plan.md for the current feature.

### Process

0. **Resolve feature:** Read `state.yaml`, resolve feature from `focus.feature`. If `focus.feature` is null, error: "No feature focused. Run `/yolo:feature start <id>` first." Read the feature's `feature.yaml`.

1. **Check release status:** Read `release.yaml` for this feature's release. Release must be `active`. If `pending`, error: "Release not started. Run `/yolo:release start` first." If `completed`, error: "Release is completed."

2. **Validate:** Feature must be `pending`, `researching`, or `planning` (or `in_progress`, `hook_gate_failed`, or `verify_failed` for `--amend`). If status is `hook_gate_failed` or `verify_failed` and NOT `--amend`: reject with error: "Feature has unresolved failures. Use `/yolo:feature start <id>` to resume, or `/yolo:feature plan --amend` to amend the plan." **If status is `researching` and not `--amend`:** **Recency check (skipped if `--force`):** If `--force` is not set: read `updated_at` from `feature.yaml` — if `updated_at` was modified within the last 5 minutes, reject with hard error: "Feature was updated {seconds}s ago — a research agent may be actively writing output. Wait for it to complete, or use `/yolo:feature plan --force` to override." If `--force` is set, skip the recency check and proceed. If `updated_at` is older than 5 minutes, warn user: "Feature is in 'researching' — a research agent may have been running in another session. Proceeding will override the research phase and transition to planning. Any in-flight research output may be lost. Continue?" via AskUserQuestion. If rejected, stop. **If status is `pending` and not `--amend`:** warn user: "Research has not been performed for this feature. Planning without research may produce a less informed plan. This may reduce plan quality. Continue?" via AskUserQuestion. If rejected, suggest `/yolo:feature start <id>` instead. If accepted, set `research_skipped: true` in `feature.yaml`. **If `--amend`:** verify that `plan.md` exists in the feature directory — if missing, error: 'No plan.md found to amend. Use `/yolo:feature plan` without --amend to create a new plan.' If `--amend` and status is `in_progress`, `hook_gate_failed`, or `verify_failed`: check that no teammates are actively executing (i.e., `tasks.completed == tasks.total`) — if tasks are still running, reject with error: "Cannot amend plan while tasks are being executed. Wait for execution to complete or restart the feature." **Circular dependency check:** Validate that this feature's `depends_on` does not create a cycle — build adjacency list from all features in the release and verify DAG (same algorithm as `/release start` step 9). If cycle detected, error: "Circular dependency detected: {cycle path}." Check that all features in `depends_on` are `completed`. If not, reject with error: "Cannot plan feature; unmet dependencies: {list}. Complete those features first." **Bypass check:** If any completed dependency has `bypass_reason` set, warn: "Dependency {id} was force-completed: {bypass_reason}. Its code changes may not be on main. Proceed?" via AskUserQuestion.

3. **Check intake:** Load intake version from release for context.

4. **Research (if not amending):**
   - **If** release `research.md` exists → reuse release research (skip agent spawn). Pass the full content of `research.md` as the plan agent's `context` input. Additionally, populate the plan agent's structured inputs from the feature's own `feature.yaml` fields: `domain_entities` → `domain_entities`, `business_rules` → `business_rules`, `integration_map` → `integration_map`. **Structured field enrichment:** If `research-output.yaml` exists in the release directory (created during `/release start` step 5), read it and use its structured fields (`intake_insights`, `gaps`) as direct inputs to the plan agent instead of relying on the plan agent to re-extract them from the markdown `research.md`. Note: `research.md` is the markdown-rendered output of the research agent's findings — it can be passed directly as `context` since the plan agent accepts markdown.
   - **Else** → **Load deferred tools:** Use ToolSearch to load WebSearch and WebFetch before spawning the research agent. Then spawn research agent (model from `config.yaml` `agents.research`):
     ```
     Task(subagent_type: "general-purpose", model: config.agents.research)
     ```
     Read `.claude/yolo/agents/research.md` for agent instructions.
     Input: goal (feature goal), scope (feature scope.directories), intake (release intake path), release_context (release ID and goal).
     If research returns `open_questions` with `blocking: true`, present each to user via AskUserQuestion before proceeding. **Record resolutions:** For each resolved question, add a `resolution` field with the user's answer, creating a `resolved_questions` list. Pass `resolved_questions` to the plan agent as the named `resolved_questions` input (see plan agent input schema). Also persist `resolved_questions` to `features/{id}/research.md` alongside the research output for session recovery.
     **Persist feature-level research:** Write the research agent's output to `features/{id}/research.md` in the release directory. **Also save structured output:** Write `features/{id}/research-output.yaml` with the research agent's structured YAML fields (`intake_insights`, `gaps`, `resolved_questions`) for consistency with the release-level enrichment path. On resume, if `features/{id}/research.md` exists, skip re-running the research agent and pass its content as the plan agent's `context` input (same as the release-level research.md reuse path). If `features/{id}/research-output.yaml` exists, use its structured fields as direct inputs to the plan agent.

5. **TOCTOU guard + status update:** Re-read `feature.yaml` to confirm status has not changed since step 2 — if status has changed, error: "Feature status changed during planning. Another session may have modified this feature." Also re-read `release.yaml` to confirm release is still `active` — if release status changed, error: "Release status changed during planning." Also check `updated_at` — if it has advanced since step 2's read, another operation may have touched this feature; warn user: "Feature was modified during research (updated_at changed). Continue?" via AskUserQuestion. **Update feature.yaml:** Set `status: planning`, `updated_at: {timestamp}`. **Crash recovery note:** If the plan agent (step 6) crashes after this status write, the feature will be stuck in `planning` with no `plan.md`. Recovery: run `/yolo:feature start <id>` which detects the `planning` status, checks for `plan.md`, and offers to re-run the plan agent. `/yolo:status` also flags features in `planning` without `plan.md` as likely crashed. If status was `pending` (transitioning via standalone `/feature plan`), also set `started_at: {timestamp}`. **Note:** Standalone `/feature plan` intentionally skips the `researching` status — it transitions directly to `planning`. The `researching` status is only set by `/feature start` Phase 1. **When `--amend` is used on an `in_progress`, `hook_gate_failed`, or `verify_failed` feature, status remains unchanged** — do not set to `planning`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `updated_at`, `session.last_action: "Planning feature"`, `session.resume`.

6. **Spawn plan agent** (model from `config.yaml` `agents.plan`):
   ```
   Task(subagent_type: "general-purpose", model: config.agents.plan)
   ```
   Read `.claude/yolo/agents/plan.md` for agent instructions.
   Input: goal (feature title/goal), context (full content of `research.md` — whether from release-level reuse or fresh feature-level research), domain_entities (from `feature.yaml`), business_rules (from `feature.yaml`), integration_map (from `feature.yaml` — only populated for features created via `/release start`; empty for `/feature add` features or when research agent did not run), intake_insights (from research agent output when ran fresh; when reusing research.md, pass from `research-output.yaml` structured fields if available, otherwise omit — the plan agent will extract from the full context), gaps (from research agent output when ran fresh; when reusing research.md, pass from `research-output.yaml` structured fields if available, otherwise omit — the plan agent will extract from the full context), resolved_questions (from user resolution of blocking open_questions; when reusing release research, pass from `research-output.yaml` `resolved_questions` field if available), lint_commands (if known — discovered by reading project build config e.g. `package.json` scripts, `Makefile` targets, etc.; omit if not found and let the plan agent discover — **persist discovered commands to `feature.yaml`** as `lint_commands` and `test_commands` fields for passing to the verify agent in Phase 5, surviving session boundaries), test_commands (same as lint_commands — persist to `feature.yaml`), max_tasks: (from `config.yaml` `limits.max_tasks_per_feature`, default 5).
   If `--prompt`: inject as `constraints` input to the plan agent.
   If `--amend`: pass existing plan with instruction to preserve completed tasks.

   **Extract lint/test commands:** After the plan agent returns, extract `lint_commands` and `test_commands` from the agent's output YAML. If discovered (non-empty arrays), persist them to `feature.yaml` as `lint_commands` and `test_commands` fields.

7. **Write plan.md** with tasks, files, verification criteria, execution order.

8. **Present for review:** User approves or rejects.
   - Approved → **Create worktree** if not already created (standalone `/feature plan` without prior `/feature start`): follow the worktree creation steps from Phase 1 step 5 — specifically: compute `WORKTREE_DIR` and `BRANCH_POINT`, run `git worktree add`, and **write `branch_point: "{BRANCH_POINT}"` to feature.yaml** (critical for Phase 5 diff accuracy). **Important:** Worktree creation MUST succeed before writing `status: in_progress`. If worktree creation fails, leave status unchanged and error. **TOCTOU guard:** Re-read `feature.yaml` to confirm status is still `planning` — if status has changed, error: "Feature status changed during plan approval. Another session may have modified this feature." Update feature.yaml: Set `status: in_progress`, `updated_at: {timestamp}`, update task count. If `started_at` is null, also set `started_at: {timestamp}`. **Note:** The `researching` status is not set by standalone `/feature plan` — it is only set when `/feature start` runs the full pipeline. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `focus.feature: {feature_id}`, `updated_at`, `session.last_action: "Plan approved"`, `session.resume`. **Crash recovery note:** If a crash occurs between the feature.yaml write (`status: in_progress`) and this state.yaml write (`focus.feature`), the feature will be `in_progress` but unfocused. `/yolo:status` reconciliation detects this — the feature's `in_progress` status is preserved and the user can re-focus via `/yolo:feature start <id>`.
   **Git commit:** Check `git status` for changes in `workspace/`. If changes exist, stage `workspace/` files and commit: `"chore: plan feature {feature_id}"`.
   - Rejected → Update feature.yaml: Set `status: pending`, `started_at: null`, `updated_at: {timestamp}`, `research_skipped: false`, `previous_failure: null`, `research_retry_count: 0`, `verify_retry_count: 0`, `lint_commands: []`, `test_commands: []`, reset `tasks.total` and `tasks.completed` to 0, reset `completed_ids` to `[]`, set `tasks.current: null`. Delete plan.md, delete `features/{id}/research.md` if it exists (ensure clean slate on restart). **Clean up worktree and branch** if they exist (created in Phase 1 step 5, if applicable):
1. Run `git worktree remove "{worktree_dir}" --force`. If this fails, warn user: "Worktree cleanup failed at {worktree_dir}. Manual cleanup required: `git worktree remove {worktree_dir} --force`." via AskUserQuestion — user must acknowledge before proceeding.
2. Run `git branch -d "feature/{feature_id}"`. If this fails (branch may not exist if worktree creation failed), ignore — branch deletion failure is non-critical when worktree is already removed. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `focus.feature: null`, `updated_at`, `session.last_action: "Plan rejected"`, `session.resume`. Feature can be re-planned via `/yolo:feature plan` or restarted via `/yolo:feature start`. Note: `/feature start` will re-validate `depends_on` upon restart.
   **Git commit:** Check `git status` for changes in `workspace/`. If changes exist, stage `workspace/` files and commit: `"chore: reject plan for feature {feature_id}"`.

---

## /feature verify [--force]

Verify feature meets success criteria. Use `--force` to bypass `hook_gate_failed` guard (skips hook gate requirement with user confirmation).

**Note:** When called on an `in_progress` feature, this skips Phase 4 (hook gate). Pre-commit hooks have NOT been validated. The user is choosing to verify without the hook gate safety net.

### Process

0. **Resolve feature:** Read `state.yaml`, resolve feature from `focus.feature`. If `focus.feature` is null, error: "No feature focused. Run `/yolo:feature start <id>` first." Read the feature's `feature.yaml`.

1. **Validate status (explicit guard):**
   - `in_progress`, `verifying`, `verify_failed` → allowed (proceed)
   - `completed` → reject: "Terminal state — cannot be re-verified."
   - `pending`, `researching`, `planning` → reject: "Feature has not been executed yet. Run `/yolo:feature start <id>` first."
   - `hook_gate_failed` → reject: "Must pass hook gate first. Run `/yolo:feature start <id>` to resume from Phase 4, or `/yolo:feature verify --force` to bypass." If `--force` flag is set: warn user prominently: "⚠ Bypassing hook gate — pre-commit hooks have NOT passed. This may result in broken code on main. Proceed?" via AskUserQuestion. If approved, increment `verify_retry_count` in feature.yaml (tracks bypass attempts for escalation), set `status: verifying`, `previous_failure: hook_gate_failed`, `updated_at: {timestamp}` in feature.yaml. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `updated_at`, `session.last_action: "Bypassed hook gate for feature {id} via --force"`, `session.resume`. Continue. If rejected, stop.
   - unknown → reject: "Unknown feature status: {status}."

   If `verify_failed`: increment `verify_retry_count` in feature.yaml (consistent with `/feature start` resume handler). Warn: "Re-verifying without re-running hook gate (Phase 4). Ensure fixes have been committed. Continue?" via AskUserQuestion. Verify `tasks.total > 0` — if not, error: "No tasks planned. Run `/yolo:feature plan` first." Verify `tasks.completed > 0` and `started_at` is set. If no tasks completed or not started, error: "No tasks executed. Run `/yolo:feature start <id>` first." **If status is `in_progress`:** verify `tasks.completed == tasks.total` — if not, error: "Not all tasks completed ({tasks.completed}/{tasks.total}). Complete all tasks before verifying. Run `/yolo:feature start <id>` to continue execution." **Sanity check:** If `tasks.completed > tasks.total`, warn: "Task count inconsistency ({tasks.completed}/{tasks.total}). State may be corrupted." via AskUserQuestion.

2. **Re-read feature.yaml** to confirm status is still `in_progress`, `verifying`, or `verify_failed`. If status has changed unexpectedly, error: "Feature status changed. Re-run `/yolo:feature start <id>` to refresh." **If status is not `verifying`:** Update feature.yaml: Set `status: verifying`, `updated_at: {timestamp}`. **Update state.yaml:** `updated_at`, `session.last_action`, `session.resume`. **Worktree check:** Verify worktree exists at `{worktree_dir}` — if missing, error: 'Worktree was removed. Recreate from branch before verifying.' via AskUserQuestion. If approved and branch exists, recreate. If not, error: 'Cannot verify — no worktree available.'

3. **Determine changed files:** Read `branch_point` from feature.yaml. Run `git diff --name-only {branch_point}..HEAD` in the worktree to get the list of files changed by this feature. If `branch_point` is not set (legacy feature), fall back to `git diff --name-only main...HEAD`.

4. **Spawn verify agent** (model from `config.yaml` `agents.verify`):
   Read `.claude/yolo/agents/verify.md` for agent instructions.
   Input: criteria (from feature.yaml `success_criteria`), files (changed files from step 3), business_rules, lint_commands (if known from plan agent discovery or project build config), test_commands (same).
   Working directory: `{worktree_dir}`
   **Persist `rule_results`** (if provided by the verify agent) to verification.md alongside `results` and `issues`. **Exclude `type_check_results`** from verification.md output — this field is agent-internal and must not be persisted.

5. **Determine result:**
   - All criteria pass → proceed to step 6
   - Blocker failures → Update feature.yaml: Set `status: verify_failed`, `previous_failure: verify_failed`, `updated_at`. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `session.last_action: "Verify failed with blockers"`, `session.resume: "Verification failed for feature {id}. Fix failing criteria, then re-run: /yolo:feature start <id>"`, `updated_at`. **Reconcile `releases[].progress`:** read release.yaml and count actual completed features to refresh the cached progress in state.yaml. Write verification.md with results. Report failure prominently:
     ```
     ⛔ PIPELINE FAILED
     Feature {id}: {name}
     Phase: Verify (/feature verify)
     Reason: Success criteria not met
     Failing criteria: {list}
     Worktree preserved at: {worktree_dir}
     Fix manually, then re-run: /yolo:feature start <id>
     ```
     Stop.
   - Warning-only failures → proceed to step 7 (warnings reported)

6. **Write verification.md** with results, evidence, issues.

7. **Assert status:** Re-read feature.yaml and verify `status == verifying`. If status has changed unexpectedly, error: "Feature status changed to {status} during verification. Re-run `/yolo:feature start <id>`." **Run `/feature complete` process** to finalize: merge worktree, create summary.md, update release progress, and update state.yaml.

---

## /feature complete

Mark feature as completed, merge worktree.

### Process

0. **Resolve feature:** Read `state.yaml`, resolve feature from `focus.feature`. If `focus.feature` is null, error: "No feature focused." Read the feature's `feature.yaml`.

1. **Validate:** Feature must be `verifying`. If already `completed`, reject — terminal state cannot be re-completed. Note: `/feature complete` is always called as a sub-process of `/feature verify` (or `/feature start` Phase 6) in the single-threaded model — it is not intended for standalone concurrent use. Note: Force-completion from `in_progress` is only available via `/release end` (which always sets `bypass_reason`) — `/feature complete` requires verification to have passed. **Verify that `verification.md` exists** in the feature directory and contains `passed: true` (no blocker-severity failures). If `verification.md` is missing or contains blockers, reject with error: "Verification has not passed. Run `/yolo:feature verify` first." **Defense-in-depth:** Verify `tasks.completed == tasks.total` (and `tasks.total > 0`). If mismatch, warn: "Task count mismatch ({tasks.completed}/{tasks.total}). State may be corrupted. Proceed anyway?" via AskUserQuestion.

2. **Create summary.md** in feature directory with: goal, success criteria results, business rule verification results (if available from `rule_results` in verification.md), tasks completed, files changed, verification outcome.

3. **Verify branch and merge worktree:**
   Verify current branch is the base branch (e.g., main) — run `git branch --show-current` and confirm it matches the expected merge target. If not, error: "Not on expected base branch. Switch to the correct branch before completing."
   **Check branch existence:** Verify `feature/{feature_id}` branch exists (`git branch --list "feature/{feature_id}"`). If the branch does not exist but the worktree does, the merge may have already completed in a prior interrupted run — skip merge, proceed to step 4. If neither branch nor worktree exists, warn: "Feature branch and worktree already cleaned up. Proceeding to mark completed."
   ```bash
   git merge "feature/{feature_id}" --no-ff --no-verify -m "merge: feature/{feature_id}"
   git worktree remove "{worktree_dir}"
   git branch -d "feature/{feature_id}"
   ```
   If merge conflicts: stop, let user resolve, retry.

4. **Update feature.yaml (atomic field computation):** First, read `previous_failure` from `feature.yaml` to compute `bypass_reason` before clearing. If `previous_failure` was `hook_gate_failed`, set `bypass_reason: "completed with hook gate bypassed via /feature verify --force"`. Then write all fields in a single update: `status: completed`, `completed_at: {timestamp}`, `updated_at: {timestamp}`, `tasks.current: null`, `previous_failure: null`, `bypass_reason: {computed value}`, `verify_retry_count: 0`, `research_retry_count: 0`, `run_failure_count: 0`. (Done after merge to avoid marking completed if merge fails.)

5. **Update release progress:** Re-read state.yaml to confirm `focus.release` still matches this feature's release ID — if mismatch, abort with error. Load release.yaml, **reconcile `features.completed`** by counting actual completed features from `features.list` (read each feature's `feature.yaml` status) rather than blindly incrementing the cached counter. Update `updated_at`, write back.

6. **Update state.yaml:** Re-read `state.yaml` to get current values. Set `updated_at: {timestamp}`, clear `focus.feature`, **Note:** `/release run` only checks `focus.release` (not `focus.feature`) between feature executions — the null `focus.feature` window after clearing is expected and harmless. update `releases[].progress`: set `features_completed` to the reconciled count from step 5, set `features_total` from `release.yaml` `features.total`, recompute `percentage` as `features_total > 0 ? (features_completed / features_total) * 100 : 0`. Update `session.last_action` and `session.resume`.

7. **Git commit:** Check `git status` for changes in `workspace/`. If changes exist, stage `workspace/` files and commit: `"chore: complete feature {feature_id}"`.

8. **Determine next:** Show next pending feature or release completion status.

---

## /feature status [id]

Show feature progress (read-only). Read the feature's `feature.yaml` directly for current status. **If `bypass_reason` is set** (e.g., force-completed via `/release end`), display a warning: "⚠ Feature was force-completed: {bypass_reason}. Verification was not passed."

### Display

```
FEATURE STATUS: {id}
─────────────────────────────
  Title:    {title}
  Status:   {status}
  Bypass:   {bypass_reason or "none"}
  Release:  {release}

LIFECYCLE
  pending → researching → planning → in_progress → verifying → completed
                                        ↓              ↓
                                  hook_gate_failed  verify_failed
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
- Pipeline: research → plan → execute → hook gate → verify → complete
- Individual commands (`/yolo:feature plan`, `/yolo:feature verify`, etc.) are override entry points for specific stages
- Phase 3 commits use `--no-verify` to avoid hooks firing N times during parallel execution
- Phase 4 (hook gate) is a single commit with hooks enabled — pre-commit hooks are the quality gate
- Phase 6 merge uses `--no-verify` since Phase 4 already validated everything
- Worktree creation and committed changes are mandatory for every feature
- Worktree removed after merge; preserved on failure for manual fix
- Lead never implements tasks — always delegates to teammates
- Lead handles all git operations (execute agents do not run git commands)
- Teammate count configured via `config.yaml` `limits.max_teammates`
