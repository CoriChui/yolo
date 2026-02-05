<purpose>
End an active release.
Handles incomplete features by asking user per feature.
Locks intake and generates output specs.
</purpose>

<triggers>
- `/release end` - End the focused release
- `/release end <id>` - End specific release by ID
</triggers>

<process>

<step name="determine_release">
Determine which release to end:

**If ID provided:**
```bash
RELEASE_ID=${ARG}
```

**If no ID:**
```bash
RELEASE_ID=$(cat .planning/state.yaml | yq '.focus.release')
```

Validate release exists and check status:
```bash
RELEASE_DIR=".planning/releases/${RELEASE_ID}"
RELEASE_STATUS=$(cat "${RELEASE_DIR}/release.yaml" | yq '.status')
```

**If no release found:**
```
═══════════════════════════════════════════════════════════════
NO RELEASE FOUND
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" not found.
Use /release status to see active releases.
═══════════════════════════════════════════════════════════════
```

**If pending (not started):**
```
═══════════════════════════════════════════════════════════════
RELEASE NOT STARTED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" is pending, not active.
Start it first with /release start ${RELEASE_ID}
Or delete it manually.
═══════════════════════════════════════════════════════════════
```

**If paused:**
```
═══════════════════════════════════════════════════════════════
RELEASE PAUSED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" is paused.
Resume it first with /release resume ${RELEASE_ID}
═══════════════════════════════════════════════════════════════
```

**If failed:**
```
═══════════════════════════════════════════════════════════════
RELEASE FAILED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" is in a failed state.
It cannot be ended normally. Investigate or create a new release.
═══════════════════════════════════════════════════════════════
```

**If cancelled:**
```
═══════════════════════════════════════════════════════════════
RELEASE CANCELLED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" has been cancelled.
Cancelled releases cannot be ended. Create a new release.
═══════════════════════════════════════════════════════════════
```

**If completed (already ended):**
```
═══════════════════════════════════════════════════════════════
RELEASE ALREADY COMPLETED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" has already been completed.
Use /release status ${RELEASE_ID} to view its archive.
═══════════════════════════════════════════════════════════════
```
</step>

<step name="check_features">
List all features and identify incomplete ones:

```bash
FEATURES=$(cat ".planning/releases/${RELEASE_ID}/release.yaml" | yq '.features[]')
INCOMPLETE=$(cat ".planning/releases/${RELEASE_ID}/release.yaml" | \
  yq '.features[] | select(.status != "completed")')
```
</step>

<step name="handle_incomplete_features">
**For EACH incomplete feature, ask user what to do:**

```
═══════════════════════════════════════════════════════════════
INCOMPLETE FEATURE: ${FEATURE_ID}-${FEATURE_NAME}
═══════════════════════════════════════════════════════════════

Status: ${FEATURE_STATUS}
Goal: ${FEATURE_GOAL}

What would you like to do?

  [1] Complete now — Mark as completed
  [2] Detach — Move to standalone features/
  [3] Archive incomplete — Keep in release as-is

───────────────────────────────────────────────────────────────
```

Use AskUserQuestion for each incomplete feature.

**Handle response:**

**1. Complete now:**
- Mark feature as completed in release.yaml
- Update progress

**2. Detach:**
# Note: Keep in sync with feature-detach.md workflow, or invoke it directly
- Move feature directory to `.planning/features/` (standalone)
- Remove from release.yaml features array
- Add to state.yaml standalone_features
- Update release progress

**3. Archive incomplete:**
- Keep feature in release as-is
- Note incomplete status in summary
</step>

<step name="lock_intake">
Lock the release intake:

Update .planning/releases/${RELEASE_ID}/release.yaml:
```yaml
intake:
  current: "${INTAKE_VERSION}"
  locked: true                        # Locked on release end
```

Update intake manifest:
```yaml
# .planning/releases/${RELEASE_ID}/intake/${INTAKE_VERSION}/manifest.yaml
version: "${INTAKE_VERSION}"
release: "${RELEASE_ID}"
created: ${CREATED_TIMESTAMP}
closed: ${TIMESTAMP}
status: closed                        # No more captures
```
</step>

<step name="generate_output_specs">
Generate output specs from codebase:

```bash
OUTPUT_DIR=".planning/releases/${RELEASE_ID}/output"
mkdir -p "$OUTPUT_DIR"
```

**Generate output/schema.md:**
- Read actual database types
- Document current schema state

**Generate output/api.md:**
- List actual API endpoints
- Document routes and handlers

**Generate output/architecture.md:**
- System overview
- Component relationships
- Technology stack

These are for VISIBILITY — documentation of what was built.
</step>

<step name="update_release_file">
# Assert that started_at is non-null before completing
# If started_at is null, abort with error: "Cannot complete a release that was never started"

Update .planning/releases/${RELEASE_ID}/release.yaml:

```yaml
id: "${RELEASE_ID}"
slug: "${RELEASE_SLUG}"
title: "${RELEASE_TITLE}"
created: ${CREATED_TIMESTAMP}

goal: |
  ${RELEASE_GOAL}

success_criteria:
  - ${CRITERIA}

intake:
  current: "${INTAKE_VERSION}"
  locked: true                        # Intake locked

features:
  - id: "01"
    name: foundation
    status: completed
  - id: "02"
    name: auth
    status: completed
  # Only features not detached

progress:
  features_total: ${FEATURES_TOTAL}
  features_completed: ${FEATURES_COMPLETED}
  percentage: ${PERCENTAGE}

status: completed                     # Release completed
started_at: ${STARTED_TIMESTAMP}
completed_at: ${TIMESTAMP}
paused_at: null
failed_at: null
cancelled_at: null

archive:
  shipped_at: ${TIMESTAMP}
  git_range: "${GIT_START_TAG}..${GIT_END_TAG}"
  stats:
    features_total: ${FEATURES_TOTAL}
    features_completed: ${FEATURES_COMPLETED}
    features_detached: ${DETACHED_COUNT}
    duration: "${DURATION}"

summary: |
  Release completed on ${DATE}.
  ${FEATURES_COMPLETED}/${FEATURES_TOTAL} features completed.
  ${DETACHED_COUNT} features detached to standalone.
```
</step>

<step name="update_state">
# Acquire state lock
Update .planning/state.yaml:

Remove completed release from releases array:
# Note: Release directory .planning/releases/${RELEASE_ID}/ serves as the archive record
```yaml
focus:
  release: null                       # Or next release if exists
  feature: null
  feature_release: null

releases:
  # Release removed from array
  # ... other releases remain ...

# If features were detached:
standalone_features:
  total: ${STANDALONE_COUNT}
  active: 0
  list:
    # ... detached features added here ...

session:
  last_activity: ${TIMESTAMP}
  last_action: "release-end ${RELEASE_ID}"
  last_error: null                    # Cleared on success

updated_at: ${TIMESTAMP}
updated_by: release-end
_checksum: ${COMPUTED_CHECKSUM}       # Recomputed after write
```

# Release state lock

On failure, record error before releasing lock:
```yaml
session:
  last_error: "${ERROR_MESSAGE}"
```

# Focus switch protocol:
# If other releases exist, choose next focused release.
# Check the chosen release for an in_progress feature.
# If found, set focus.feature to that feature's ID and focus.feature_release to that release ID.
If other releases exist, optionally set focus to another release.
</step>

<step name="report_success">
```
═══════════════════════════════════════════════════════════════
RELEASE COMPLETED: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Features: ${FEATURES_COMPLETED}/${FEATURES_TOTAL} completed
Detached: ${DETACHED_COUNT} moved to standalone
Intake:   ${INTAKE_VERSION} (locked)
Duration: ${DURATION}

Output generated:
  .planning/releases/${RELEASE_ID}/output/schema.md
  .planning/releases/${RELEASE_ID}/output/api.md
  .planning/releases/${RELEASE_ID}/output/architecture.md

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /release new <slug>   — Start new release
  /release status       — View all releases
  /feature list         — See standalone features
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<notes>
- Supports optional release ID parameter (defaults to focused release)
- Requires an active release
- Asks user per incomplete feature: complete/detach/archive
- Detached features move to standalone .planning/features/ directory
- Locks intake (no more captures for this release)
- Generates output specs for visibility
- Removes release from state.yaml releases array
- Release files preserved in .planning/releases/${RELEASE_ID}/
</notes>
