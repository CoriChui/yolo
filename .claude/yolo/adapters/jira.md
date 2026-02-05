# Jira Adapter

> **Status:** Stub — not yet tested against live API. Contributions welcome.

Adapter for Jira Issues using the Jira REST API v3.

## Authentication

### Check Auth Status

```bash
# Verify environment variables are set
echo "JIRA_BASE_URL: ${JIRA_BASE_URL:+configured}"
echo "JIRA_EMAIL: ${JIRA_EMAIL:+configured}"
echo "JIRA_API_TOKEN: ${JIRA_API_TOKEN:+configured}"

# Test API connection
curl -s -o /dev/null -w "%{http_code}" \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_BASE_URL}/rest/api/3/myself"
# Expected: 200
```

**Success output (from myself endpoint):**
```json
{
  "accountId": "5a1234b5c6d7e8f9a0b1c2d3",
  "displayName": "Jane Doe",
  "emailAddress": "jane@example.com",
  "active": true
}
```

### Setup Auth

1. Go to [Atlassian API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Click "Create API token"
3. Set the environment variables:

```bash
export JIRA_BASE_URL="https://your-domain.atlassian.net"
export JIRA_EMAIL="jane@example.com"
export JIRA_API_TOKEN="ATATT3xFfGF0..."
```

### Required Permissions

- The user account must have **Browse projects** permission for the target project
- For push operations (future): **Edit issues**, **Transition issues**, **Add comments**

---

## Detect Repository

Jira is not git-remote-based. Detection uses environment variables:

```bash
# Check for required environment variables
if [ -n "$JIRA_BASE_URL" ] && [ -n "$JIRA_EMAIL" ] && [ -n "$JIRA_API_TOKEN" ]; then
  echo "Jira credentials detected"
fi

# Optionally extract project key from branch naming convention (e.g., PROJ-123-feature-name)
BRANCH=$(git branch --show-current 2>/dev/null)
PROJECT_KEY=$(echo "$BRANCH" | sed -E 's/^([A-Z]+)-[0-9]+.*/\1/')
echo "$PROJECT_KEY"  # e.g., PROJ
```

---

## Fetch Implementation

### List Issues (JQL Search)

```bash
# All open issues for a project
curl -s \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/search?jql=project%3DPROJ%20AND%20status%20!%3D%20Done&maxResults=50&fields=key,summary,description,status,issuetype,labels,assignee,priority,created,updated,comment"

# Filtered by issue type
curl -s \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_BASE_URL}/rest/api/3/search?jql=project%3DPROJ%20AND%20issuetype%3DBug&fields=key,summary,description,status,issuetype,labels,assignee,priority,created,updated,comment"

# Filtered by label
curl -s \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_BASE_URL}/rest/api/3/search?jql=project%3DPROJ%20AND%20labels%3Dauth&fields=key,summary,description,status,issuetype,labels,assignee,priority,created,updated,comment"
```

### Get Single Issue

```bash
curl -s \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/issue/PROJ-123?fields=key,summary,description,status,issuetype,labels,assignee,priority,created,updated,comment"
```

### JSON Output Format

```json
{
  "key": "PROJ-123",
  "fields": {
    "summary": "Login crashes on empty email",
    "description": {
      "type": "doc",
      "version": 1,
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "When submitting the login form with an empty email field..." }
          ]
        }
      ]
    },
    "status": {
      "name": "In Progress",
      "statusCategory": {
        "key": "indeterminate",
        "name": "In Progress"
      }
    },
    "issuetype": {
      "name": "Bug",
      "subtask": false
    },
    "labels": ["auth", "critical"],
    "assignee": {
      "displayName": "Jane Doe",
      "accountId": "5a1234b5c6d7e8f9a0b1c2d3"
    },
    "priority": {
      "name": "High"
    },
    "created": "2026-02-01T10:00:00.000+0000",
    "updated": "2026-02-03T15:30:00.000+0000",
    "comment": {
      "comments": [
        {
          "author": {
            "displayName": "John Smith",
            "accountId": "5b9876c5d4e3f2a1b0c9d8e7"
          },
          "body": {
            "type": "doc",
            "version": 1,
            "content": [
              {
                "type": "paragraph",
                "content": [
                  { "type": "text", "text": "Can reproduce on Chrome" }
                ]
              }
            ]
          },
          "created": "2026-02-01T12:00:00.000+0000"
        }
      ]
    }
  }
}
```

**Note:** Jira v3 uses Atlassian Document Format (ADF) for `description` and `comment.body`. The adapter must extract plain text from ADF nodes recursively.

---

## Normalize Implementation

Convert Jira JSON to common format:

```yaml
# Input: Jira REST API response
# Output: Common issue format

id: "JIRA#${key}"
tracker: jira
url: "${JIRA_BASE_URL}/browse/${key}"

title: "${fields.summary}"
body: "${extract_text(fields.description)}"     # Flatten ADF to plain text
status: "${fields.status.name}"                 # e.g., "In Progress", "To Do"
type: "${infer_type(fields.issuetype, fields.labels)}"

labels: "${fields.labels}"                      # already string array
assignees: "${fields.assignee ? [fields.assignee.displayName] : []}"
milestone: null                                 # Jira uses fixVersions instead
created_at: "${fields.created}"
updated_at: "${fields.updated}"

comments:
  - author: "${comment.author.displayName}"
    date: "${comment.created}"
    body: "${extract_text(comment.body)}"        # Flatten ADF to plain text

yolo_status: "${map_status(fields.status.statusCategory.key, fields.status.name)}"
suggested_yolo: "${infer_type(fields.issuetype, fields.labels)}"
```

---

## Type Mapping

### Native Issue Type Mapping

Jira has native issue types that take precedence over label-based inference:

```yaml
# Jira issue type → YOLO type (primary mapping)
Epic: release
Story: feature
Sub-task: feature-task
Bug: do
Task: do
Improvement: do
```

### Label → Type Inference (Fallback)

When the native issue type is not conclusive (e.g., custom types), fall back to label-based inference:

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
```

### Inference Logic

```python
def infer_type(issuetype, labels):
    # Jira native issue types take precedence
    native_map = {
        "Epic": "release",
        "Story": "feature",
        "Sub-task": "feature-task",
        "Bug": "do",
        "Task": "do",
        "Improvement": "do",
    }
    type_name = issuetype.get("name", "")
    if type_name in native_map:
        return native_map[type_name]

    # Sub-task flag overrides
    if issuetype.get("subtask"):
        return "feature-task"

    # Fallback to label-based inference
    label_names = [l.lower() for l in labels]

    for label in release_labels:
        if label in label_names:
            return "release"

    for label in feature_labels:
        if label in label_names:
            return "feature"

    for label in feature_task_labels:
        if label in label_names:
            return "feature-task"

    for label in do_labels:
        if label in label_names:
            return "do"

    # Default
    return "do"
```

---

## Status Mapping

### Primary: Status Category Mapping

| Jira Status Category | YOLO Status |
|----------------------|------------|
| new (To Do) | pending |
| indeterminate (In Progress) | in_progress |
| done (Done) | completed |

### Secondary: Status Name Overrides

Certain status names override the category-based mapping:

| Jira Status Name | YOLO Status |
|------------------|------------|
| Blocked | blocked |
| On Hold | blocked |
| Waiting for Customer | blocked |
| Won't Do | cancelled |
| Won't Fix | cancelled |
| Rejected | cancelled |
| Duplicate | cancelled |

### Mapping Logic

```python
def map_status(status_category_key, status_name):
    # Status name overrides take priority
    name_lower = status_name.lower()
    blocked_names = ["blocked", "on hold", "waiting for customer", "waiting"]
    cancelled_names = ["won't do", "won't fix", "rejected", "duplicate", "cancelled"]

    if name_lower in blocked_names:
        return "blocked"
    if name_lower in cancelled_names:
        return "cancelled"

    # Fall back to category-based mapping
    category_map = {
        "new": "pending",
        "indeterminate": "in_progress",
        "done": "completed",
    }
    return category_map.get(status_category_key, "pending")
```

---

## Push Implementation (Future)

### Transition Issue (Change Status)

```bash
# First, get available transitions
curl -s \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_BASE_URL}/rest/api/3/issue/PROJ-123/transitions"

# Then perform the transition
curl -s -X POST \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/issue/PROJ-123/transitions" \
  -d '{
    "transition": { "id": "31" },
    "update": {
      "comment": [
        {
          "add": {
            "body": {
              "type": "doc",
              "version": 1,
              "content": [
                {
                  "type": "paragraph",
                  "content": [
                    { "type": "text", "text": "Completed via YOLO" }
                  ]
                }
              ]
            }
          }
        }
      ]
    }
  }'
```

### Add Comment

```bash
curl -s -X POST \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/issue/PROJ-123/comment" \
  -d '{
    "body": {
      "type": "doc",
      "version": 1,
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Status update: in progress" }
          ]
        }
      ]
    }
  }'
```

### Update Labels

```bash
curl -s -X PUT \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/issue/PROJ-123" \
  -d '{
    "update": {
      "labels": [
        { "add": "done" },
        { "remove": "in-progress" }
      ]
    }
  }'
```

---

## Error Handling

### Auth Errors (Missing Credentials)

```
Error: JIRA_BASE_URL, JIRA_EMAIL, or JIRA_API_TOKEN environment variable is not set.
```

**Action:** Run `/yolo:sync setup jira` and provide all required environment variables

### Auth Errors (401 Unauthorized)

```json
{
  "errorMessages": ["You do not have the permission to see the specified issue."],
  "errors": {}
}
```

**Action:** Verify email and API token. Regenerate token from Atlassian account settings.

### Not Found (404)

```json
{
  "errorMessages": ["Issue does not exist or you do not have permission to see it."],
  "errors": {}
}
```

**Action:** Verify the issue key and project permissions

### Permission Denied (403)

```json
{
  "errorMessages": ["You do not have the permission to see the specified issue."],
  "errors": {}
}
```

**Action:** Contact project admin to grant Browse Projects permission

### Rate Limit (429)

```
HTTP 429 — Rate limit exceeded.
Retry-After: 30
```

**Action:** Wait for the indicated duration. Jira Cloud allows approximately 100 requests per minute for basic auth.

---

## Example Usage

### Setup

```bash
/yolo:sync setup jira

# Output:
# Checking environment variables...
# ✓ JIRA_BASE_URL: https://your-domain.atlassian.net
# ✓ JIRA_EMAIL: configured
# ✓ JIRA_API_TOKEN: configured
# Verifying connection...
# ✓ Authenticated as Jane Doe (jane@example.com)
# Detecting project...
# ✓ Project: PROJ (My Project)
# Creating config...
# ✓ Setup complete
```

### Pull

```bash
/yolo:sync pull --label=bug

# Fetches all open issues with "bug" label from the project
# Normalizes to common format
# Presents for import
```

### Pull Specific

```bash
/yolo:sync pull JIRA#PROJ-123

# Fetches issue PROJ-123
# Shows details and suggested mapping
# Imports on confirmation
```
