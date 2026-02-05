# Notion Adapter

> **Status:** Stub — not yet tested against live API. Contributions welcome.

Adapter for Notion Database items using the Notion API.

## Authentication

### Check Auth Status

```bash
# Verify environment variables are set
echo "NOTION_API_KEY: ${NOTION_API_KEY:+configured}"
echo "NOTION_DATABASE_ID: ${NOTION_DATABASE_ID:+configured}"

# Test API connection
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  "https://api.notion.com/v1/users/me"
# Expected: 200
```

**Success output (from users/me endpoint):**
```json
{
  "object": "user",
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "type": "bot",
  "bot": {
    "owner": {
      "type": "workspace",
      "workspace": true
    },
    "workspace_name": "My Workspace"
  }
}
```

### Setup Auth

1. Go to [Notion Integrations](https://www.notion.so/my-integrations)
2. Create a new internal integration
3. Copy the integration token
4. Share the target database with the integration (click "..." on the database, then "Add connections")
5. Set the environment variables:

```bash
export NOTION_API_KEY="ntn_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export NOTION_DATABASE_ID="a1b2c3d4e5f67890abcdef1234567890"
```

### Required Permissions

- Integration must have **Read content** capability
- For push operations (future): **Update content** and **Insert content** capabilities
- The target database must be explicitly shared with the integration

---

## Detect Repository

Notion is not git-remote-based. Detection uses environment variables:

```bash
# Check for required environment variables
if [ -n "$NOTION_API_KEY" ] && [ -n "$NOTION_DATABASE_ID" ]; then
  echo "Notion credentials detected"
fi

# Validate database is accessible
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  "https://api.notion.com/v1/databases/${NOTION_DATABASE_ID}"
# Expected: 200
```

---

## Fetch Implementation

### List Issues (Database Query)

```bash
# All items (no filter)
curl -s -X POST \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  "https://api.notion.com/v1/databases/${NOTION_DATABASE_ID}/query" \
  -d '{}'

# Filtered by status (not done)
curl -s -X POST \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  "https://api.notion.com/v1/databases/${NOTION_DATABASE_ID}/query" \
  -d '{
    "filter": {
      "property": "Status",
      "status": {
        "does_not_equal": "Done"
      }
    }
  }'

# Filtered by tag
curl -s -X POST \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  "https://api.notion.com/v1/databases/${NOTION_DATABASE_ID}/query" \
  -d '{
    "filter": {
      "property": "Tags",
      "multi_select": {
        "contains": "bug"
      }
    },
    "page_size": 50
  }'
```

### Get Single Page

```bash
curl -s \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  "https://api.notion.com/v1/pages/a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

### JSON Output Format

```json
{
  "results": [
    {
      "object": "page",
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "created_time": "2026-02-01T10:00:00.000Z",
      "last_edited_time": "2026-02-03T15:30:00.000Z",
      "url": "https://www.notion.so/Login-crashes-on-empty-email-a1b2c3d4e5f67890abcdef1234567890",
      "properties": {
        "Name": {
          "id": "title",
          "type": "title",
          "title": [
            {
              "type": "text",
              "text": { "content": "Login crashes on empty email" },
              "plain_text": "Login crashes on empty email"
            }
          ]
        },
        "Status": {
          "id": "status-id",
          "type": "status",
          "status": {
            "name": "In progress",
            "color": "blue"
          }
        },
        "Tags": {
          "id": "tags-id",
          "type": "multi_select",
          "multi_select": [
            { "name": "bug", "color": "red" },
            { "name": "auth", "color": "blue" }
          ]
        },
        "Assignee": {
          "id": "assignee-id",
          "type": "people",
          "people": [
            {
              "object": "user",
              "id": "user-uuid",
              "name": "Jane Doe",
              "type": "person"
            }
          ]
        },
        "Description": {
          "id": "desc-id",
          "type": "rich_text",
          "rich_text": [
            {
              "type": "text",
              "text": { "content": "When submitting the login form with an empty email field..." },
              "plain_text": "When submitting the login form with an empty email field..."
            }
          ]
        },
        "Priority": {
          "id": "priority-id",
          "type": "select",
          "select": {
            "name": "High",
            "color": "red"
          }
        }
      }
    }
  ],
  "has_more": false,
  "next_cursor": null
}
```

**Note:** Notion databases are highly customizable. Property names (e.g., "Name", "Status", "Tags", "Assignee", "Description") may differ across databases. The adapter must support configurable property name mappings.

---

## Normalize Implementation

Convert Notion JSON to common format:

```yaml
# Input: Notion API response
# Output: Common issue format

id: "NOT#${id.slice(0,8)}"
tracker: notion
url: "${url}"

title: "${properties.Name.title[0]?.plain_text || ''}"
body: "${properties.Description.rich_text[0]?.plain_text || ''}"
status: "${properties.Status.status?.name || 'Not started'}"
type: "${infer_type(properties.Tags.multi_select)}"

labels: "${properties.Tags.multi_select.map(t => t.name)}"
assignees: "${properties.Assignee.people.map(p => p.name)}"
milestone: null
created_at: "${created_time}"
updated_at: "${last_edited_time}"

comments: []                          # Notion comments require a separate API call

yolo_status: "${map_status(properties.Status.status?.name)}"
suggested_yolo: "${infer_type(properties.Tags.multi_select)}"
```

### Fetching Comments (Separate Call)

```bash
curl -s \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  "https://api.notion.com/v1/comments?block_id=a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

```json
{
  "results": [
    {
      "id": "comment-uuid",
      "created_time": "2026-02-01T12:00:00.000Z",
      "created_by": {
        "id": "user-uuid",
        "name": "John Smith"
      },
      "rich_text": [
        {
          "type": "text",
          "plain_text": "Can reproduce on Chrome"
        }
      ]
    }
  ]
}
```

Normalized:

```yaml
comments:
  - author: "${comment.created_by.name}"
    date: "${comment.created_time}"
    body: "${comment.rich_text.map(r => r.plain_text).join('')}"
```

---

## Type Mapping

### Label → Type Inference

Uses the `Tags` multi-select property with base label mappings:

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
def infer_type(tags_multi_select):
    tag_names = [t["name"].lower() for t in tags_multi_select]

    # Check release labels
    for label in release_labels:
        if label in tag_names:
            return "release"

    # Check feature labels
    for label in feature_labels:
        if label in tag_names:
            return "feature"

    # Check feature-task labels
    for label in feature_task_labels:
        if label in tag_names:
            return "feature-task"

    # Check do labels
    for label in do_labels:
        if label in tag_names:
            return "do"

    # Default
    return "do"
```

**Note on custom databases:** Because Notion databases are fully customizable, the property used for type inference may not be called "Tags". The adapter configuration should allow specifying which property holds type/label data.

---

## Status Mapping

Notion has custom statuses per database. The adapter matches status names case-insensitively:

| Common Notion Status | YOLO Status |
|----------------------|------------|
| Not started | pending |
| To do | pending |
| Backlog | pending |
| In progress | in_progress |
| Doing | in_progress |
| In review | in_progress |
| Blocked | blocked |
| On hold | blocked |
| Waiting | blocked |
| Done | completed |
| Complete | completed |
| Completed | completed |
| Cancelled | cancelled |
| Archived | cancelled |

### Mapping Logic

```python
def map_status(status_name):
    if status_name is None:
        return "pending"

    name_lower = status_name.lower()

    pending_statuses = ["not started", "to do", "backlog"]
    in_progress_statuses = ["in progress", "doing", "in review"]
    blocked_statuses = ["blocked", "on hold", "waiting"]
    completed_statuses = ["done", "complete", "completed"]
    cancelled_statuses = ["cancelled", "canceled", "archived"]

    if name_lower in pending_statuses:
        return "pending"
    if name_lower in in_progress_statuses:
        return "in_progress"
    if name_lower in blocked_statuses:
        return "blocked"
    if name_lower in completed_statuses:
        return "completed"
    if name_lower in cancelled_statuses:
        return "cancelled"

    # Default for unknown custom statuses
    return "pending"
```

**Note:** Because Notion statuses are fully custom, unrecognized status names default to `pending`. The adapter configuration should allow users to define additional status mappings for their specific database.

---

## Push Implementation (Future)

### Update Page Properties (Change Status)

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  "https://api.notion.com/v1/pages/a1b2c3d4-e5f6-7890-abcd-ef1234567890" \
  -d '{
    "properties": {
      "Status": {
        "status": {
          "name": "Done"
        }
      }
    }
  }'
```

### Add Comment

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  "https://api.notion.com/v1/comments" \
  -d '{
    "parent": { "page_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890" },
    "rich_text": [
      {
        "type": "text",
        "text": { "content": "Status update: completed via YOLO" }
      }
    ]
  }'
```

### Update Tags

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  "https://api.notion.com/v1/pages/a1b2c3d4-e5f6-7890-abcd-ef1234567890" \
  -d '{
    "properties": {
      "Tags": {
        "multi_select": [
          { "name": "bug" },
          { "name": "done" }
        ]
      }
    }
  }'
```

**Note:** Notion's multi_select update replaces all values. To add a tag without removing existing ones, the adapter must first read the current tags and merge them.

---

## Error Handling

### Auth Errors (Missing Credentials)

```
Error: NOTION_API_KEY or NOTION_DATABASE_ID environment variable is not set.
```

**Action:** Run `/yolo:sync setup notion` and provide integration token and database ID

### Auth Errors (Invalid Token)

```json
{
  "object": "error",
  "status": 401,
  "code": "unauthorized",
  "message": "API token is invalid."
}
```

**Action:** Verify the integration token. Regenerate from Notion Integrations page.

### Not Found (Database Not Shared)

```json
{
  "object": "error",
  "status": 404,
  "code": "object_not_found",
  "message": "Could not find database with ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890."
}
```

**Action:** Ensure the database is shared with the integration. Open the database in Notion, click "..." > "Add connections" and select the integration.

### Rate Limit (429)

```json
{
  "object": "error",
  "status": 429,
  "code": "rate_limited",
  "message": "Rate limited",
  "retry_after": 1
}
```

**Action:** Wait for the `retry_after` duration. Notion allows approximately 3 requests per second per integration.

### Validation Error

```json
{
  "object": "error",
  "status": 400,
  "code": "validation_error",
  "message": "Property 'Status' does not exist on the database."
}
```

**Action:** Check the database schema. Property names are case-sensitive. Run `/yolo:sync setup notion` to reconfigure property mappings.

---

## Example Usage

### Setup

```bash
/yolo:sync setup notion

# Output:
# Checking environment variables...
# ✓ NOTION_API_KEY: configured
# ✓ NOTION_DATABASE_ID: configured
# Verifying connection...
# ✓ Connected to workspace: My Workspace
# Reading database schema...
# ✓ Database: Task Tracker
#   Properties detected:
#     - Name (title)
#     - Status (status): Not started, In progress, Done
#     - Tags (multi_select): bug, feature, chore
#     - Assignee (people)
#     - Description (rich_text)
# Creating config...
# ✓ Setup complete
```

### Pull

```bash
/yolo:sync pull --label=bug

# Fetches all items with "bug" tag from the database
# Normalizes to common format
# Presents for import
```

### Pull Specific

```bash
/yolo:sync pull NOT#a1b2c3d4

# Fetches the page by ID prefix
# Shows details and suggested mapping
# Imports on confirmation
```
