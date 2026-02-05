<purpose>
Create a new release with PENDING status.
This creates the release record AND a release-scoped intake.
No research happens yet — that's /release start.
Multiple releases can exist in parallel.
</purpose>

<triggers>
- `/release new <slug>` - Create new release with slug
- `/release new` - Interactive release creation
</triggers>

<process>

<step name="gather_release_info">
Collect release information:

**If slug provided:**
```bash
RELEASE_SLUG=${ARG}
```

**If interactive:**
Use AskUserQuestion:
- Question: "What slug for this release?"
- Examples: "mvp", "mobile-app", "billing-integration"
</step>

<step name="generate_release_id">
Generate release ID from current date + slug:

```bash
TODAY=$(date +%Y-%m-%d)
RELEASE_ID="${TODAY}-${RELEASE_SLUG}"
# Example: 2026-02-04-mvp
```
</step>

<step name="validate_not_exists">
Validate that the release does not already exist:

```bash
RELEASE_DIR=".planning/releases/${RELEASE_ID}"
if [ -d "$RELEASE_DIR" ]; then
  echo "Release already exists: ${RELEASE_ID}"
  echo "Use /release status ${RELEASE_ID} to see its details."
  exit 1
fi
```
</step>

<step name="create_release_structure">
Create release directory structure:

```bash
RELEASE_DIR=".planning/releases/${RELEASE_ID}"
mkdir -p "${RELEASE_DIR}/intake/${RELEASE_SLUG}-v1"
mkdir -p "${RELEASE_DIR}/features"
mkdir -p "${RELEASE_DIR}/output"
```

**Create release.yaml:**
```yaml
id: "${RELEASE_ID}"
slug: "${RELEASE_SLUG}"
title: ""                              # User fills later
created: ${TIMESTAMP}

goal: ""
success_criteria: []

# Intake (release-scoped)
intake:
  current: "${RELEASE_SLUG}-v1"
  locked: false

# Features (auto-created on /release start)
features: []

# Progress
progress:
  features_total: 0
  features_completed: 0
  percentage: 0

# Status
status: pending
started_at: null
completed_at: null
paused_at: null
failed_at: null
cancelled_at: null

# Archive (populated on release end)
archive: null
```

**Create intake manifest:**
```yaml
# .planning/releases/${RELEASE_ID}/intake/${RELEASE_SLUG}-v1/manifest.yaml
version: "${RELEASE_SLUG}-v1"
release: "${RELEASE_ID}"
created: ${TIMESTAMP}
status: open

sources: []

stats:
  total_files: 0
  sources: 0
```
</step>

<step name="update_state">
# Acquire state lock
# Note: If a release was previously focused, inform user: "Focus switching from ${OLD_FOCUSED} to ${RELEASE_ID}"
Update .planning/state.yaml:

Add to releases array and set as focused:

```yaml
focus:
  release: "${RELEASE_ID}"             # New release is focused

releases:
  # ... existing releases ...
  - id: "${RELEASE_ID}"
    slug: "${RELEASE_SLUG}"
    status: pending
    created: ${TIMESTAMP}
    started_at: null
    intake:
      current: "${RELEASE_SLUG}-v1"
      locked: false
    progress:
      features_total: 0
      features_completed: 0
      percentage: 0

session:
  last_activity: ${TIMESTAMP}
  last_action: "release-new ${RELEASE_ID}"
  last_error: null                     # Cleared on success

updated_at: ${TIMESTAMP}
updated_by: release-new
_checksum: ${COMPUTED_CHECKSUM}        # Recomputed after write
```

# Release state lock

On failure, record error before releasing lock:
```yaml
session:
  last_error: "${ERROR_MESSAGE}"
```
</step>

<step name="report_success">
```
═══════════════════════════════════════════════════════════════
RELEASE CREATED: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Status: PENDING
Intake: ${RELEASE_SLUG}-v1 (open for capture)
Location: .planning/releases/${RELEASE_ID}/

This release is now FOCUSED.
Capture intake materials before starting.

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /intake capture figma    — Capture from Figma
  /intake capture notion   — Capture from Notion
  /intake capture manual   — Add content manually
  /release start           — Start release (runs research)
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<notes>
- Creates release in PENDING status (not active)
- Automatically creates release-scoped intake at .planning/releases/id/intake/slug-v1/
- Intake is OPEN for capture
- No research happens until /release start
- Multiple releases can exist in parallel (no constraint check)
- New release automatically becomes focused
- Release ID format: YYYY-MM-DD-slug
</notes>
