---
name: yolo:init
description: Initialize YOLO in current project
argument-hint: ""
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - AskUserQuestion
---

<objective>
Initialize YOLO framework in the current project.
Creates `.planning/` structure and initial state (schema v2).
</objective>

<process>

## Step 1: Check Existing

```bash
if [ -f .planning/state.yaml ]; then
  echo "YOLO already initialized"
  exit 0
fi
```

## Step 2: Create Structure

```bash
mkdir -p .planning/{releases,features,do,debug,sync,decisions,archive}
```

## Step 3: Create state.yaml (Schema v2)

```yaml
# STATE.yaml — Single source of project state
# Schema version 2: parallel releases, standalone features, focus tracking
schema_version: 2

updated_at: {TIMESTAMP}
updated_by: yolo-init

# Lock protocol (prevents concurrent writes)
lock:
  held_by: null
  acquired_at: null
  expires_at: null

# ═══════════════════════════════════════════════════════════════
# FOCUS (what we're working on now)
# ═══════════════════════════════════════════════════════════════

focus:
  release: null                     # Currently focused release ID
  feature: null                     # Currently active feature ID
  feature_release: null             # Feature's release (null if standalone)

# ═══════════════════════════════════════════════════════════════
# RELEASES (all active/pending)
# ═══════════════════════════════════════════════════════════════

releases: []

# ═══════════════════════════════════════════════════════════════
# STANDALONE FEATURES
# ═══════════════════════════════════════════════════════════════

standalone_features:
  total: 0
  active: 0
  list: []

# ═══════════════════════════════════════════════════════════════
# CURRENT FEATURE (detailed)
# ═══════════════════════════════════════════════════════════════

feature:
  id: null
  release: null
  status: null
  tasks:
    total: 0
    completed: 0
    current: null
  started_at: null

# ═══════════════════════════════════════════════════════════════
# SESSION
# ═══════════════════════════════════════════════════════════════

session:
  last_activity: {TIMESTAMP}
  last_action: "Initialized YOLO"
  last_error:
    at: null
    workflow: null
    message: null
    recoverable: null
    recovery_hint: null
  resume:
    context: null

# ═══════════════════════════════════════════════════════════════
# METRICS
# ═══════════════════════════════════════════════════════════════

metrics:
  releases_completed: 0
  features_completed: 0
  total_tasks_completed: 0

# State integrity checksum
_checksum: null
```

## Step 4: Create config.yaml

Copy from `.claude/yolo/templates/config.yaml`

## Step 5: Output

```
═══════════════════════════════════════════════════════════════
YOLO INITIALIZED (Schema v2)
═══════════════════════════════════════════════════════════════

Created:
  .planning/
  ├── state.yaml (schema v2 — parallel releases)
  ├── config.yaml
  ├── releases/
  ├── features/
  ├── do/
  ├── debug/
  ├── sync/
  ├── decisions/
  └── archive/

───────────────────────────────────────────────────────────────
NEXT STEPS:

Quick task?
  /yolo:do "description"

Full project?
  /yolo:release new mvp

Need to debug?
  /yolo:debug "issue description"

Import from tracker?
  /yolo:sync setup github

Regenerate agents?
  /yolo:sync-agents
═══════════════════════════════════════════════════════════════
```

</process>

<success_criteria>
- [ ] .planning/ directory created
- [ ] state.yaml exists with schema_version: 2
- [ ] config.yaml exists
- [ ] State includes focus, releases[], standalone_features, session, metrics sections
</success_criteria>
