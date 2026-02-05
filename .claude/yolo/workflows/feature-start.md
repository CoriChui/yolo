<purpose>
Start a feature by setting its status to researching and loading context.
This is the entry point for feature execution.
Supports both release-scoped and standalone features.
</purpose>

<triggers>
- `/feature start <feature-id>` - Start a specific feature (release or standalone)
- `/feature start <feature-id> --release <release-id>` - Start feature in specific release
- `/feature start` - Start next pending feature in focused release
</triggers>

<process>

<step name="load_state">
Read current project state:

```bash
cat .planning/state.yaml
```

Extract:
- `focus.release` - Currently focused release
- `focus.feature` - Current feature
- `feature.status` - Current feature status
- `releases` - Array of active releases
- `standalone_features` - List of standalone features
</step>

<step name="resolve_feature">
Determine which feature to start and its location:

**If feature-id provided without --release:**

```bash
FEATURE_ID=${ARG}

# Check if it's a standalone feature
STANDALONE_DIR="features/${FEATURE_ID}"
if [ -d "$STANDALONE_DIR" ]; then
  FEATURE_DIR="$STANDALONE_DIR"
  FEATURE_RELEASE=null
fi

# Check if it's a release feature (in focused release)
FOCUSED_RELEASE=$(cat .planning/state.yaml | yq '.focus.release')
if [ -n "$FOCUSED_RELEASE" ]; then
  # Find feature directory matching ID pattern (e.g., "02" matches "02-auth")
  RELEASE_FEATURE_DIR=$(ls -d "releases/${FOCUSED_RELEASE}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
  if [ -n "$RELEASE_FEATURE_DIR" ]; then
    FEATURE_DIR="$RELEASE_FEATURE_DIR"
    FEATURE_RELEASE="$FOCUSED_RELEASE"
  fi
fi
```

**If feature-id with --release provided:**

```bash
FEATURE_ID=${ARG}
RELEASE_ID=${RELEASE_ARG}
RELEASE_FEATURE_DIR=$(ls -d "releases/${RELEASE_ID}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
if [ -n "$RELEASE_FEATURE_DIR" ]; then
  FEATURE_DIR="$RELEASE_FEATURE_DIR"
  FEATURE_RELEASE="$RELEASE_ID"
fi
```

**If no argument (start next in focused release):**

```bash
FOCUSED_RELEASE=$(cat .planning/state.yaml | yq '.focus.release')
if [ -z "$FOCUSED_RELEASE" ] || [ "$FOCUSED_RELEASE" == "null" ]; then
  echo "No focused release. Use --release or /release focus first."
  exit 1
fi

# Find first pending feature in release
RELEASE_FILE="releases/${FOCUSED_RELEASE}/release.yaml"
PENDING_FEATURE=$(cat "$RELEASE_FILE" | yq '.features.list[] | select(.status == "pending") | .id' | head -1)
FEATURE_DIR="releases/${FOCUSED_RELEASE}/features/${PENDING_FEATURE}"
FEATURE_RELEASE="$FOCUSED_RELEASE"
```

**Validate feature exists:**
```bash
if [ -z "$FEATURE_DIR" ] || [ ! -d "$FEATURE_DIR" ]; then
  echo "Feature not found: ${FEATURE_ID}"
  echo ""
  echo "Available features:"
  echo "  Release features: /feature list --release <id>"
  echo "  Standalone features: /feature list --standalone"
  exit 1
fi
```
</step>

<step name="check_preconditions">
Verify feature can be started:

**1. Check no other feature in progress:**
```bash
CURRENT_STATUS=$(cat .planning/state.yaml | yq '.feature.status')
if [ "$CURRENT_STATUS" == "in_progress" ] || [ "$CURRENT_STATUS" == "planning" ] || [ "$CURRENT_STATUS" == "researching" ] || [ "$CURRENT_STATUS" == "verifying" ]; then
  CURRENT_FEATURE=$(cat .planning/state.yaml | yq '.feature.id')
  echo "Feature ${CURRENT_FEATURE} is already in progress."
  echo "Complete or pause it before starting another."
  exit 1
fi
```

**2. Check dependencies (if defined in feature.yaml):**
```bash
FEATURE_YAML="${FEATURE_DIR}/feature.yaml"
DEPENDS_ON=$(cat "$FEATURE_YAML" | yq '.depends_on[]' 2>/dev/null)
for dep in $DEPENDS_ON; do
  # For release features, check in same release
  if [ -n "$FEATURE_RELEASE" ]; then
    DEP_DIR="releases/${FEATURE_RELEASE}/features/${dep}"
  else
    DEP_DIR="features/${dep}"
  fi
  DEP_STATUS=$(cat "${DEP_DIR}/feature.yaml" 2>/dev/null | yq '.status')
  if [ "$DEP_STATUS" != "completed" ]; then
    echo "Feature ${FEATURE_ID} depends on feature ${dep} which is not completed."
    exit 1
  fi
done
```
</step>

<step name="load_feature_context">
Load feature definition:

```bash
# Read feature.yaml
cat "${FEATURE_DIR}/feature.yaml"
```

Display feature overview:

```
═══════════════════════════════════════════════════════════════
STARTING FEATURE: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Title: ${TITLE}
Goal:  ${GOAL}

${IF_RELEASE_FEATURE}
Release: ${FEATURE_RELEASE}
${ELSE}
Type: Standalone
${END_IF}

Success criteria:
  - ${CRITERIA_1}
  - ${CRITERIA_2}

───────────────────────────────────────────────────────────────
```
</step>

<step name="acquire_state_lock">
Acquire state lock (set lock.held_by, lock.acquired_at, lock.expires_at in state.yaml):

```yaml
lock:
  held_by: feature-start
  acquired_at: ${TIMESTAMP}
  expires_at: ${TIMESTAMP + 60s}
```
</step>

<step name="update_state">
Update state.yaml to reflect feature start:

```yaml
# Update focus
focus:
  release: ${FOCUS_RELEASE}          # Keep current or set to feature's release
  feature: ${FEATURE_ID}
  feature_release: ${FEATURE_RELEASE}  # null if standalone

# Update feature section
feature:
  id: ${FEATURE_ID}
  release: ${FEATURE_RELEASE}         # null if standalone
  status: researching
  started_at: ${TIMESTAMP}
  tasks:
    total: 0
    completed: 0
    current: null

session:
  last_activity: ${TIMESTAMP}
  last_action: "Started feature ${FEATURE_ID}"
  last_error: null                   # XC-003: Clear last_error on success

  resume:
    context: |
      Starting Feature: ${FEATURE_ID} (${TITLE}).
      ${IF_RELEASE}Release: ${FEATURE_RELEASE}.${END_IF}
      ${IF_STANDALONE}Standalone feature.${END_IF}
      Need to create plan or explore codebase.

updated_at: ${TIMESTAMP}
updated_by: feature-start
```

Compute and set `_checksum` on state.yaml (XC-002).
</step>

<step name="release_state_lock">
Release state lock (clear lock fields in state.yaml):

```yaml
lock:
  held_by: null
  acquired_at: null
  expires_at: null
```
</step>

<step name="update_feature_yaml">
Update feature.yaml status:

```yaml
status: researching
started_at: ${TIMESTAMP}
```
</step>

<step name="commit_start">
Commit feature start artifacts:

```bash
git add .planning/state.yaml "${FEATURE_DIR}/feature.yaml" && git commit -m "chore: start feature ${FEATURE_ID}"
```
</step>

<step name="report_success">
Report feature started:

```
═══════════════════════════════════════════════════════════════
FEATURE STARTED: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Title:    ${TITLE}
Status:   researching
Location: ${FEATURE_DIR}
${IF_RELEASE}Release:  ${FEATURE_RELEASE}${END_IF}
${IF_STANDALONE}Type:     Standalone${END_IF}
Started:  ${TIMESTAMP}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /research            — Research if needed
  /feature plan        — Create execution plan
  /feature execute     — Execute feature tasks
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).

**Feature already in progress:**
```
Feature ${CURRENT} is already in progress.

Options:
  /feature complete ${CURRENT}  — Complete current feature first
  /feature start ${NEW} --force — Pause current and start new

Use --force only if current feature work should be paused.
```

**Missing dependencies:**
```
Feature ${ID} has unmet dependencies:

Required: Feature ${DEP} (${DEP_NAME})
Status:   ${DEP_STATUS}

Complete dependent features first.
```

**Feature not found:**
```
Feature not found: ${FEATURE_ID}

To find features:
  /feature list --release ${RELEASE_ID}  — List release features
  /feature list --standalone             — List standalone features
  /feature list                          — List all features
```

</error_handling>

<invariants>
- Only one feature can be in_progress at a time
- state.yaml always reflects current feature
- feature.yaml status matches state.yaml
- Feature can be release-scoped or standalone
- focus.feature_release tracks which release the feature belongs to (or null)
</invariants>
