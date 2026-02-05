# Adapter Specification

> **Adapter Status:**
> - **Implemented:** GitHub (`github.md`)
> - **Planned:** GitLab (`gitlab.md`), Linear (`linear.md`), Jira (`jira.md`), Notion (`notion.md`)

Base specification for tracker adapters. Each adapter must implement these operations.

## Adapter Interface

Every adapter must handle:

1. **Authentication** — Setup and verify credentials
2. **Fetch** — Get issues from tracker
3. **Normalize** — Convert to common format
4. **Push** — Update tracker (future)

---

## Common Issue Format

All adapters normalize issues to this format:

```yaml
id: "GH#123"                       # Tracker-prefixed ID
tracker: github                    # Tracker name
url: "https://..."                 # Direct link to issue

# Core fields
title: "Issue title"
body: "Issue description..."
status: open                       # Tracker-native value (e.g. open, closed, in_progress)
type: bug                          # Inferred from labels/type

# Metadata
labels: [bug, auth, critical]
assignees: [user1, user2]
milestone: "v1.0"
created_at: "2026-02-01T10:00:00Z"
updated_at: "2026-02-03T15:30:00Z"

# Comments (imported for context)
comments:
  - author: "username"
    date: "2026-02-01T12:00:00Z"
    body: "Comment text..."

# YOLO mapping
yolo_status: pending                # Mapped from `status` via Status Mapping table below
suggested_yolo: do                  # do | feature | release | feature-task
```

---

## Type Inference Rules

Adapters infer YOLO type from labels/issue-type:

```yaml
# Labels that map to release
release_labels:
  - epic
  - initiative
  - milestone

# Labels that map to feature
feature_labels:
  - feature
  - story
  - user-story
  - enhancement

# Labels that map to feature-task
feature_task_labels:
  - subtask

# Labels that map to /do task
do_labels:
  - bug
  - fix
  - hotfix
  - task
  - chore
  - improvement

# Default if no match
default: do
```

**Priority:** release > feature > feature-task > do

---

## Adapter File Structure

```markdown
# {Tracker} Adapter

## Authentication

[How to authenticate]

## CLI/API Reference

[Commands or API endpoints used]

## Fetch Implementation

[How to fetch issues]

## Normalize Implementation

<!-- Convert tracker-specific format to the Common Issue Format defined above. -->
[How to convert to common format]

## Type Mapping

[Tracker-specific type inference]

## Push Implementation (Future)

[How to update tracker]
```

---

## Status Mapping

| Tracker Status | YOLO Status |
|----------------|------------|
| open, todo, new, backlog | pending |
| in_progress, doing, active, in_review | in_progress |
| blocked, on_hold, waiting | blocked |
| closed, done, resolved, merged | completed |
| wontfix, cancelled, rejected, duplicate | cancelled |

---

## Error Handling

Adapters should handle:

1. **Auth failure** — Clear message with setup instructions
2. **Network error** — Retry suggestion
3. **Rate limit** — Wait and retry
4. **Not found** — Clear message
5. **Permission denied** — Check access instructions

---

## Creating a New Adapter

1. Copy this template to `.claude/yolo/adapters/{tracker}.md`
2. Implement authentication section
3. Implement fetch commands/API calls
4. Define type mapping for tracker-specific labels
5. Test with `/yolo:sync setup {tracker}`
