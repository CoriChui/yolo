# Linear Adapter

> **Status:** Stub — not yet tested against live API. Contributions welcome.

Adapter for Linear Issues using the Linear GraphQL API.

## Authentication

### Check Auth Status

```bash
# Verify API key is set
echo "${LINEAR_API_KEY:+API key is configured}"

# Test API connection
curl -s -o /dev/null -w "%{http_code}" \
  -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -d '{"query":"{ viewer { id name email } }"}'
# Expected: 200
```

**Success output (from viewer query):**
```json
{
  "data": {
    "viewer": {
      "id": "user-uuid",
      "name": "Jane Doe",
      "email": "jane@example.com"
    }
  }
}
```

### Setup Auth

1. Go to [Linear Settings > API](https://linear.app/settings/api)
2. Create a personal API key
3. Set the environment variable:

```bash
export LINEAR_API_KEY="lin_api_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Required Permissions

- Personal API key provides full access to the user's workspace
- No additional scopes needed — Linear API keys inherit the user's permissions

---

## Detect Repository

Linear is not git-remote-based. Detection uses:

```bash
# Check for LINEAR_API_KEY in environment
if [ -n "$LINEAR_API_KEY" ]; then
  echo "Linear API key detected"
fi

# Check for .linear directory or config
if [ -f ".linear/config.json" ] || [ -f ".linear.json" ]; then
  echo "Linear config detected"
fi

# Optionally extract team key from branch naming convention (e.g., TEAM-123-feature-name)
BRANCH=$(git branch --show-current 2>/dev/null)
TEAM_KEY=$(echo "$BRANCH" | sed -E 's/^([A-Z]+-[0-9]+).*/\1/' | sed -E 's/-[0-9]+$//')
echo "$TEAM_KEY"  # e.g., ENG
```

---

## Fetch Implementation

### List Issues (GraphQL)

```bash
# Fetch issues for a team
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -d '{
    "query": "query($teamKey: String!) { issues(filter: { team: { key: { eq: $teamKey } } }, first: 50) { nodes { id identifier title description state { name type } labels { nodes { name } } assignee { name displayName } priority priorityLabel project { name } createdAt updatedAt url } } }",
    "variables": { "teamKey": "ENG" }
  }'
```

### Get Single Issue

```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -d '{
    "query": "query($id: String!) { issue(id: $id) { id identifier title description state { name type } labels { nodes { name } } assignee { name displayName } priority priorityLabel project { name } createdAt updatedAt url comments { nodes { body user { name } createdAt } } } }",
    "variables": { "id": "ENG-123" }
  }'
```

### JSON Output Format

```json
{
  "data": {
    "issues": {
      "nodes": [
        {
          "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "identifier": "ENG-123",
          "title": "Login crashes on empty email",
          "description": "When submitting the login form with an empty email field...",
          "state": {
            "name": "In Progress",
            "type": "started"
          },
          "labels": {
            "nodes": [
              {"name": "Bug"},
              {"name": "auth"}
            ]
          },
          "assignee": {
            "name": "Jane Doe",
            "displayName": "Jane"
          },
          "priority": 2,
          "priorityLabel": "High",
          "project": {
            "name": "Auth Improvements"
          },
          "createdAt": "2026-02-01T10:00:00.000Z",
          "updatedAt": "2026-02-03T15:30:00.000Z",
          "url": "https://linear.app/team/issue/ENG-123"
        }
      ]
    }
  }
}
```

---

## Normalize Implementation

Convert Linear JSON to common format:

```yaml
# Input: Linear GraphQL response
# Output: Common issue format

id: "LIN#${identifier}"
tracker: linear
url: "${url}"

title: "${title}"
body: "${description}"
status: "${state.name}"                # e.g., "In Progress", "Done", "Backlog"
type: "${infer_type(labels, state)}"

labels: "${labels.nodes.map(l => l.name)}"
assignees: "${assignee ? [assignee.displayName] : []}"
milestone: "${project?.name || null}"
created_at: "${createdAt}"
updated_at: "${updatedAt}"

comments:
  - author: "${comment.user.name}"
    date: "${comment.createdAt}"
    body: "${comment.body}"

yolo_status: "${map_status(state.type)}"
suggested_yolo: "${infer_type(labels, state)}"
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
  # Linear-specific extensions of the base release_labels:
  - project
  - cycle

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

### Native Issue Type Mapping

Linear has native issue types that take precedence over label-based inference:

```yaml
# Linear native type → YOLO type
Bug: do
Feature: feature
Improvement: do
```

### Inference Logic

```python
def infer_type(labels, issue_type=None):
    # Linear native types take precedence
    if issue_type:
        native_map = {
            "Bug": "do",
            "Feature": "feature",
            "Improvement": "do",
        }
        if issue_type in native_map:
            return native_map[issue_type]

    label_names = [l["name"].lower() for l in labels.get("nodes", [])]

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

| Linear State Type | YOLO Status |
|-------------------|------------|
| triage | pending |
| backlog | pending |
| unstarted | pending |
| started | in_progress |
| completed | completed |
| cancelled | cancelled |

**Note:** Linear uses `state.type` (the workflow state category) rather than `state.name` (the custom display name) for reliable mapping. Custom state names like "In Review" or "QA" still have `type: "started"` and map to `in_progress`.

**Heuristics for blocked:** Linear has no native blocked state type. Blocked is inferred from:
- A label matching `blocked`, `on_hold`, or `waiting`
- The issue's `priority` field set to 0 (No priority) combined with a blocked label

---

## Push Implementation (Future)

### Update Issue State

```bash
# Transition to completed state
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -d '{
    "query": "mutation($id: String!, $stateId: String!) { issueUpdate(id: $id, input: { stateId: $stateId }) { success issue { identifier state { name } } } }",
    "variables": { "id": "issue-uuid", "stateId": "completed-state-uuid" }
  }'
```

### Add Comment

```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -d '{
    "query": "mutation($issueId: String!, $body: String!) { commentCreate(input: { issueId: $issueId, body: $body }) { success comment { id body } } }",
    "variables": { "issueId": "issue-uuid", "body": "Status update: completed via YOLO" }
  }'
```

### Update Labels

```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -d '{
    "query": "mutation($id: String!, $labelIds: [String!]!) { issueUpdate(id: $id, input: { labelIds: $labelIds }) { success } }",
    "variables": { "id": "issue-uuid", "labelIds": ["label-uuid-1", "label-uuid-2"] }
  }'
```

---

## Error Handling

### Auth Errors (Missing API Key)

```
Error: LINEAR_API_KEY environment variable is not set.
```

**Action:** Run `/yolo:sync setup linear` and provide API key from Linear Settings > API

### Auth Errors (Invalid API Key)

```json
{
  "errors": [
    {
      "message": "Authentication required",
      "extensions": { "code": "AUTHENTICATION_ERROR" }
    }
  ]
}
```

**Action:** Verify the API key is correct and has not been revoked

### Not Found

```json
{
  "data": {
    "issue": null
  }
}
```

**Action:** Verify the issue identifier and team key

### Rate Limit

```
HTTP 429 — Rate limit exceeded. Retry-After: 60
```

**Action:** Wait for the indicated duration. Linear allows 1,500 requests per hour for personal API keys.

### Network Error

```
Error: Could not connect to https://api.linear.app/graphql
```

**Action:** Check network connectivity and try again

---

## Example Usage

### Setup

```bash
/yolo:sync setup linear

# Output:
# Checking LINEAR_API_KEY...
# ✓ API key detected
# Verifying connection...
# ✓ Authenticated as Jane Doe (jane@example.com)
# Detecting team...
# ✓ Team: ENG (Engineering)
# Creating config...
# ✓ Setup complete
```

### Pull

```bash
/yolo:sync pull --label=bug

# Fetches all active issues with "Bug" label from the team
# Normalizes to common format
# Presents for import
```

### Pull Specific

```bash
/yolo:sync pull LIN#ENG-123

# Fetches issue ENG-123
# Shows details and suggested mapping
# Imports on confirmation
```
