# Release Workflow
# Commands: /release new, /release start, /release run, /release end, /release status

Read `.planning/state.yaml` before any operation. Validate it exists and is valid YAML — if missing, error: "Run `/yolo:init` first."
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

6. **Update state.yaml:** Read current `focus.release` — if another release is already focused, warn user and confirm before switching. Then add to `releases[]`, set `focus.release`, update `updated_at`, `session.last_action` and `session.resume`.

7. **Report** with next steps: `/yolo:intake capture`, `/yolo:release start`.

---

## /release start [id] [--prompt "<text>"]

Activate a pending release: research codebase, define goal, create features.

### Process

1. **Resolve release:** Use arg or `focus.release`. Must be `pending`.

2. **Read intake:** Load manifest, digests, `requirements.yaml`, `conflicts.yaml` from intake directory.

3. **Spawn research agent** (model from `config.yaml` `agents.research`):
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

5. **Save research:** Write `research.md` to release directory.

6. **Define release goal:** Based on research + intake + user prompt, draft goal, title, and success criteria. Present to user for approval via AskUserQuestion. If rejected, revise based on feedback and re-present. Write approved title to `release.yaml`.

7. **Resolve open questions:** If research produced blocking questions, present each to user via AskUserQuestion. Record answers.

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

   Additional inputs: release_goal (from step 6), max_features (from `config.yaml` `limits.max_features_per_release`, default 12). If `--prompt`: inject as constraints.

   Read `.claude/yolo/agents/feature-breakdown.md` for agent instructions.

   Output: features[] with id, name, title, goal, success_criteria, scope, depends_on, estimated_tasks, services_touched, domain_entities (optional), business_rules (optional)

9. **Validate features:**
   - success_criteria: 3–8 per feature
   - services_touched: max 2
   - estimated_tasks: within `config.yaml` `limits.estimated_tasks_range` (default 2–8)
   - scope.directories: max 8
   - Dependency fanout: no feature depended on by >3 others
   - At least 2 features at level 1 (if total > 4) — **soft warning**: if violated, warn user about reduced parallelism but allow proceeding via AskUserQuestion confirmation
   - No circular dependencies in dependency graph — verify by topological sort: build adjacency list from `depends_on`, visit each feature tracking "in-progress" and "visited" sets; if a feature is reached while already "in-progress", a cycle exists. Report the cycle path and reject.

10. **Present breakdown to user** with dependency graph. Wait for approval.

11. **Create feature directories:** For each feature, create `{id}-{name}/feature.yaml` in release `features/` dir with all fields from breakdown output, including `domain_entities` and `business_rules` if provided by the feature-breakdown agent. **Initialize fields:** Set `status: pending`, `started_at: null`, `completed_at: null`, `updated_at: {timestamp}`, `tasks: { total: 0, completed: 0, current: null }`.

12. **Write requirements.md:** Release goal + success criteria + per-feature requirements.

13. **Update release.yaml:** Set `status: active`, `started_at`, `updated_at`, populate `features.list`.

14. **Update state.yaml:** Set release `status: active`, update progress, update `updated_at`, `session.last_action` and `session.resume`.

15. **Report** with next steps: `/yolo:feature start 01`.

---

## /release run [id] [--from <feature-id>]

Run all pending features sequentially through the full pipeline (`/yolo:feature start`).

### Process

1. **Resolve release:** Use arg or `focus.release`. Must be `active`.

2. **If `--from <id>`:** Note starting point.

3. **Feature loop** (re-evaluate after each completion):

   a. **Build/refresh queue:** Read `features.list` from release.yaml. **Guard against external modifications:** If this is not the first iteration, compare `features.list` with the previous iteration's list — if features were added, removed, or reordered, warn user: "features.list was modified externally. Continue with updated list?" via AskUserQuestion. If rejected, stop run. Filter to features where `status` is not `completed`. Validate no circular dependencies exist — build adjacency list from `depends_on`, verify DAG (if cycle found, report cycle path and stop run with error). Sort by topological order (features whose `depends_on` are all `completed` come first; among equal candidates, sort by ID ascending). If `--from`: skip features before that ID.

   b. **Pick next:** Take first feature from queue where all `depends_on` are `completed`. Re-read `release.yaml` to confirm release is still `active`, re-read `state.yaml` to confirm `focus.release` still matches the release being run, and re-read the candidate's `feature.yaml` to confirm dependencies are still met before proceeding. If release is no longer active, focus changed, or no eligible feature remains, exit loop. Note: `/release run` assumes single-user, single-session operation.

   c. **Run pipeline:** Invoke `/yolo:feature start {id}` via Skill tool. If Skill tool invocation itself fails (not the feature), retry once. If still failing, stop run with error report and suggest running `/yolo:feature start {id}` manually.

   d. **On success:** Feature completes normally. Loop back to step (a) to re-evaluate queue.

   e. **On failure:** Record the failed feature. Check if other independent features remain eligible (i.e., non-completed features whose `depends_on` are all `completed` — not depending on the failed feature). If eligible features exist, loop back to step (a) to continue with them. If no eligible features remain, stop the run. Report:
      ```
      RUN STOPPED
      ─────────────────────────────
      Failed features: {list of failed ids with names}
      Completed: {N}/{total} features this run
      Skipped:   {features that were pending but depend on failed features}

      Retry:   /yolo:feature start {id}
      Resume:  /yolo:release run
      ```

4. **On all features complete:** Report summary. If failed features remain, list them with suggested actions (`/yolo:feature start {id}` to retry). If all features completed, suggest `/yolo:release end`.

---

## /release end [id]

Complete an active release.

### Process

1. **Resolve release:** Use arg or `focus.release`. Must be `active`.

2. **Find incomplete features:** List all features with `status != completed`.

3. **If no incomplete features:** Skip to step 4.

4. **Per incomplete feature, ask user:**
   - **Complete now** — only allowed if feature status is `verifying`, or `in_progress` with `tasks.completed == tasks.total` (must have finished all tasks). If status is `in_progress` and `tasks.completed < tasks.total`, reject with error: "Feature has incomplete tasks ({tasks.completed}/{tasks.total}). Complete tasks first or choose Remove instead." If status is `verifying`, check whether `verification.md` exists and contains no blocker failures — if blockers exist, reject with error: "Feature has unresolved verification blockers. Fix blockers and re-run `/yolo:feature start <id>`, or choose Remove instead." Set `status: completed`, `completed_at: {timestamp}`, `updated_at: {timestamp}` in feature.yaml (warn user: skips full verification, no new verification.md will be created).
   - **Remove** — allowed for any incomplete feature. Delete the feature directory and remove from `features.list` in release.yaml. Update `features.total`. Clean up worktree if one exists.

   Before applying each choice, check dependency impact: if this feature is in other features' `depends_on` lists, warn user. Process features one at a time — after each action, re-read `release.yaml` and all affected features' `feature.yaml` files to refresh the incomplete features list before proceeding to the next.

5. **Lock intake:** Set `intake.locked: true`, `updated_at` in release.yaml.

6. **Update release.yaml:** Set `status: completed`, `completed_at`, `updated_at`.

7. **Update state.yaml:** Set release status to `completed` in `releases[]`. Read current `focus.release` — only clear focus if it matches this release's ID (no-op if null or different release). If clearing `focus.release`, also clear `focus.feature`. Update `updated_at`, `session.last_action` and `session.resume`.

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
- Research saved to release dir — per-feature planning reuses it
- `--prompt` instructions injected into research, goal, and feature-breakdown agents
