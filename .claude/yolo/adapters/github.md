# GitHub Adapter

Adapter for GitHub Issues using `gh` CLI.

## Authentication

### Check Auth Status

```bash
gh auth status
```

**Success output:**
```
github.com
  ✓ Logged in to github.com as username
  ✓ Git operations for github.com configured to use https
  ✓ Token: gho_****
  ✓ Token scopes: gist, read:org, repo, workflow
```

### Setup Auth

```bash
gh auth login
```

Interactive flow:
1. Select GitHub.com or Enterprise
2. Select HTTPS or SSH
3. Authenticate via browser or token

### Required Scopes

- `repo` — Access private repositories
- `read:org` — Read org membership (for org repos)

---

## Detect Repository

Auto-detect from git remote:

```bash
# Get remote URL
REMOTE=$(git remote get-url origin 2>/dev/null)

# Extract owner/repo
# Handles: git@github.com:owner/repo.git
#          https://github.com/owner/repo.git
REPO=$(echo "$REMOTE" | sed -E 's/.*github\.com[:/]([^/]+\/[^/.]+)(\.git)?$/\1/')

echo "$REPO"  # owner/repo
```

---

## Fetch Implementation

### List Issues

```bash
# All open issues
gh issue list --repo owner/repo --state open --json number,title,labels,body,comments,state,stateReason,assignees,milestone,createdAt,updatedAt,url

# Filtered by label
gh issue list --repo owner/repo --label bug --json number,title,labels,body,comments,state,stateReason,assignees,milestone,createdAt,updatedAt,url

# Filtered by milestone
gh issue list --repo owner/repo --milestone "v1.0" --json number,title,labels,body,comments,state,stateReason,assignees,milestone,createdAt,updatedAt,url

# Limit results
gh issue list --repo owner/repo --limit 50 --json number,title,labels,body,comments,state,stateReason,assignees,milestone,createdAt,updatedAt,url
```

### Get Single Issue

```bash
gh issue view 123 --repo owner/repo --json number,title,labels,body,comments,state,stateReason,assignees,milestone,createdAt,updatedAt,url
```

### JSON Output Format

```json
{
  "number": 123,
  "title": "Login crashes on empty email",
  "state": "OPEN",
  "stateReason": "COMPLETED",
  "body": "When submitting login form...",
  "labels": [
    {"name": "bug"},
    {"name": "auth"}
  ],
  "assignees": [
    {"login": "username"}
  ],
  "milestone": {
    "title": "v1.0"
  },
  "comments": [
    {
      "author": {"login": "user1"},
      "body": "Can reproduce on Chrome",
      "createdAt": "2026-02-01T12:00:00Z"
    }
  ],
  "createdAt": "2026-02-01T10:00:00Z",
  "updatedAt": "2026-02-03T15:30:00Z",
  "url": "https://github.com/owner/repo/issues/123"
}
```

---

## Normalize Implementation

Convert GitHub JSON to common format:

```yaml
# Input: GitHub API response
# Output: Common issue format

id: "GH#${number}"
tracker: github
url: "${url}"

title: "${title}"
body: "${body}"
status: "${state.toLowerCase()}"    # OPEN → open, CLOSED → closed
type: "${infer_type(labels)}"

labels: "${labels.map(l => l.name)}"
assignees: "${assignees.map(a => a.login)}"
milestone: "${milestone?.title || null}"
created_at: "${createdAt}"
updated_at: "${updatedAt}"

comments:
  - author: "${comment.author.login}"
    date: "${comment.createdAt}"
    body: "${comment.body}"

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
  - project          # GitHub-specific extension (not in base adapter spec)

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
  # GitHub-specific extensions of the base do_labels:
  - documentation
  - refactor
  - security
  - performance
```

### Inference Logic

```python
def infer_type(labels):
    label_names = [l.name.lower() for l in labels]

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

| GitHub State | YOLO Status |
|--------------|------------|
| OPEN | pending |
| OPEN + assignee/in-progress label/draft PR | in_progress |
| CLOSED (stateReason: completed) | completed |
| CLOSED (stateReason: not_planned) | cancelled |

**Heuristics for in_progress:** GitHub lacks a native "in_progress" state. The following signals indicate an issue is actively being worked on:
- Assignee is present
- An "in progress" or "in-progress" label is applied
- A draft PR is linked to the issue

---

## Push Implementation (Future)

### Close Issue

```bash
gh issue close 123 --repo owner/repo --comment "Completed via YOLO"
```

### Add Comment

```bash
gh issue comment 123 --repo owner/repo --body "Status update: ..."
```

### Update Labels

```bash
gh issue edit 123 --repo owner/repo --add-label "done" --remove-label "in-progress"
```

---

## Error Handling

### Auth Errors

```
Error: gh: Not logged in. Run 'gh auth login' to authenticate.
```

**Action:** Run `/yolo:sync setup github` again

### Not Found

```
Error: Could not resolve to an Issue with the number of 999.
```

**Action:** Verify issue number and repository

### Rate Limit

```
Error: API rate limit exceeded
```

**Action:** Wait and retry, or authenticate for higher limits

### Permission Denied

```
Error: Resource not accessible by integration
```

**Action:** Check repository access permissions

---

## Example Usage

### Setup

```bash
/yolo:sync setup github

# Output:
# Detecting repository...
# Repository: owner/repo
# Checking authentication...
# ✓ Authenticated as username
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
/yolo:sync pull GH#123

# Fetches issue #123
# Shows details and suggested mapping
# Imports on confirmation
```
