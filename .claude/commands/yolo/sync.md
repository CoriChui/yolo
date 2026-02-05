---
name: yolo:sync
description: Import issues from external trackers (GitHub, GitLab, Linear, Jira)
argument-hint: '[setup|pull|status|link|refresh] [args]'
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
---

<objective>
Import issues from external trackers into YOLO workflow with automatic type mapping.

**Key features:**

- Pluggable adapters (GitHub, GitLab, Linear, Jira, Notion)
- Auto-mapping: epic→release, feature→feature, bug→/do
- Import comments and status
- Tracker wins in conflicts
- Drift detection

**Note:** Currently only the GitHub adapter is fully implemented. Other adapters are planned.

**Subcommands:**

- `/yolo:sync setup [tracker]` — Configure tracker
- `/yolo:sync pull [filter]` — Import issues
- `/yolo:sync status` — Show sync state
- `/yolo:sync link <external> <yolo>` — Manual linking
- `/yolo:sync refresh [id]` — Re-import issue
  </objective>

<execution_context>
@./.claude/yolo/workflows/sync.md
@./.claude/yolo/adapters/adapter.md
@./.claude/yolo/adapters/github.md
@./.claude/yolo/templates/sync.yaml
@./.claude/yolo/templates/sync-config.yaml
</execution_context>

<context>
Arguments: $ARGUMENTS

Check for existing sync config:

```bash
cat .planning/sync/config.yaml 2>/dev/null
```

</context>

<process>

## Parse Subcommand

Parse $ARGUMENTS:

- `setup [tracker]` → Configure tracker
- `pull [filter]` → Import issues
- `status` → Show sync state
- `link <ext> <yolo>` → Manual link
- `refresh [id]` → Re-import
- Empty → Show status or suggest setup

---

## Flow: Setup

**If $ARGUMENTS starts with `setup`:**

### Step 1: Detect Tracker

If no tracker specified, detect from git remote:

```bash
REMOTE=$(git remote get-url origin 2>/dev/null)
if echo "$REMOTE" | grep -q "github.com"; then
  TRACKER="github"
elif echo "$REMOTE" | grep -q "gitlab"; then
  TRACKER="gitlab"
fi
```

### Step 2: Load Adapter

Read adapter spec from `.claude/yolo/adapters/${TRACKER}.md`

### Step 3: Authenticate

**GitHub:**

```bash
gh auth status
# If not authenticated:
# gh auth login
```

**GitLab:**

```bash
glab auth status
```

**Linear:**

```bash
if [ -z "$LINEAR_API_KEY" ]; then
  echo "Set LINEAR_API_KEY environment variable"
fi
```

### Step 4: Detect Repository

```bash
# GitHub
REPO=$(echo "$REMOTE" | sed -E 's/.*github\.com[:/]([^/]+\/[^/.]+)(\.git)?$/\1/')
```

### Step 5: Test Connection

```bash
gh issue list --repo $REPO --limit 1
```

### Step 6: Create Config

Create `.planning/sync/config.yaml`:

```yaml
tracker: ${TRACKER}

${TRACKER}:
  repository: ${REPO}
  auth: ${AUTH_METHOD}
  default_filter:
    state: open

mapping:
  release: [epic, initiative]
  feature: [feature, story, enhancement]
  do: [bug, task, chore]
  default: do

sync:
  direction: import
  conflict_resolution: tracker
  import_comments: true
  import_status: true
```

### Step 7: Create sync.yaml

Create `.planning/sync/sync.yaml` from template.

### Step 8: Output

```
───────────────────────────────
YOLO > /sync SETUP COMPLETE

Tracker: ${TRACKER}
Repository: ${REPO}
Auth: ✓ Configured

Config: .planning/sync/config.yaml
Tracking: .planning/sync/sync.yaml

Next: /yolo:sync pull
───────────────────────────────
```

---

## Flow: Pull

**If $ARGUMENTS starts with `pull`:**

### Step 1: Load Config

```bash
TRACKER=$(grep "^tracker:" .planning/sync/config.yaml | cut -d' ' -f2)
REPO=$(grep "repository:" .planning/sync/config.yaml | cut -d' ' -f2)
```

### Step 2: Parse Filter

From $ARGUMENTS:

- `--label=bug` → Filter by label
- `--milestone=v1.0` → Filter by milestone
- `GH#123` → Specific issue
- `--as=feature` → Force type

### Step 3: Fetch Issues

**GitHub:**

```bash
gh issue list --repo $REPO --state open \
  --json number,title,labels,body,comments,state,stateReason,assignees,milestone,createdAt,updatedAt,url
```

### Step 4: Normalize

Convert to common format with suggested YOLO type.

### Step 5: Check Already Linked

Compare against sync.yaml, skip linked issues.

### Step 6: Present Pending

```
PENDING IMPORT (N issues)
─────────────────────────

| # | External | Type | Title | Suggested |
|---|----------|------|-------|-----------|
| 1 | GH#123 | bug | Login crashes | /do task |
| 2 | GH#200 | feature | Add billing | Feature |
| 3 | GH#50 | epic | MVP Release | Release |

Import which? [1,2,3 / all / none]
```

### Step 7: Import Selected

For each selected:

**If /do task:**

1. Create `.planning/do/NNN-slug/plan.md`
2. Include issue body + comments as context
3. Update DO.yaml
4. Update sync.yaml

**If Feature:**

1. Create `.planning/sync/pending-features/slug.md`
2. Update sync.yaml as "queued"
3. User runs `/yolo:feature start` later

**If Release:**

1. Create `.planning/sync/pending-releases/slug.md`
2. Update sync.yaml as "queued"
3. User runs `/yolo:release new` later

### Step 8: Commit

```bash
git add .planning/sync/ .planning/do/
git commit -m "sync: import issues from ${TRACKER}"
```

### Step 9: Output

```
───────────────────────────────
YOLO > /sync PULL COMPLETE

Imported: N issues

Created:
  /do/008-login-crash ← GH#123
  /do/009-api-timeout ← GH#124

Queued:
  Feature: add-billing ← GH#200
  Release: mvp-release ← GH#50

Next:
  /yolo:do list
  /yolo:sync status
───────────────────────────────
```

---

## Flow: Status

**If $ARGUMENTS is `status`:**

Read sync.yaml and config, display:

```
SYNC STATUS
───────────

Tracker: github (owner/repo)
Last sync: 2026-02-03 10:00

LINKED (N)
| External | YOLO | Status |
|----------|------|--------|
| GH#123 | /do/008 | ✓ In sync |
| GH#200 | feature/03 | ✓ In sync |

PENDING IMPORT (N)
  GH#140: Add dark mode (feature)

DRIFT DETECTED (N)
  GH#130: Closed in tracker, YOLO shows in_progress
  → /yolo:sync refresh GH#130

Commands:
  /yolo:sync pull
  /yolo:sync refresh GH#130
```

---

## Flow: Link

**If $ARGUMENTS starts with `link`:**

Parse: `link GH#150 /do/003`

1. Verify external issue exists
2. Verify YOLO item exists
3. Add to sync.yaml Linked Items
4. Import comments into YOLO item
5. Commit

---

## Flow: Refresh

**If $ARGUMENTS starts with `refresh`:**

Parse: `refresh GH#123`

1. Find linked YOLO item in sync.yaml
2. Re-fetch issue from tracker
3. Update YOLO item with:
   - Latest status (tracker wins)
   - New comments
   - Updated description
4. Update sync.yaml timestamps
5. Commit

</process>

<type_mapping>
**Auto-inference from labels:**

| External Label              | YOLO Type |
| --------------------------- | --------- |
| epic, initiative            | Release   |
| feature, story, enhancement | Feature   |
| bug, fix, task, chore       | /do task  |

**Override:** `/yolo:sync pull GH#123 --as=feature`
</type_mapping>

<success_criteria>

- [ ] Config created with tracker details
- [ ] Auth verified
- [ ] Issues fetched and normalized
- [ ] Type auto-mapped correctly
- [ ] Comments imported
- [ ] sync.yaml tracks all links
- [ ] Drift detected on status
      </success_criteria>
