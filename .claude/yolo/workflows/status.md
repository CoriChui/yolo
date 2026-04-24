# Status Workflow
# Command: /yolo:status

Show overall project status. Performs state.yaml reconciliation when mismatches with release.yaml are detected.

---

## /status

### Process

1. **Load state.yaml:** Focus, releases, current feature, session info. **Fallback:** If `workspace/` exists but `state.yaml` is missing or corrupt, scan `workspace/releases/` directories and read each `release.yaml` directly to build the releases list. **Also read feature.yaml files:** For each release directory found, scan `features/` subdirectory and read each feature's `feature.yaml` to include feature-level progress (status, tasks completed/total, current task) in the fallback display. Display available information with a warning: "state.yaml is missing or corrupt — showing data from release.yaml and feature.yaml files. Run `/yolo:init` to repair."

2. **Reconcile state.yaml against release.yaml (crash recovery):**
   **Re-read state.yaml** to get current values before writing corrections (TOCTOU guard).
   For each entry in `releases[]`:
   - Read the corresponding `release.yaml` at `workspace/releases/{id}/release.yaml`
   - Compare `releases[].status` (state.yaml cache) with `release.yaml` `status` (authoritative)
   - If mismatch: update `releases[].status` in state.yaml to match `release.yaml`
   - Compare `releases[].progress` against `release.yaml` `features.total` and count of completed features
   - If mismatch: update `releases[].progress.features_total`, `features_completed`, and recompute `percentage`
   - Compare `releases[].intake.locked` and `releases[].intake.current` against `release.yaml` `intake.locked` and `intake.current`
   - If mismatch: update `releases[].intake` in state.yaml to match `release.yaml`
   - **Feature-level reconciliation:** If `focus.feature` is set, verify the feature directory and `feature.yaml` exist. If the feature directory is missing, clear `focus.feature: null` and log correction. If `feature.yaml` exists, read its `status` — no status correction is made (feature.yaml is authoritative and `/status` is not the owner of feature status transitions), but if the feature status is a terminal state (`completed`) and `focus.feature` still points to it, clear `focus.feature: null` (stale focus from a completed feature that wasn't properly cleaned up).
   - **Release-level stuck state detection:** For **pending releases**, check for signs of interrupted `/release start`: if `research.md` exists in the release directory but status is still `pending`, log warning: "Release {id} appears to have an interrupted /release start (research.md exists but status is pending). Resume with `/yolo:release start {id}`." Display stuck releases in the status output under a "WARNINGS" section.
   - **Release-wide feature scan:** For **all active releases** (not just the focused one), scan all features in `features.list`. For each feature in a non-terminal intermediate state (`researching`, `planning`, `in_progress`, `verifying`, `hook_gate_failed`, `verify_failed`), read its `feature.yaml` and check `updated_at`. If `updated_at` is older than 2 hours, log warning: "Feature {id} (release: {release_id}) may be stuck in '{status}' since {updated_at}." **Planning-specific heuristic:** If status is `planning`, also check whether `plan.md` exists in the feature directory. If `plan.md` exists, the feature may be awaiting user review (not stuck) — append to warning: "(plan.md exists — may be awaiting review)". If `plan.md` is missing, the plan agent likely crashed — append: "(no plan.md — plan agent may have crashed. Resume with `/yolo:feature start <id>`)." **Additional heuristics for recently-updated-but-crashed features:** Check for existing worktrees at the expected path (`../.${REPO_NAME}-worktrees/${feature_id}`) — if the worktree directory is missing but status is an active state (`researching`, `planning`, `in_progress`, `verifying`), warn: "Feature {id} has no worktree but is in '{status}' — likely crashed." Also check for stale `.task-locks/` files in the worktree (if it exists) — lock files without corresponding `completed_ids` entries indicate mid-task crashes. If `session.run_active` is `true` but `focus.feature` does not match this feature, check if the feature's `updated_at` advanced after `session.run_started_at` — this indicates the run progressed past this feature and it may be stuck from an earlier iteration. Display stuck features in the status output under a "WARNINGS" section.
   - If any corrections were made: update `state.yaml` `updated_at` and log: "Reconciled state.yaml: {list of corrections}". **Git commit:** Check `git status` for changes in `workspace/`. If changes exist, stage `workspace/` files and commit: `"chore: reconcile state.yaml"`.

3. **Display:**

```
PROJECT STATUS
─────────────────────────────────────
RELEASES ({count})
  ★ 2026-02-04-mvp (active) [FOCUSED]
    Progress: ████████░░ 50% (2/4 features)
    Intake: mvp-v1 (open)

  ● 2026-02-10-mobile (active)
    Progress: ██░░░░░░░░ 20% (1/5 features)
    Intake: mobile-v1 (locked)

  ○ 2026-02-15-billing (pending)
    Progress: not started

CURRENT FEATURE
  03-billing (in_progress) — Release: 2026-02-04-mvp
  Tasks: ████░░░░░░ 33% (2/6)
  Current: "Implement payment acceptance"

NEXT ACTION:
  {suggested action based on state}
─────────────────────────────────────
```

4. **Get current feature status:** If `focus.feature` is set, check that the feature directory and `feature.yaml` exist. If not found, display "Focused feature {id} not found (may have been removed)" and suggest running `/yolo:feature start` or clearing focus. If found, read `feature.yaml` directly to get current status.

5. **Suggest next action:**

| Condition | Suggested Action |
|-----------|------------------|
| Feature status == pending | `/yolo:feature start <id>` to begin pipeline (check `depends_on` — show unmet dependencies if any) |
| Feature status == researching | Feature may be stuck (previous run interrupted). Run `/yolo:feature start <id>` to resume |
| Feature status == planning | Review `plan.md` or re-run `/yolo:feature start <id>` to resume |
| Feature status == in_progress | `/yolo:feature start` (auto-resumes from last phase) |
| Feature status == verifying | `/yolo:feature verify` |
| Feature status == hook_gate_failed | Fix issues, then `/yolo:feature start <id>` |
| Feature status == verify_failed | Fix issues, then `/yolo:feature start <id>` |
| All features complete | `/yolo:release end` |
| No current feature | `/yolo:feature start <id>` |
| No releases | `/yolo:release new <name>` |

### Special States

- **No `workspace/`:** Show "No project found" with `/yolo:init` suggestion.
- **No releases:** Show empty releases with `/yolo:release new` suggestion.
- **`run_active: true` with no `focus.feature`:** Show "⚠ Release run may have been interrupted — `run_active` is set (since {run_started_at}) but no feature is focused. Resume with `/yolo:release run` or clear with `/yolo:release end`."
- **`run_active: true` with `focus.feature`:** Display `run_started_at` in the status output: "Release run in progress (since {run_started_at})"

---

## Notes

- Indicators: ★ focused, ● active, ○ pending, ✓ completed
- Status provides orientation after context resets
