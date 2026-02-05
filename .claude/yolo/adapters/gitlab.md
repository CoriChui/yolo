# GitLab Adapter

> **Status:** Stub — not yet tested against live API. Contributions welcome.

Adapter for GitLab Issues using `glab` CLI.

## Authentication

### Check Auth Status

```bash
glab auth status
```

**Success output:**
```
gitlab.com
  - Logged in to gitlab.com as username (OAUTH_TOKEN)
  - Git operations for gitlab.com configured to use https
  - Token scopes: api
```

### Setup Auth

```bash
glab auth login
```

Interactive flow:
1. Select GitLab instance (gitlab.com or self-managed)
2. Choose authentication method (token or browser)
3. Paste personal access token or complete browser flow

### Required Scopes

- `api` — Full read/write access to the API (issues, labels, milestones, etc.)

---

## Detect Repository

Auto-detect from git remote:

```bash
# Get remote URL
REMOTE=$(git remote get-url origin 2>/dev/null)

# Extract owner/project from gitlab.com remote
# Handles: git@gitlab.com:owner/project.git
#          https://gitlab.com/owner/project.git
#          git@gitlab.com:group/subgroup/project.git
#          https://gitlab.com/group/subgroup/project.git
REPO=$(echo "$REMOTE" | sed -E 's/.*gitlab\.com[:/](.+)(\.git)?$/\1/' | sed 's/\.git$//')

echo "$REPO"  # owner/project or group/subgroup/project
```

---

## Fetch Implementation

### List Issues

```bash
# All open issues
glab issue list --repo owner/project --output-format json

# Filtered by label
glab issue list --repo owner/project --label bug --output-format json

# Filtered by milestone
glab issue list --repo owner/project --milestone "v1.0" --output-format json

# Limit results
glab issue list --repo owner/project --per-page 50 --output-format json

# Include closed issues
glab issue list --repo owner/project --all --output-format json
```

### Get Single Issue

```bash
glab issue view 123 --repo owner/project --output-format json
```

### JSON Output Format

```json
{
  "iid": 123,
  "title": "Login page returns 500 on empty password",
  "state": "opened",
  "description": "When submitting the login form with an empty password field...",
  "labels": [
    "bug",
    "auth"
  ],
  "assignees": [
    {
      "username": "jdoe",
      "name": "Jane Doe"
    }
  ],
  "milestone": {
    "title": "v1.0",
    "iid": 1
  },
  "web_url": "https://gitlab.com/owner/project/-/issues/123",
  "created_at": "2026-02-01T10:00:00.000Z",
  "updated_at": "2026-02-03T15:30:00.000Z",
  "closed_at": null
}
```

---

## Normalize Implementation

Convert GitLab JSON to common format:

```yaml
# Input: GitLab API response
# Output: Common issue format

id: "GL#${iid}"
tracker: gitlab
url: "${web_url}"

title: "${title}"
body: "${description}"
status: "${state}"                   # opened, closed
type: "${infer_type(labels)}"

labels: "${labels}"                  # already string array
assignees: "${assignees.map(a => a.username)}"
milestone: "${milestone?.title || null}"
created_at: "${created_at}"
updated_at: "${updated_at}"

comments:
  - author: "${note.author.username}"
    date: "${note.created_at}"
    body: "${note.body}"

yolo_status: "${map_status(state, assignees)}"
suggested_yolo: "${infer_type(labels)}"
```

---

## Type Mapping

### Label → Type Inference

```yaml
# Priority order (first match wins)

release_labels:
  - epic
  - initiative
  - milestone

feature_labels:
  - feature
  - enhancement
  - story
  - user-story

feature_task_labels:
  - subtask

do_labels:
  - bug
  - fix
  - hotfix
  - task
  - chore
  - improvement
  # GitLab-specific extensions of the base do_labels:
  - incident
  - service-desk
```

### Inference Logic

```python
def infer_type(labels):
    label_names = [l.lower() for l in labels]

    # Check release labels
    for label in release_labels:
        if label in label_names:
            return "release"

    # Check feature labels
    for label in feature_labels:
        if label in label_names:
            return "feature"

    # Check feature-task labels
    for label in feature_task_labels:
        if label in label_names:
            return "feature-task"

    # Check do labels
    for label in do_labels:
        if label in label_names:
            return "do"

    # Default
    return "do"
```

---

## Status Mapping

| GitLab State | YOLO Status |
|--------------|------------|
| opened | pending |
| opened + assignee | in_progress |
| closed | completed |

**Heuristics for in_progress:** GitLab issues only have two native states (`opened` and `closed`). The following signals indicate an issue is actively being worked on:
- At least one assignee is present
- A label matching `in_progress`, `doing`, or `in-progress` is applied

**Heuristics for blocked/cancelled:** GitLab has no native blocked or cancelled state. These are inferred from labels:
- Labels matching `blocked`, `on_hold`, `waiting` map to `blocked`
- Labels matching `wontfix`, `cancelled`, `rejected`, `duplicate` map to `cancelled`

---

## Push Implementation (Future)

### Close Issue

```bash
glab issue close 123 --repo owner/project --comment "Completed via YOLO"
```

### Add Comment (Note)

```bash
glab issue note 123 --repo owner/project --message "Status update: ..."
```

### Update Labels

```bash
glab issue update 123 --repo owner/project --label "done" --unlabel "in-progress"
```

### Reopen Issue

```bash
glab issue reopen 123 --repo owner/project
```

---

## Error Handling

### Auth Errors

```
Error: glab: authentication required. Run 'glab auth login' to authenticate.
```

**Action:** Run `/yolo:sync setup gitlab` again

### Not Found

```
Error: GET https://gitlab.com/api/v4/projects/owner%2Fproject/issues/999: 404 Not Found
```

**Action:** Verify issue IID and project path

### Rate Limit

```
Error: 429 Too Many Requests — Rate limit exceeded. Retry after 60 seconds.
```

**Action:** Wait for the indicated duration and retry

### Permission Denied

```
Error: GET https://gitlab.com/api/v4/projects/owner%2Fproject/issues: 403 Forbidden
```

**Action:** Check project visibility and token scopes. Ensure the `api` scope is granted.

---

## Example Usage

### Setup

```bash
/yolo:sync setup gitlab

# Output:
# Detecting repository...
# Repository: owner/project
# Checking authentication...
# ✓ Authenticated as jdoe on gitlab.com
# Creating config...
# ✓ Setup complete
```

### Pull

```bash
/yolo:sync pull --label=bug

# Fetches all open issues with "bug" label
# Normalizes to common format
# Presents for import
```

### Pull Specific

```bash
/yolo:sync pull GL#123

# Fetches issue #123
# Shows details and suggested mapping
# Imports on confirmation
```
