# YOLO Missing Features

Generated: 2026-02-05 | Context: Post-upgrade gap analysis across all layers

---

## Structural Gaps — RESOLVED

| # | Feature | Status |
|---|---------|--------|
| 1 | Adapter stubs: gitlab, linear, jira, notion | DONE — Created all 4 adapter stubs |
| 2 | Workflow: feature-resume.md | DONE — Created workflow |
| 3 | Workflow: debug-resume.md | DONE — Created workflow |
| 4 | Workflow: init.md | DONE — Created workflow |
| 5 | Workflow: feature-status.md | DONE — Created workflow, updated index.yaml routing |
| 6 | Workflow: intake-add.md | DONE — Created workflow, removed last TODO from index.yaml |
| 7 | Intake sources: gdocs, notebooklm | DONE — Added to enum across 10 files (specs, contracts, baselines, workflows, commands, generated agents) |

---

## Functional Gaps

| # | Feature | Description | Affected Area | Status |
|---|---------|-------------|---------------|--------|
| 8 | Rollback/undo | No revert mechanism when execute agent breaks mid-task. `files_changed` tracked but never used for recovery | execute pipeline | DONE — Git checkpoint before each task, surgical rollback on failure |
| 9 | Feature dependencies | Features can attach to releases but cannot depend on other features. Common need: "auth must land before permissions" | 03-features.md, feature.yaml | DONE — Cascading auto-unblock, cross-context deps, /feature:unblock command |
| 10 | Dry-run mode | No way to preview what a command would do before committing. Useful for destructive operations (release:end, feature:complete) | All write workflows | TODO |
| 11 | State backup/recovery | state.yaml has lock + checksum but no restore path if corrupted. Single point of failure for entire system | 04-state.md | DONE — Auto-backup before writes, /init --recover with backup + filesystem scan |
| 12 | Persistent retry queue | Pipeline has max_retries but no persistent queue. Context reset mid-pipeline loses all progress | orchestration/pipelines.md | DONE — Checkpoint.yaml persists after each stage, pipeline resumes from last checkpoint |
| 13 | Partial plan execution | Execute runs all tasks sequentially. No way to skip completed tasks on retry or run a subset | feature-execute.md | DONE — Checkpoint-based task skip on resume (part of #12) |

---

## Integration Gaps

| # | Feature | Description | Use Case | Status |
|---|---------|-------------|----------|--------|
| 14 | CI/CD hooks | No way to trigger verification on PR creation or report status to CI pipelines | Automated quality gates | TODO |
| 15 | Notifications | No Slack/email/webhook on release completion, feature blocking, or pipeline failure | Team awareness | TODO |
| 16 | Multi-user awareness | Lock protocol assumes single user. No conflict resolution for concurrent edits to state.yaml | Team workflows | TODO |
| 17 | External tool triggers | No inbound webhooks — can't auto-create features from GitHub issues or Jira tickets | Bidirectional sync | TODO |

---

## Quality-of-Life Gaps

| # | Feature | Description | Benefit | Status |
|---|---------|-------------|---------|--------|
| 18 | Metrics/history | No tracking of feature duration, agent success rates, pipeline performance, or cost per operation | Data-driven improvement | TODO |
| 19 | Schema migration (`yolo:migrate`) | No migration tooling when schemas evolve. Existing `.planning/` data becomes stale | Safe upgrades | TODO |
| 20 | Feature templates | Can't create features from blueprints (e.g., "new API endpoint" with pre-filled tasks and intake) | Faster feature kickoff | TODO |
| 21 | Cleanup command (`yolo:cleanup`) | No way to archive old do tasks, prune completed debug sessions, or garbage-collect orphan files | Hygiene | TODO |
| 22 | Intake versioning diff | `intake:diff` exists but no structured migration path when intake changes mid-feature | Requirement drift | TODO |
| 23 | Plan amendment | No way to modify a plan after creation without re-running plan agent from scratch | Iterative planning | DONE — /feature plan --amend with completed task preservation |
| 24 | Agent cost tracking | No per-agent token/cost tracking. Profiles control model choice but can't report actual spend | Budget management | TODO |

---

## Priority Ranking

### P0 — Blocks existing functionality — DONE
1. ~~Missing workflow files (resume, init, feature-status)~~ DONE
2. ~~Adapter stubs~~ DONE
3. ~~intake:add workflow~~ DONE
4. ~~New intake sources (gdocs, notebooklm)~~ DONE

### P1 — Safety and resilience — DONE
5. ~~Rollback/recovery for execute agent~~ DONE
6. ~~State backup + restore~~ DONE
7. ~~Persistent retry queue for pipelines~~ DONE

### P2 — Real-world project needs — DONE
8. ~~Feature-to-feature dependencies~~ DONE
9. ~~Partial plan execution / task skip on retry~~ DONE (part of P1 #12)
10. ~~Plan amendment without full re-plan~~ DONE

### P3 — Team and integration
11. CI/CD hooks
12. Notifications
13. Multi-user conflict resolution

### P4 — Polish and optimization
14. Dry-run mode
15. Schema migration tooling
16. Feature templates
17. Metrics, cost tracking, cleanup
