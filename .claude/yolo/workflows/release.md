# Release Workflow
# Commands: /yolo:release new, /yolo:release start, /yolo:release run, /yolo:release end, /yolo:release status

Read `.planning/state.yaml` before any mutating operation. Validate it exists and is valid YAML — if missing, error: "Run `/yolo:init` first." For read-only commands (`/release status`), fall back to reading `release.yaml` files directly from `.planning/releases/` if state.yaml is unavailable.
**Rule:** Every state.yaml or release.yaml mutation must update `updated_at` to current ISO 8601 UTC timestamp.

---

## /release new <slug>

Create a pending release with initial intake.

### Process

1. **Generate ID:** `YYYY-MM-DD-slug` (e.g., `2026-02-15-mvp`)

2. **Validate:** Release directory must not already exist.

3. **Create structure:**
   ```
   .planning/releases/{id}/
   ├── release.yaml
   ├── intake/{slug}-v1/
   │   └── manifest.yaml
   └── features/
   ```

4. **Write release.yaml** (creating file with `status: pending` is the initial state write):
   ```yaml
   id: "{id}"
   slug: "{slug}"
   title: ""
   created_at: {timestamp}
   updated_at: {timestamp}
   goal: ""
   success_criteria: []
   intake:
     current: "{slug}-v1"
     locked: false
   features:
     total: 0
     completed: 0
     list: []
   status: pending
   started_at: null
   completed_at: null
   ```

5. **Write manifest.yaml:**
   ```yaml
   version: "{slug}-v1"
   release: "{id}"
   created_at: {timestamp}
   type: major
   sources: []
   stats:
     total_files: 0
     sources: 0
   ```

6. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. **Recovery check (forward):** scan `.planning/releases/` for directories not listed in `releases[]` — if found, validate that the directory contains a parseable `release.yaml` with required fields (`id`, `status`, `slug`). If valid, **validate slug-vs-directory consistency:** verify that the `id` and `slug` fields in `release.yaml` match the directory name (directory should be named `{id}` which contains the slug). If mismatch, warn: "Release directory name '{dirname}' does not match release.yaml id '{id}' or slug '{slug}'. Fix manually." Also check for expected subdirectories (`intake/`, `features/`) — if missing, warn: "Release directory {id} is missing subdirectories (intake/ or features/). It may be partially created. Repair (create missing dirs) or remove?" via AskUserQuestion. If subdirectories exist, warn: "Found release directory {id} not tracked in state.yaml. This may be from a crashed `/release new`. Add to state? (yes/no)" via AskUserQuestion. If invalid (missing or corrupt `release.yaml`), warn: "Found release directory {id} with no valid release.yaml — remove manually or reinitialize." **Recovery check (reverse):** for each entry in `releases[]`, verify the corresponding directory exists at `.planning/releases/{id}/`. If a directory is missing, warn: "Release {id} is tracked in state.yaml but its directory no longer exists. Remove orphaned entry? (yes/no)" via AskUserQuestion. If approved, remove the entry from `releases[]`. Read current `focus.release` — if another release is already focused, warn user and confirm before switching. If `session.run_active` is `true`, warn: "A release run is in progress on the currently focused release. Switching focus will disrupt the run. Continue?" via AskUserQuestion. **Check for duplicate release IDs:** verify `releases[]` does not already contain an entry with this release's ID before adding. If duplicate found, update the existing entry instead of adding a new one. Then add to `releases[]` with full field list: `id`, `slug`, `status: pending`, `intake: { current: "{slug}-v1", locked: false }`, `progress: { features_total: 0, features_completed: 0, percentage: 0 }`. Set `focus.release`. **Clear `focus.feature` with logging:** If `focus.feature` is currently set, log: "Clearing focus.feature (was: {focus.feature}) — switching to new release." Set `focus.feature: null`. Update `updated_at`, `session.last_action` and `session.resume`.

7. **Git commit:** Check `git status` for changes in `.planning/`. If changes exist, stage `.planning/` files and commit: `"chore: create release {id}"`.

8. **Report** with next steps: `/yolo:intake capture`, `/yolo:release start`.

---

## /release start [id] [--prompt "<text>"]

Activate a pending release: research codebase, define goal, create features.

### Process

1. **Resolve release:** Use arg or `focus.release`. Must be `pending`. If release is `active`, error: "Release is already active. Use `/yolo:release run` to continue working on features." If release is `completed`, error: "Release is already completed. Cannot restart a completed release."

2. **Read intake:** Load manifest, digests, `requirements.yaml`, and `conflicts.yaml` (if it exists) from intake directory.

3. **Load deferred tools:** Use ToolSearch to load WebSearch and WebFetch before spawning the research agent. **Spawn research agent** (model from `config.yaml` `agents.research`):
   ```
   Task(subagent_type: "general-purpose", model: config.agents.research)
   ```
   Read `.claude/yolo/agents/research.md` for agent instructions.
   Input:
   - goal: "Understand codebase architecture for release {id}"
   - scope: project source directories
   - intake: path to intake directory (e.g., `.planning/releases/{id}/intake/{version}/`)
   - release_context: release ID and goal
   - If `--prompt`: inject as high-priority constraint

   Output: findings, relevant_files, patterns, intake_insights, gaps, concerns, suggestions, domain_model, business_rules, integration_map, open_questions

4. **Verify research claims:** Spot-check files the agent marked as "functional" or "complete". Downgrade if key files are missing.

5. **Save research:** Write `research.md` (markdown rendering) to release directory. **Also save structured output:** Write `research-output.yaml` to the release directory containing the research agent's structured YAML output (findings, relevant_files, patterns, intake_insights, gaps, concerns, suggestions, domain_model, business_rules, integration_map, open_questions). This structured file enables crash recovery — if the session crashes after step 5 but before step 8, the structured fields can be re-read from `research-output.yaml` instead of being lost.

6. **Define release goal:** Based on research + intake + user prompt, draft goal, title, and success criteria. Present to user for approval via AskUserQuestion. If rejected, ask user via AskUserQuestion: "Revise goal based on feedback, or re-run research with updated focus?" Options: **Revise** (revise text and re-present) or **Re-research** (go back to step 3 with user's feedback as additional `--prompt` constraint). If Re-research, re-run from step 3 with the rejection feedback injected as a research constraint. Write approved title to `release.yaml`.

7. **Resolve open questions:** If research produced blocking questions, present each to user via AskUserQuestion. Record answers. **Persist resolved questions:** After all blocking questions are resolved, update `research-output.yaml` (saved in step 5) to add a `resolved_questions` field containing each resolved question with the user's `resolution` answer. This ensures crash recovery between step 7 and step 8 preserves the user's answers, and makes them available for `/feature plan` reuse.

8. **Spawn feature-breakdown agent** (model from `config.yaml` `agents.feature-breakdown`):
   ```
   Task(subagent_type: "general-purpose", model: config.agents.feature-breakdown)
   ```
   Pass research output fields from step 3 with these mappings:

   | Research Output | Feature-Breakdown Input | Action |
   |-----------------|------------------------|--------|
   | `findings` | `codebase_findings` | rename |
   | `open_questions` | `resolved_questions` | rename (after user resolution in step 7) |
   | `intake_insights` | `intake_insights` | pass through |
   | `gaps` | `gaps` | pass through |
   | `patterns` | `patterns` | pass through |
   | `domain_model` | `domain_model` | pass through |
   | `business_rules` | `business_rules` | pass through |
   | `integration_map` | `integration_map` | pass through |
   | `relevant_files` | — | saved to `research.md` only |
   | `concerns` | — | saved to `research.md` only |
   | `suggestions` | — | saved to `research.md` only |

   **Validate renamed fields before spawning:** After performing the renames above, verify that `codebase_findings` (renamed from `findings`) is non-empty. If the rename was missed or the source field was null, error: "Research output field 'findings' is missing — cannot map to 'codebase_findings' for feature-breakdown agent." **Validate research outputs before spawning:** Verify that `findings` and `domain_model` are non-empty (required for quality breakdown). If either is empty, warn user: "Research produced incomplete results: missing {list of empty required fields}. Feature breakdown quality may be degraded. Continue anyway?" via AskUserQuestion. If rejected, stop and suggest re-running with more specific `--prompt`. Additionally, if `business_rules` or `integration_map` are empty, note in the warning: "Optional fields empty: {list}. Feature breakdown will proceed but may lack domain-specific detail." (These fields may legitimately be empty arrays — the feature-breakdown agent accepts them as optional.)

   **Validate max_features:** Read `config.yaml` `limits.max_features_per_release`. If value exceeds 99, cap at 99 (feature IDs are two-digit sequential).

   Additional inputs: release_goal (from step 6), max_features (mapped from `config.yaml` `limits.max_features_per_release` → agent parameter `max_features`, default 12). If `--prompt`: inject as constraints.

   Read `.claude/yolo/agents/feature-breakdown.md` for agent instructions.

   Output: features[] with id, name, title, goal, success_criteria, scope, depends_on, services_touched, domain_entities (optional), business_rules (optional); also: dependency_graph, risks, assumptions, coverage

9. **Validate features:**
   - **Hard errors** (reject):
     - No circular dependencies in dependency graph — verify by topological sort: build adjacency list from `depends_on`, visit each feature tracking "in-progress" and "visited" sets; if a feature is reached while already "in-progress", a cycle exists. Report the cycle path and reject.
   - **Soft warnings** (warn user, allow proceeding via AskUserQuestion):
     - Feature touches many services (3+) — may indicate it should be split
     - Feature has many dependents — may be a bottleneck
     - Dependency graph is mostly linear — reduced parallelism opportunity
     - Feature has no success criteria or very vague criteria
     - Coverage gap: any intake requirement has empty `covered_by` list

10. **Present breakdown to user** with dependency graph, risks, and assumptions. Wait for approval.

11. **Create feature directories:** **TOCTOU guard:** Re-read `release.yaml` to confirm status is still `pending` — if status has changed, error: "Release status changed during start. Another session may have started this release." **Validate ID uniqueness:** Before creating directories, check each feature ID from breakdown output against existing entries in `features.list` (if any — e.g., from `/feature add`). If a collision is found, error: "Feature ID {id}-{name} already exists. Rename the conflicting feature in the breakdown output (e.g., increment ID) before proceeding." Present the collision to user for resolution via AskUserQuestion. For each feature, create `{id}-{name}/feature.yaml` in release `features/` dir with all fields from breakdown output, including `domain_entities`, `business_rules`, and `integration_map` if provided by the feature-breakdown agent. **Initialize fields:** Set `status: pending`, `started_at: null`, `completed_at: null`, `updated_at: {timestamp}`, `bypass_reason: null`, `run_failure_count: 0`, `research_retry_count: 0`, `verify_retry_count: 0`, `research_skipped: false`, `branch_point: null`, `previous_failure: null`, `baseline_failures: null`, `tasks: { total: 0, completed: 0, completed_ids: [], current: null }`. **Ensure `scope.patterns`** and `integration_map` are initialized to `[]` if not provided by the feature-breakdown agent. **Post-creation validation:** After the loop, verify all expected feature directories and `feature.yaml` files exist. If any are missing (partial failure — disk full, permission error, crash), list the missing features and error: "Feature directory creation incomplete — {N} of {total} created. Missing: {list}. Clean up partial state manually or re-run `/release start`."

12. **Write requirements.md (optional):** Release goal + success criteria + per-feature requirements. Human-readable summary — not consumed by downstream agents.

13. **Update release.yaml:** Re-read `release.yaml` to confirm status is still `pending` — if status has changed, error: "Release status changed during start. Another session may have started this release." Set `status: active`, `started_at`, `updated_at`, populate `features.list`, set `features.total` to count of created features, `features.completed: 0`.

14. **Update state.yaml:** Re-read `state.yaml` to get current values. **Verify `releases[]` entry exists** for this release ID — if missing (e.g., removed by concurrent `/release new` recovery), re-add it with full field list before updating. Set release `status: active`, update progress to `{ features_total: {count from step 11}, features_completed: 0, percentage: 0 }`, update `updated_at`, `session.last_action` and `session.resume`.

15. **Git commit:** Check `git status` for changes in `.planning/`. If changes exist, stage `.planning/` files and commit: `"chore: start release {id} — {feature_count} features created"`.

16. **Report** with next steps: `/yolo:feature start 01`.

---

## /release run [id] [--from <feature-id>]

Run all pending features sequentially through the full pipeline (`/yolo:feature start`).

### Process

1. **Resolve release:** Use arg or `focus.release`. Must be `active`. **Re-read state.yaml.** If `session.run_active` is `true`: if `--from` is specified, **verify `focus.release` matches this release** — if mismatched, warn: "Another release ({focus.release}) has an active run. Clear it and start this release?" via AskUserQuestion. If approved or matching, treat as intentional resume — clear `run_active` and proceed. Otherwise, check `session.run_started_at` — if more than 2 hours ago, warn user: "A release run has been active since {run_started_at} (over 2 hours). It may have crashed. Force-clear and continue?" via AskUserQuestion. If approved, clear `run_active` and proceed. If rejected or `run_started_at` is recent, error: "A release run is already in progress. Wait for it to complete, or use `/yolo:release run --from <feature-id>` to force-resume from a specific feature." **Early `--from` validation:** If `--from` is specified, immediately verify the target feature exists in `features.list` from release.yaml — if not found, error: "Feature {id} not found in release features list. Available features: {list}."

2. **If `--from <id>`:** Note starting point.

3. **Mark run active:** Re-read `state.yaml` to get current values. Update `state.yaml`: set `session.run_active: true`, `session.run_started_at: {timestamp}`, `session.last_action: "Starting release run"`, `updated_at`. **Reset failure counters (new run only):** If `--from` is NOT specified, reset `run_failure_count` to 0 in each feature's `feature.yaml` for this release **only for features with `status != completed`** (skip completed features to avoid unnecessary writes and `updated_at` churn on stable files).
   **Git commit:** Check `git status` for changes in `.planning/`. If changes exist, stage `.planning/` files and commit: `"chore: start release run {id}"`.

4. **Feature loop** (re-evaluate after each completion):

   a. **Build/refresh queue:** Read `features.list` from release.yaml. **Guard against external modifications:** If this is not the first iteration, compare `features.list` with the previous iteration's list — if features were added, removed, or reordered, warn user: "features.list was modified externally. Continue with updated list?" via AskUserQuestion. If rejected, stop run. Filter to features where `status` is not `completed`. Re-read all feature.yaml files for features in the updated list — **if any feature.yaml is missing or corrupt (unparseable YAML):** log warning: "Feature {id} has missing or corrupt feature.yaml — skipping for this run." Skip the feature (treat as failed) and continue with remaining features. Only stop the run if the unreadable feature is a required dependency of the next candidate. Verify every `depends_on` reference points to a feature that still exists in `features.list` — if any reference is dangling (feature was removed), stop run with error: "Feature {id} depends on {dep_id} which is no longer in features.list. Fix dependencies before resuming." Validate no circular dependencies exist — build adjacency list from `depends_on`, verify DAG (if cycle found, report cycle path and stop run with error). Sort by topological order (features whose `depends_on` are all `completed` come first; among equal candidates, sort by ID ascending). If `--from`: skip features before that ID.

   b. **Pick next:** Re-read `release.yaml` to confirm release is still `active`, re-read `state.yaml` to confirm `focus.release` still matches the release being run. **Anti-staleness queue refresh:** Before picking a candidate, re-read ALL non-completed feature.yaml files referenced in `features.list` (not just the single candidate) to rebuild the dependency graph and topological ordering with the current on-disk state. This refresh catches sibling features whose status changed between queue build (4a) and feature selection (4b) — e.g., a dependency that silently regressed, or a feature marked completed out-of-band. If the refreshed sort order differs from the step 4a ordering, log: "Queue refreshed — order changed due to on-disk state drift." Then take the first feature from the refreshed queue where all `depends_on` are `completed`. If release is no longer active, focus changed, or no eligible feature remains, exit loop. Note: `/release run` assumes single-user, single-session operation — this refresh is a best-effort safeguard against manual edits or crash recovery between iterations.

   c. **Run pipeline:** Invoke `/yolo:feature start {id}` via Skill tool. If Skill tool invocation itself fails (not the feature), increment `run_failure_count` in the feature's `feature.yaml` and retry once. If still failing, update `state.yaml`: set `session.run_active: false`, `session.run_started_at: null`, `session.last_action: "Release run stopped — Skill invocation failure"`, `session.resume: "Release run stopped due to Skill tool failure on feature {id}. Retry: /yolo:feature start {id}. Resume: /yolo:release run"`, `updated_at`. Stop run with error report and suggest running `/yolo:feature start {id}` manually.

   d. **On success:** Feature completes normally. Reset `run_failure_count` to 0 in the feature's `feature.yaml` and update `updated_at`. Loop back to step (a) to re-evaluate queue.

   e. **On failure:** Record the failed feature. **Track failure count:** Maintain a per-feature failure counter during the run — both in-memory (map: `{feature_id: failure_count}`) and persisted to `feature.yaml` as `run_failure_count` (increment on each failure, read on resume). On resume via `--from`, read `run_failure_count` from each feature's `feature.yaml` to initialize the in-memory map. Increment the counter for this feature (both in-memory and in `feature.yaml`). **If failure count exceeds 2 for any feature, skip it permanently** for this run with error: "Feature {id} failed {count} times — skipping to avoid infinite retry." **Reset `run_failure_count`** to 0 in feature.yaml when a feature completes successfully (in step 4d) or when a new `/release run` starts without `--from` (in step 3). **Reconcile feature status:** Re-read the failed feature's `feature.yaml` to detect its current status. If status is still `pending` (failure occurred before status mutation), log: "Feature {id} failed before status was updated (still pending). Skipping — manual start required via `/yolo:feature start {id}`." and skip this feature for the rest of the run. If stuck in an intermediate status (`researching`, `planning`, `in_progress`, `verifying`) that is not a recognized failure state (`hook_gate_failed`, `verify_failed`), offer to reset: "Feature {id} is stuck in '{status}' after pipeline failure. Reset to pending for retry? (yes = reset, no = skip and require manual intervention via `/yolo:feature start {id}`)" via AskUserQuestion. If approved, reset feature.yaml `status: pending`, `started_at: null`, `updated_at: {timestamp}`, `previous_failure: null`, `branch_point: null`, `research_skipped: false`, `run_failure_count: 0`, `research_retry_count: 0`, `verify_retry_count: 0`, `lint_commands: []`, `test_commands: []`, `tasks.total: 0`, `tasks.completed: 0`, `tasks.completed_ids: []`, `tasks.current: null`. **Clean up artifacts:** Delete `plan.md` and `features/{id}/research.md` if they exist (ensure clean slate — stale/corrupted plans from the crashed run must not persist through the reset). **Clean up worktree and branch** if they exist: `git worktree remove "{worktree_dir}" --force 2>/dev/null` and `git branch -d "feature/{feature_id}" 2>/dev/null`. If rejected, log in run report: "Feature {id} is stuck in '{status}' — manual intervention required." Check if other independent features remain eligible (i.e., non-completed features whose `depends_on` are all `completed` — not depending on the failed feature). If eligible features exist, **checkpoint state.yaml before looping:** re-read `state.yaml`, update `updated_at`, `session.last_action: "Feature {id} failed — continuing with remaining features"`, `session.resume: "Release run in progress. Last failure: {id}. Continuing with eligible features."` Then loop back to step (a) to continue with them. If no eligible features remain, **Reconcile release.yaml progress:** Re-read `release.yaml` and count actual completed features to refresh `features.completed` and `updated_at`. update `state.yaml`: set `session.run_active: false`, `session.run_started_at: null`, `session.last_action: "Release run stopped — feature failures"`, `session.resume: "Release run stopped. Failed: {list of failed ids}. Retry: /yolo:feature start {id}. Resume: /yolo:release run"`, `updated_at`. Stop the run. Report:
      ```
      RUN STOPPED
      ─────────────────────────────
      Failed features: {list of failed ids with names}
      Completed: {N}/{total} features this run
      Skipped:   {features that were pending but depend on failed features, including transitively blocked}

      Retry:   /yolo:feature start {id}
      Resume:  /yolo:release run
      ```

5. **Clear run state:** Re-read `state.yaml` to get current values before writing. Update `state.yaml`: set `session.run_active: false`, `session.run_started_at: null`, `session.last_action: "Release run completed"`, `session.resume: "All features processed. Run /yolo:release end to complete the release."`, `updated_at`.

   **Git commit:** Check `git status` for changes in `.planning/`. If changes exist, stage `.planning/` files and commit: `"chore: complete release run {id}"`.

6. **On all features complete:** Report summary. If failed features remain, list them with suggested actions (`/yolo:feature start {id}` to retry). If all features completed, suggest `/yolo:release end`.

---

## /release end [id]

Complete an active release.

### Process

1. **Resolve release:** Use arg or `focus.release`. Must be `active`. **Check `session.run_active`:** if `true` and `focus.release` matches this release, warn user: "A `/release run` is in progress on this release. Ending the release will disrupt the run. Continue?" via AskUserQuestion.

2. **Find incomplete features:** List all features with `status != completed`.

3. **If no incomplete features:** Skip to step 5.

4. **Per incomplete feature, ask user:**
   For features in `pending`, `researching`, or `planning` status: only the **Remove** option is available — do not present **Complete now**.
   - **Complete now** — only allowed if feature status is `verifying`, `in_progress` with `tasks.completed == tasks.total` (must have finished all tasks), `hook_gate_failed`, or `verify_failed`. If status is `in_progress` and `tasks.completed < tasks.total`, reject with error: "Feature has incomplete tasks ({tasks.completed}/{tasks.total}). Complete tasks first or choose Remove instead." If status is `verifying`, check whether `verification.md` exists and contains no blocker failures — if blockers exist, reject with error: "Feature has unresolved verification blockers. Fix blockers and re-run `/yolo:feature start <id>`, or choose Remove instead." If status is `hook_gate_failed` or `verify_failed`: warn user prominently: "Feature has unresolved failures ({status}). Force-completing bypasses remaining pipeline stages. Pre-commit hooks and/or success criteria have NOT been validated. Proceed?" via AskUserQuestion. If approved, proceed to force-complete (same as `in_progress` force-complete below, with `bypass_reason: "force-complete via /release end (from {status})"`). If rejected, offer: "Fix and re-run `/yolo:feature start <id>`, or choose Remove instead." **For `in_progress` features (force-complete):** warn user prominently: "This bypasses both the hook gate (Phase 4) and verification (Phase 5). Pre-commit hooks and success criteria have NOT been validated. Proceed?" via AskUserQuestion. Set `status: completed`, `completed_at: {timestamp}`, `updated_at: {timestamp}`, `tasks.current: null` in feature.yaml. Also set `bypass_reason: "force-complete via /release end"` in feature.yaml to explicitly distinguish force-completed features from normally verified ones. Create minimal `summary.md` in the feature directory: note the force-complete bypass ("Feature force-completed via /release end without hook gate or verification"). Create minimal `verification.md` with `passed: false, bypass: "force-complete via /release end"`. **Recovery note:** To revert a force-completed feature back to an active state: (1) delete `verification.md` (required — `/feature complete` checks for `passed: true`), (2) set `status` back to `in_progress` and `bypass_reason` to `null` in `feature.yaml`, (3) run `/yolo:status` to reconcile state.yaml. **Dependency check:** If this feature is in other features' `depends_on` lists, warn user prominently: "Feature {id} has dependents: {list}. Force-completing without merging means dependents may fail due to missing code changes. Consider merging the worktree manually first." If a worktree exists for this feature, warn user: "Worktree exists at {worktree_dir} with unmerged changes. Merge manually or changes will be lost." Do NOT auto-merge — force-completing is an escape hatch, not a shortcut. **Dependency impact warning:** If downstream features depend on this bypassed feature, `/feature start` will warn about the bypass but will proceed (warn-and-proceed). Users should verify the code is on main before starting dependent features. **Incremental progress update:** After each force-complete, re-read `state.yaml` and update `releases[].progress.features_completed`, recompute `percentage`, and update `session.last_action: "Force-completed feature {id}"`, `session.resume: "Release end in progress. Last action: force-completed feature {id}."`, `updated_at` immediately (crash-safe — don't defer to step 6).
   - **Remove** — allowed for any incomplete feature. **Before removal:** check if the feature branch has commits beyond the branch point (`git log main..feature/{feature_id} --oneline`). If commits exist, warn user: "Feature branch has {N} unmerged commits. Removing will lose this work. Proceed?" via AskUserQuestion. **Update YAML first (crash-safe order):** Remove from `features.list` in release.yaml, update `features.total`, update `state.yaml` `releases[].progress.features_total` to match. **Clear focus.feature:** If `focus.feature` in state.yaml matches the removed feature ID, set `focus.feature: null`. **Then delete directory:** Delete the feature directory. Clean up worktree and branch if they exist:
     ```bash
     git worktree remove "{worktree_dir}" --force 2>/dev/null
     git branch -d "feature/{feature_id}" 2>/dev/null
     ```

   Before applying each choice, check dependency impact: if this feature is in other features' `depends_on` lists, warn user. **On remove:** after removing a feature, scan all remaining features' `depends_on` lists for references to the removed feature. If found, offer to clean up: "Feature {remaining_id} depends on removed feature {removed_id}. Remove from depends_on?" via AskUserQuestion. If approved, update the remaining feature's `feature.yaml` to remove the dangling reference. Process features one at a time — after each action, re-read `release.yaml` and all affected features' `feature.yaml` files to refresh the incomplete features list before proceeding to the next.

5. **Complete release (atomic write):** Re-read `release.yaml` to confirm status is still `active` — if status has changed, error: "Release status changed during /release end. Another session may have modified this release." Update release.yaml in a single write: set `intake.locked: true`, `status: completed`, `completed_at: {timestamp}`, `updated_at: {timestamp}`. Note: `completed` is a terminal status — there is no `/release reopen` command. Recovery from accidental completion requires manual YAML editing. After any manual YAML edits, run `/yolo:status` to verify state consistency and refresh the state.yaml cache. **Recovery note:** If a crash occurs between step 5 and step 6, `release.yaml` will say `completed` but `state.yaml` will still say `active`. `/yolo:status` should detect this mismatch and reconcile by reading `release.yaml` as the authoritative source.

6. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set release status to `completed`, `releases[].intake.locked: true`, and `releases[].completed_at: {timestamp}` (cache of release.yaml `completed_at`) in `releases[]`. **Reconcile progress:** re-read `release.yaml` `features.total`, count completed features, update `releases[].progress.features_total`, `features_completed`, and recompute `percentage` as `features_total > 0 ? (features_completed / features_total) * 100 : 0`. **If `session.run_active` is `true`:** clear `session.run_active: false` and `session.run_started_at: null` only if `focus.release` matches this release's ID or if `session.run_started_at` is older than 2 hours (stale run from a different release). If another release owns the active run and it is recent, leave `session.run_active` unchanged and log: "Preserving run_active — owned by a different release." **Note:** `session.run_active` is global (not per-release) — care must be taken when ending one release while another has an active run. Read current `focus.release` — only clear focus if it matches this release's ID (no-op if null or different release). If clearing `focus.release`, check if `focus.feature` belongs to this release (read feature.yaml to verify `release` field matches). Only clear `focus.feature` if it does. Update `updated_at`, `session.last_action: "Release {id} completed"` and `session.resume: "Release {id} completed. Create a new release with /yolo:release new <slug>."`.

7. **Git commit:** Check `git status` for changes in `.planning/`. If changes exist, stage `.planning/` files and commit: `"chore: complete release {id}"`.

8. **Report** with summary and next steps.

---

## /release status [id]

Show release progress (read-only, no state changes).

### Process

**If no ID:** Show all releases with focused indicator (★).

```
RELEASES
─────────────────────────────
★ 2026-02-04-mvp (active) [FOCUSED]
  Progress: ████████░░ 50% (2/4 features)
  Intake: mvp-v1 (open)

○ 2026-02-10-billing (pending)
  Progress: not started
```

**If ID provided:** Show release details including goal, success criteria, feature list with statuses, intake info. Format depends on status (pending/active/completed).

---

## Notes

- Release IDs: `YYYY-MM-DD-slug`
- Intake version format: `{slug}-v{N}`
- Intake is release-scoped at `.planning/releases/{id}/intake/`
- Codebase is source of truth; intake is auxiliary context
- Features are vertical slices, not horizontal layers
- Release-level research saved to release dir — per-feature planning reuses it. Feature-level research (when release research doesn't cover the feature) is persisted to `features/{id}/research.md`
- `--prompt` instructions injected into research, goal, and feature-breakdown agents
