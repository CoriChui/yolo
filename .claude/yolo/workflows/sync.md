# /sync Workflow

# Note: sync.yaml should use proper YAML format to match DO.yaml and DEBUG.yaml conventions

## Purpose

Import issues from external trackers (GitHub, GitLab, Linear, Jira, Notion) into YOLO workflow with automatic type mapping.

**Key principles:**

- **Tracker is source of truth** — external tracker wins in conflicts
- **Pluggable adapters** — each tracker has its own adapter
- **Auto-mapping** — ticket type determines YOLO item type
- **Comments imported** — context preserved from tracker

## File Structure

```
.planning/
└── sync/
    ├── sync.yaml              # Central tracking file
    ├── config.yaml          # Tracker configuration
    └── cache/               # Per-tracker cache
        ├── github/
        │   └── issues.json
        └── linear/
            └── issues.json

.claude/yolo/
└── adapters/
    ├── adapter.md           # Base adapter spec
    ├── github.md            # GitHub Issues
    ├── gitlab.md            # GitLab Issues
    ├── linear.md            # Linear
    ├── jira.md              # Jira
    └── notion.md            # Notion
```

---

## Subcommand Routing

Parse first argument and dispatch to the correct flow:

```bash
SUBCOMMAND="${1:-status}"  # Default to status if no argument

case "$SUBCOMMAND" in
  setup)   # → Flow: /sync setup [tracker]
    TRACKER="${2}"
    ;;
  pull)    # → Flow: /sync pull [filter]
    FILTER="${2}"
    ;;
  status)  # → Flow: /sync status
    ;;
  refresh) # → Flow: /sync refresh [id]
    REFRESH_ID="${2}"
    ;;
  link)    # → Flow: /sync link <external> <yolo>
    EXTERNAL="${2}"
    YOLO_ITEM="${3}"
    ;;
  *)
    echo "Unknown subcommand: ${SUBCOMMAND}"
    echo "Usage: /sync [setup|pull|status|refresh|link]"
    exit 1
    ;;
esac
```

## Commands

### /sync setup [tracker]

Configure tracker connection with authentication.

### /sync pull [filter]

Import issues from tracker. **Asks which release to assign features to.**

### /sync status

Show sync state and drift detection.

### /sync link <external> <yolo>

Manually link external issue to YOLO item.

### /sync refresh [id]

Re-import issue to get latest comments/status.

### /sync push (Future)

Push YOLO status back to tracker.

---

## sync.yaml Format

```markdown
# External Sync

## Configuration

- **Primary tracker:** github
- **Repository:** owner/repo
- **Auto-refresh:** on-pull
- **Last sync:** 2026-02-03T10:00:00

## Linked Items

| External | Type    | Title       | YOLO Item                             | YOLO Status | Tracker Status | Last Sync  |
| -------- | ------- | ----------- | ------------------------------------- | ----------- | -------------- | ---------- |
| GH#123   | bug     | Login crash | [/do/005](../do/005-login-crash/)     | completed   | closed         | 2026-02-03 |
| GH#124   | feature | Billing     | [releases/2026-02-04-mvp/features/03-billing](../releases/2026-02-04-mvp/features/03-billing/) | in_progress | open           | 2026-02-03 |
| GH#120   | epic    | MVP         | [release/2026-02-04-mvp](../releases/2026-02-04-mvp/)     | active      | open           | 2026-02-03 |

## Pending Import

Issues fetched but not yet imported:

| External | Type    | Title       | Labels  | Suggested | Action   |
| -------- | ------- | ----------- | ------- | --------- | -------- |
| GH#125   | bug     | API timeout | bug,api | /do task  | [Import] |
| GH#126   | feature | Export CSV  | feature | Feature   | [Import] |

## Drift Detected

Items where tracker status changed:

| External | YOLO Item | YOLO Status | Tracker Status | Action |
| -------- | --------- | ----------- | -------------- | ------ |
| GH#130   | /do/007   | in_progress | closed         | [Sync] |

## Statistics

- Total linked: 3
- Pending import: 2
- Drift detected: 1
- Last full sync: 2026-02-03
```

---

## config.yaml Format

```yaml
# Sync configuration
# Location: .planning/sync/config.yaml

tracker: github # Primary tracker

github:
  repository: owner/repo # Auto-detected from git remote
  auth: gh_cli # gh CLI handles auth
  default_filter:
    state: open
    labels: []

mapping:
  release:
    - epic
    - initiative
  feature:
    - feature
    - story
    - user-story
    - enhancement
  feature-task:
    - subtask
  do:
    - bug
    - fix
    - hotfix
    - task
    - chore
    - documentation
    - refactor
    - security
    - performance

sync:
  direction: import # import | bidirectional
  conflict_resolution: tracker # tracker wins
  import_comments: true
  import_status: true
  auto_refresh: on-pull # on-pull | manual | scheduled
```

---

## Type Mapping Rules

### Auto-inference from Labels/Type

| External Label/Type              | YOLO Item                  |
| -------------------------------- | -------------------------- |
| `epic`, `initiative`             | Release                    |
| `feature`, `story`, `user-story` | Feature                    |
| `bug`, `fix`, `hotfix`           | /do task                   |
| `task`, `chore`                  | /do task                   |
| `subtask` (with parent)          | Task within parent feature |

### Override via Command

```bash
/sync pull GH#123 --as=feature    # Force as feature
/sync pull GH#123 --as=do         # Force as /do task
/sync pull GH#123 --as=release    # Force as release
```

---

## Flow: /sync setup [tracker]

### Step 1: Detect Tracker

If no tracker specified, detect from git remote:

```bash
# Check for GitHub
git remote -v | grep -q "github.com" && echo "github"

# Check for GitLab
git remote -v | grep -q "gitlab" && echo "gitlab"
```

### Step 2: Load Adapter

# Validate: Check if adapter file exists at .claude/yolo/adapters/${TRACKER}.md before loading. Error with available adapters list if missing.
```bash
ADAPTER_FILE=".claude/yolo/adapters/${TRACKER}.md"
if [ ! -f "$ADAPTER_FILE" ]; then
  echo "ERROR: Adapter not found for tracker '${TRACKER}'"
  echo ""
  echo "Available adapters:"
  ls -1 .claude/yolo/adapters/*.md 2>/dev/null | grep -v adapter.md | \
    sed 's|.claude/yolo/adapters/||; s|\.md$||' | sed 's/^/  - /'
  exit 1
fi
```

Load adapter from `.claude/yolo/adapters/{tracker}.md`

### Step 3: Authenticate

Each adapter handles its own auth:

**GitHub:**

```bash
# Check if gh CLI is authenticated
gh auth status

# If not authenticated
gh auth login
```

**GitLab:**

```bash
glab auth status
glab auth login
```

**Linear:**

```bash
# Check for API key
if [ -z "$LINEAR_API_KEY" ]; then
  echo "Set LINEAR_API_KEY environment variable"
  echo "Get key from: Linear Settings → API → Personal API keys"
fi
```

### Step 4: Verify Connection

Test connection by fetching 1 issue:

```bash
# GitHub
gh issue list --limit 1

# GitLab
glab issue list --per-page 1
```

### Step 5: Create Config

# XC-001: Acquire lock before modifying state files
```bash
LOCK_FILE=".planning/sync/sync.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: sync.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

Create `.planning/sync/config.yaml` with detected settings.

### Step 6: Create sync.yaml

Create `.planning/sync/sync.yaml` from template.

# XC-002: Compute checksum after sync.yaml write
```bash
_checksum=$(sha256sum .planning/sync/sync.yaml | cut -d' ' -f1)
```

# XC-003: Update session fields in state.yaml

```bash
# Acquire state lock
LOCK_ID="sync-$(date +%s)"
yq -i ".lock.held_by = \"${LOCK_ID}\"" .planning/state.yaml
yq -i ".lock.acquired_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" .planning/state.yaml
yq -i ".lock.expires_at = \"$(date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)\"" .planning/state.yaml
```

```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Sync setup completed for ${TRACKER}\"" .planning/state.yaml
yq -i ".session.last_error.at = null" .planning/state.yaml
yq -i ".session.last_error.workflow = null" .planning/state.yaml
yq -i ".session.last_error.message = null" .planning/state.yaml
yq -i ".session.last_error.recoverable = null" .planning/state.yaml
yq -i ".session.last_error.recovery_hint = null" .planning/state.yaml
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i "._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release state lock
yq -i ".lock.held_by = null" .planning/state.yaml
yq -i ".lock.acquired_at = null" .planning/state.yaml
yq -i ".lock.expires_at = null" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```

### Step 7: Output

```
───────────────────────────────
/sync SETUP COMPLETE

Tracker: github
Repository: owner/repo
Auth: ✓ Configured (gh CLI)

Config: .planning/sync/config.yaml
Tracking: .planning/sync/sync.yaml

Next: /sync pull
───────────────────────────────
```

---

## Flow: /sync pull [filter]

### Step 0: Acquire Lock

# XC-001: Acquire lock before pull operations that modify sync.yaml and state.yaml
```bash
LOCK_FILE=".planning/sync/sync.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: sync.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

### Step 1: Load Config

```bash
# Read config
cat .planning/sync/config.yaml
```

### Step 2: Load Active Releases

```bash
# Get all active/pending releases from state
RELEASES=$(cat .planning/state.yaml | yq '.releases[] | select(.status != "completed")')
FOCUSED_RELEASE=$(cat .planning/state.yaml | yq '.focus.release')
```

### Step 3: Fetch Issues

Via adapter:

```bash
# GitHub - all open issues
gh issue list --state open --json number,title,labels,body,comments,state

# GitHub - filtered
gh issue list --label bug --json number,title,labels,body,comments,state

# GitHub - specific issue
gh issue view 123 --json number,title,labels,body,comments,state
```

### Step 4: Normalize

Convert to common format:

```yaml
- id: 'GH#123'
  tracker: github
  type: bug # Inferred from labels
  title: 'Login crashes on empty email'
  body: 'When submitting login form...'
  status: open
  labels: [bug, auth]
  comments:
    - author: 'user1'
      date: '2026-02-01'
      body: 'Can reproduce on Chrome'
    - author: 'user2'
      date: '2026-02-02'
      body: 'Same on Firefox'
  suggested_yolo: do # Auto-mapped from type
  url: 'https://github.com/owner/repo/issues/123'
```

### Step 5: Check Already Linked

Compare against sync.yaml Linked Items.
Skip already-linked issues (or mark for refresh).

### Step 6: Present Pending

```
PENDING IMPORT (3 issues)
─────────────────────────

| # | External | Type | Title | Suggested |
|---|----------|------|-------|-----------|
| 1 | GH#123 | bug | Login crashes on empty email | /do task |
| 2 | GH#124 | feature | Add password reset | Feature |
| 3 | GH#125 | bug | API returns 500 | /do task |

Import which? [1,2,3 / all / none / 1 --as=feature]
```

### Step 7: Ask Release Assignment (for Features)

**For each feature-type issue, ask which release to assign:**

```
═══════════════════════════════════════════════════════════════
ASSIGN FEATURE: GH#124 "Add password reset"
═══════════════════════════════════════════════════════════════

Which release should this feature belong to?

  [1] 2026-02-04-mvp (active) [focused]
      Progress: 50% (2/4 features)

  [2] 2026-02-10-mobile (pending)
      Progress: not started

  [3] Standalone
      Create as standalone feature (can attach to release later)

  [4] Skip
      Don't import this issue

Choice:
```

**Track assignment for each feature:**

```yaml
imports:
  - external: 'GH#124'
    type: feature
    title: 'Add password reset'
    assigned_to: '2026-02-04-mvp'  # or "standalone" or "skip"
  - external: 'GH#126'
    type: feature
    title: 'Export CSV'
    assigned_to: 'standalone'
```

### Step 8: Import Selected

For each selected issue:

**If /do task:**

1. Create directory `.planning/do/NNN-{slug}/`
2. Create `plan.md` with issue body + comments as context
3. Update DO.md
4. Update sync.yaml

**If Feature (assigned to release):**

1. Create feature in release: `.planning/releases/{release-id}/features/{NN}-{slug}/`
2. Create `feature.yaml` with release reference
3. Update release.yaml features list
4. Update sync.yaml

**If Feature (standalone):**

1. Create standalone feature: `.planning/features/{slug}/`
2. Create `feature.yaml` with `release: null`
3. Update state.yaml standalone_features
4. Update sync.yaml

**If Feature-task:**

# Feature-task → Add task to existing feature
# Present user with list of active features, create task within selected feature

1. List active features across all active releases and standalone features
2. Present user with selection of which feature to add the task to
3. Create task within the selected feature's tasks list
4. Update sync.yaml

**If Release:**

1. Add to release queue
2. Create `.planning/sync/pending-releases/{slug}.md`
3. Update sync.yaml

### Step 9: Commit

# XC-002: Compute checksum after sync.yaml write
```bash
_checksum=$(sha256sum .planning/sync/sync.yaml | cut -d' ' -f1)
```

# XC-003: Update session fields in state.yaml

```bash
# Acquire state lock
LOCK_ID="sync-$(date +%s)"
yq -i ".lock.held_by = \"${LOCK_ID}\"" .planning/state.yaml
yq -i ".lock.acquired_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" .planning/state.yaml
yq -i ".lock.expires_at = \"$(date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)\"" .planning/state.yaml
```

```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Sync pull: imported ${IMPORT_COUNT} issues from ${TRACKER}\"" .planning/state.yaml
yq -i ".session.last_error.at = null" .planning/state.yaml
yq -i ".session.last_error.workflow = null" .planning/state.yaml
yq -i ".session.last_error.message = null" .planning/state.yaml
yq -i ".session.last_error.recoverable = null" .planning/state.yaml
yq -i ".session.last_error.recovery_hint = null" .planning/state.yaml
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i "._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release state lock
yq -i ".lock.held_by = null" .planning/state.yaml
yq -i ".lock.acquired_at = null" .planning/state.yaml
yq -i ".lock.expires_at = null" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```

```bash
git add .planning/sync/
git add .planning/do/       # If /do tasks created
git add .planning/releases/           # If features added to releases
git add .planning/features/           # If standalone features created
git commit -m "sync: import issues from github

Imported:
- GH#123 → /do/008-login-crash
- GH#124 → .planning/releases/2026-02-04-mvp/features/05-password-reset
- GH#125 → /do/009-api-500
- GH#126 → .planning/features/export-csv (standalone)"
```

### Step 10: Output

```
───────────────────────────────
/sync PULL COMPLETE

Imported: 4 issues
Skipped: 1 (already linked)

Created:
  /do/008-login-crash ← GH#123
  /do/009-api-500 ← GH#125

  Release 2026-02-04-mvp:
    05-password-reset ← GH#124

  Standalone:
    export-csv ← GH#126

Next:
  /do list              Show imported tasks
  /feature list         Show all features
  /sync status          Check sync state
───────────────────────────────
```

---

## Flow: /sync status

### Output

```
SYNC STATUS
───────────

Tracker: github (owner/repo)
Last sync: 2026-02-03 10:00

LINKED ITEMS (5)
| External | YOLO | Status |
|----------|-----|--------|
| GH#123 | /do/008 | ✓ In sync |
| GH#124 | feature/03 | ✓ In sync |
| GH#125 | /do/009 | ✓ In sync |
| GH#130 | /do/007 | ⚠ Drift (tracker: closed) |
| GH#131 | feature/04 | ✓ In sync |

PENDING IMPORT (2)
  GH#140: Add dark mode (feature)
  GH#141: Fix typo (bug)

DRIFT DETECTED (1)
  GH#130: Closed in tracker, YOLO shows in_progress
  → Run /sync refresh GH#130 to update

Commands:
  /sync pull            Import pending
  /sync refresh GH#130  Update drifted item
```

---

## Flow: /sync refresh [id]

Re-fetch issue from tracker and update YOLO item with:

- Latest status
- New comments
- Updated description

**Tracker wins** — if tracker shows closed, mark YOLO item as completed.

---

## Flow: /sync link <external> <yolo>

Manually link an external issue to existing YOLO item.

```bash
/sync link GH#150 /do/003-validation

# Updates sync.yaml with new link
# Imports comments into plan.md
```

---

## Imported Issue Format

When importing to /do task, create `plan.md`:

```markdown
# Do 008: Login crashes on empty email

**Started:** 2026-02-03
**Status:** in_progress
**Source:** [GH#123](https://github.com/owner/repo/issues/123)

## Context

**From tracker:**

> When submitting login form with empty email field, the app crashes
> with "Cannot read property 'toLowerCase' of undefined".
>
> Steps to reproduce:
>
> 1. Go to /login
> 2. Leave email empty
> 3. Click Submit

**Comments:**

> **user1** (2026-02-01):
> Can reproduce on Chrome 120

> **user2** (2026-02-02):
> Same on Firefox. Looks like missing null check.

## Tasks

- [ ] Task 1: Add null check for email field
  - Files: `src/auth/login.ts`

## Notes

[Additional notes during work]
```

---

## Success Criteria

- [ ] Adapter handles authentication
- [ ] Issues fetched and normalized
- [ ] Type auto-mapped from labels
- [ ] User can override mapping
- [ ] Comments imported as context
- [ ] sync.yaml tracks all links
- [ ] Drift detected on status check
- [ ] Tracker wins in conflicts
