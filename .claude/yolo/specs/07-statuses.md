# YOLO Statuses

Standardized status values across all YOLO item types.

## Overview

| Item Type | Statuses |
|-----------|----------|
| Release | `pending` → `active` → `completed` |
| Feature | `pending` → `researching` → `planning` → `in_progress` → `verifying` → `completed` |
| /do Task | `pending` → `in_progress` → `completed` / `cancelled` / `blocked` |
| Debug | `gathering` → `investigating` → `fixing` → `verifying` → `resolved` / `abandoned` |

---

## Release Statuses

```
pending → active → completed
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `pending` | Release created, intake open | Created via `/release new` |
| `active` | Work in progress | `/release start` |
| `completed` | All features completed, intake locked | `/release end` |

**Transitions:**
- `pending` → `active`: When `/release start` runs research and defines features
- `active` → `completed`: When all features verified and complete

> See Extended Release Statuses below for additional states: paused, failed, cancelled.

---

## Feature Statuses

```
pending → researching → planning → in_progress → verifying → completed
                                       ↕
                                    blocked
          pending ← planning (plan rejected)
pending/planning → dropped
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `pending` | Feature in roadmap, not started | Release creation |
| `researching` | Research agent exploring codebase | `/feature start` |
| `planning` | Creating plan from research findings | Research completes |
| `in_progress` | Executing tasks | Plan approved, execution begins |
| `blocked` | Waiting on dependency or external factor | Dependency found |
| `verifying` | Testing success criteria | All tasks done |
| `completed` | Verified, summary created | Verification passed |
| `dropped` | Abandoned, will not be completed | `/feature drop` |

**Transitions:**
- `pending` → `researching`: `/feature start`
- `researching` → `planning`: Research completes
- `planning` → `in_progress`: Plan created/approved
- `planning` → `pending`: Plan rejected by user
- `in_progress` → `verifying`: All tasks marked done
- `in_progress` → `blocked`: Dependency found
- `blocked` → `in_progress`: Unblocked
- `verifying` → `in_progress`: Verification failed (back to fix)
- `verifying` → `completed`: Verification passed
- `pending` → `dropped`: `/feature drop`
- `planning` → `dropped`: `/feature drop`

---

## /do Task Statuses

```
pending → in_progress → completed
                     ↘ cancelled
                     ↘ blocked → in_progress
                     ↘ failed
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `pending` | Task created, not started | `/yolo:do` creates task |
| `in_progress` | Actively working | Work begins |
| `blocked` | Waiting on something | External dependency |
| `completed` | All subtasks done | `/yolo:do complete` |
| `cancelled` | Abandoned | `/yolo:do cancel` |
| `failed` | Execution error, unrecoverable | Execution error |

**Transitions:**
- `pending` → `in_progress`: Start working
- `in_progress` → `blocked`: Encounter blocker
- `blocked` → `in_progress`: Blocker resolved
- `in_progress` → `completed`: All done, summary created
- `in_progress` → `cancelled`: User cancels
- `in_progress` → `failed`: Execution error
- `pending` → `cancelled`: User cancels before starting

---

## Debug Session Statuses

```
gathering → investigating → fixing → verifying → resolved
                                              ↘ abandoned
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `gathering` | Collecting symptoms | `/yolo:debug` starts |
| `investigating` | Testing hypotheses | Symptoms complete |
| `fixing` | Applying fix | Root cause found |
| `verifying` | Testing fix works | Fix applied |
| `resolved` | Issue fixed and verified | Verification passed |
| `abandoned` | Given up | `/yolo:debug abandon` |

**Transitions:**
- `gathering` → `investigating`: All symptoms collected
- `investigating` → `fixing`: Root cause confirmed
- `fixing` → `verifying`: Fix applied
- `verifying` → `investigating`: Fix didn't work (back to investigate)
- `verifying` → `resolved`: Fix verified
- Any → `abandoned`: User abandons

---

## Sync Item Statuses

For items linked to external trackers:

| YOLO Status | Maps to Tracker |
|------------|-----------------|
| `pending` | open, todo, backlog |
| `researching` | in_progress, doing |
| `planning` | in_progress, doing |
| `in_progress` | in_progress, doing, in_review |
| `verifying` | in_progress, in_review |
| `active` (release) | open, in_progress |
| `completed` | closed, done, resolved |
| `cancelled` | wontfix, cancelled |
| `blocked` | blocked (if tracker supports) |

**Conflict Resolution:** Tracker status wins. When refreshing:
- If tracker shows `closed` and YOLO shows `in_progress` → YOLO becomes `completed`

---

## Status in Files

### state.yaml

```yaml
release:
  status: active             # pending | active | paused | completed | failed | cancelled

feature:
  status: in_progress        # pending | researching | planning | in_progress | blocked | verifying | completed | dropped
```

### DO.md

```markdown
| # | Description | Started | Status | Progress |
|---|-------------|---------|--------|----------|
| 003 | Fix login | 2026-02-03 | in_progress | 2/3 |
```

### plan.md (/do task)

```markdown
**Status:** in_progress
```

### session.md (debug)

```markdown
**Current:** investigating
```

### SYNC.md

```markdown
| External | YOLO Item | YOLO Status | Tracker Status |
|----------|----------|------------|----------------|
| GH#123 | /do/008 | in_progress | open |
```

---

## Status Colors (for display)

| Status | Color | Emoji |
|--------|-------|-------|
| `pending` | gray | ⏳ |
| `planning` | blue | 📋 |
| `in_progress` | yellow | 🔄 |
| `blocked` | red | 🚫 |
| `verifying` | purple | 🔍 |
| `completed` | green | ✅ |
| `resolved` | green | ✅ |
| `cancelled` | gray | ❌ |
| `abandoned` | gray | ❌ |

---

## Extended Statuses

### Release Statuses (Extended)

| Status | Meaning | Color | Emoji |
|--------|---------|-------|-------|
| `pending` | Created, intake open | gray | ○ |
| `active` | Work in progress | blue | ● |
| `paused` | Temporarily on hold | yellow | ⏸ |
| `completed` | All features handled | green | ✓ |
| `failed` | Unrecoverable error | red | ✗ |
| `cancelled` | User abandoned | gray | ⊘ |

### Feature Statuses (Extended)

| Status | Meaning | Color | Emoji |
|--------|---------|-------|-------|
| `pending` | In roadmap | gray | ○ |
| `researching` | Research agent exploring | cyan | 🔍 |
| `planning` | Plan agent creating tasks | blue | ◐ |
| `in_progress` | Execute agent working | yellow | ● |
| `blocked` | Waiting on dependency | red | ⊘ |
| `verifying` | Verify agent checking | purple | ◑ |
| `completed` | All criteria met | green | ✓ |
| `dropped` | Removed from scope | gray | ✗ |

---

## Transition Tables

### Release Transitions

| From | To | Trigger | Guard |
|------|----|---------|-------|
| `pending` | `active` | `/release start` | goal is set |
| `pending` | `cancelled` | `/release cancel` | — |
| `active` | `completed` | `/release end` | all features handled |
| `active` | `paused` | `/release pause` | — |
| `active` | `failed` | system error | unrecoverable |
| `paused` | `active` | `/release resume` | — |
| `paused` | `cancelled` | `/release cancel` | — |
| `failed` | `cancelled` | `/release cancel` | — |

### Feature Transitions

| From | To | Trigger | Guard |
|------|----|---------|-------|
| `pending` | `researching` | `/feature start` | dependencies met |
| `pending` | `dropped` | `/feature drop` | — |
| `researching` | `planning` | research completes | findings returned |
| `planning` | `in_progress` | plan approved | tasks created |
| `planning` | `pending` | plan rejected | user rejects plan |
| `planning` | `dropped` | `/feature drop` | user decision |
| `in_progress` | `verifying` | all tasks done | tasks.completed == tasks.total |
| `in_progress` | `blocked` | dependency unmet | depends_on not completed |
| `blocked` | `in_progress` | dependency met | all depends_on completed |
| `verifying` | `completed` | verification passes | all criteria met |
| `verifying` | `in_progress` | verification fails | issues found |

### Task (/do) Transitions

| From | To | Trigger | Guard |
|------|----|---------|-------|
| `pending` | `in_progress` | `/do start` | — |
| `pending` | `cancelled` | `/do cancel` | — |
| `in_progress` | `completed` | task done | commit created |
| `in_progress` | `blocked` | blocker found | — |
| `in_progress` | `cancelled` | `/do cancel` | — |
| `in_progress` | `failed` | execution error | unrecoverable |
| `blocked` | `in_progress` | blocker resolved | — |

### Debug Session Transitions

| From | To | Trigger | Guard |
|------|----|---------|-------|
| `gathering` | `investigating` | symptoms collected | trigger + symptoms defined |
| `investigating` | `fixing` | root cause found | hypothesis confirmed |
| `investigating` | `abandoned` | cannot reproduce | user decision |
| `fixing` | `verifying` | fix applied | code changed |
| `verifying` | `resolved` | fix verified | all criteria pass |
| `verifying` | `investigating` | fix failed | regression or incomplete |
| (any) | `abandoned` | user decision | `/debug abandon` |

---

## Timestamp Requirements

Each status transition MUST record specific timestamps:

### Release Timestamps

| Transition | Records | Field |
|------------|---------|-------|
| → `pending` | Creation time | `created_at` |
| → `active` | Start time | `started_at` |
| → `paused` | Pause time | `paused_at` |
| → `completed` | Completion time | `completed_at` |
| → `failed` | Failure time | `failed_at` |
| → `cancelled` | Cancellation time | `cancelled_at` |

### Feature Timestamps

| Transition | Records | Field |
|------------|---------|-------|
| → `pending` | Creation time | `created_at` |
| → `researching` | Research start | `research_started_at` |
| → `planning` | Plan start | `planning_started_at` |
| → `in_progress` | Execution start | `started_at` |
| → `blocked` | Block time + reason | `blocked_at`, `blocked_reason` |
| → `verifying` | Verification start | `verification_started_at` |
| → `completed` | Completion time | `completed_at` |
| → `dropped` | Drop time + reason | `dropped_at`, `dropped_reason` |

---

## Blocked State Details

When an item enters `blocked`, additional context is required:

### Feature Blocked

```yaml
# feature.yaml
status: blocked
blocked:
  since: 2026-02-05T10:00:00Z
  reason: "Waiting for auth feature to complete"
  dependency: "01-auth"
  type: feature                    # feature | external | technical
```

### Task Blocked

```yaml
# In plan.md or do.yaml
status: blocked
blocked:
  since: 2026-02-05T10:00:00Z
  reason: "API endpoint not available yet"
  type: external                   # feature | external | technical
```

### Blocked Types

| Type | Meaning | Resolution |
|------|---------|------------|
| `feature` | Depends on another feature | Auto-unblocks when dependency completes |
| `external` | Waiting on external input | Manual unblock via `/feature unblock` |
| `technical` | Technical limitation | Fix underlying issue, then unblock |

---

## Recovery Actions

| Entity | Status | Recovery Action | Command |
|--------|--------|-----------------|---------|
| Release | `paused` | Resume work | `/release resume` |
| Release | `failed` | Investigate and cancel or recover | `/release recover` or `/release cancel` |
| Feature | `blocked` | Wait or force-unblock | `/feature unblock <id>` or `--force` |
| Feature | `dropped` | Create new feature (cannot un-drop) | `/feature start <similar-goal>` |
| Task | `blocked` | Resolve blocker | `/do unblock <id>` |
| Task | `failed` | Retry or cancel | `/do retry` or `/do cancel` |
| Debug | `abandoned` | Start new session | `/debug <description>` |

---

## Bidirectional Sync Mapping

### YOLO → Tracker

| YOLO Status | GitHub | Jira | Linear | GitLab |
|-------------|--------|------|--------|--------|
| `pending` | open | To Do | Todo | opened |
| `researching` | open | In Progress | In Progress | opened |
| `planning` | open | In Progress | In Progress | opened |
| `in_progress` | open | In Progress | In Progress | opened |
| `verifying` | open (in review) | In Review | In Review | opened |
| `active` | open | In Progress | In Progress | opened |
| `paused` | open (labeled) | On Hold | Paused | opened (labeled) |
| `blocked` | open (labeled) | Blocked | Blocked | opened (labeled) |
| `completed` | closed | Done | Done | closed |
| `resolved` | closed | Done | Done | closed |
| `dropped` | closed (not planned) | Won't Do | Cancelled | closed |
| `abandoned` | closed (not planned) | Won't Do | Cancelled | closed |
| `cancelled` | closed (not planned) | Cancelled | Cancelled | closed |
| `failed` | closed (not planned) | Failed | Cancelled | closed |

### Tracker → YOLO

| Tracker Status | Maps to YOLO |
|----------------|--------------|
| open, todo, new, backlog | `pending` |
| in_progress, doing, active, in_review | `in_progress` |
| blocked, on_hold, waiting | `blocked` |
| closed, done, resolved, merged | `completed` |
| wontfix, cancelled, rejected, duplicate | `cancelled` |

> **Note:** Mapping is context-dependent: for features/tasks, tracker 'active' maps to YOLO 'in_progress'; for releases, it maps to YOLO 'active'.

### Conflict Resolution

When YOLO and tracker disagree:
1. **Tracker wins** for status changes (external team may have context)
2. **YOLO wins** for metadata (descriptions, tasks, plans)
3. **User decides** for destructive conflicts (both sides changed)
