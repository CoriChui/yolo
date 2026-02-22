# Status Workflow
# Command: /status

Show overall project status (read-only, no state changes).

---

## /status

### Process

1. **Load state.yaml:** Focus, releases, current feature, session info.

2. **Display:**

```
PROJECT STATUS
─────────────────────────────────────
RELEASES ({count})
  ★ 2026-02-04-mvp (active) [FOCUSED]
    Progress: ████████░░ 50% (2/4 features)
    Intake: mvp-v1 (open)

  ○ 2026-02-10-mobile (pending)
    Progress: not started

CURRENT FEATURE
  03-billing (in_progress) — Release: 2026-02-04-mvp
  Tasks: ████░░░░░░ 33% (2/6)
  Current: "Implement payment acceptance"

NEXT ACTION:
  {suggested action based on state}
─────────────────────────────────────
```

3. **Get current feature status:** If `focus.feature` is set, read the feature's `feature.yaml` directly to get current status.

4. **Suggest next action:**

| Condition | Suggested Action |
|-----------|------------------|
| Feature status == researching | Wait for research or restart `/yolo:feature start` |
| Feature status == planning | `/yolo:feature plan` |
| Feature status == in_progress | `/yolo:feature start` (auto-resumes from last phase) |
| Feature status == verifying | `/yolo:feature verify` |
| All features complete | `/yolo:release end` |
| No current feature | `/yolo:feature start <id>` |
| No releases | `/yolo:release new <name>` |

### Special States

- **No `.planning/`:** Show "No project found" with `/yolo:init` suggestion.
- **No releases:** Show empty releases with `/yolo:release new` suggestion.

---

## Notes

- Indicators: ★ focused, ● active, ○ pending
- Status provides orientation after context resets
