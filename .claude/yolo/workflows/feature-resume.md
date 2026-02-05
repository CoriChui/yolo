<purpose>
Resume an in-progress feature by loading its current state and context.
Determines where the feature left off and routes to the appropriate next action.
Supports both release-scoped and standalone features.
</purpose>

<triggers>
- `/yolo:feature resume <feature-id>` - Resume a specific feature
- `/yolo:feature resume` - Resume the currently focused feature from state.yaml
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
- `focus.feature_release` - Release the feature belongs to
- `feature.status` - Current feature status
- `session.last_activity` - When last action occurred
- `session.last_action` - What was last done
</step>

<step name="determine_feature">
Determine which feature to resume:

**If feature-id provided:**

```bash
FEATURE_ID=${ARG}
```

**If no feature-id provided:**

```bash
FEATURE_ID=$(cat .planning/state.yaml | yq '.focus.feature')

if [ -z "$FEATURE_ID" ] || [ "$FEATURE_ID" == "null" ]; then
  echo "No feature specified and no focused feature in state.yaml."
  echo ""
  echo "Usage:"
  echo "  /yolo:feature resume <feature-id>"
  echo "  /yolo:feature resume  (requires a focused feature)"
  echo ""
  echo "Set focus with /feature start <id> first."
  exit 1
fi
```
</step>

<step name="locate_feature">
Find the feature directory. Check release-scoped first, then standalone:

```bash
FEATURE_RELEASE=$(cat .planning/state.yaml | yq '.focus.feature_release')

# 1. Check in the feature's known release (from state)
if [ -n "$FEATURE_RELEASE" ] && [ "$FEATURE_RELEASE" != "null" ]; then
  FEATURE_DIR=$(ls -d ".planning/releases/${FEATURE_RELEASE}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
fi

# 2. If not found, check focused release
if [ -z "$FEATURE_DIR" ]; then
  FOCUSED_RELEASE=$(cat .planning/state.yaml | yq '.focus.release')
  if [ -n "$FOCUSED_RELEASE" ] && [ "$FOCUSED_RELEASE" != "null" ]; then
    FEATURE_DIR=$(ls -d ".planning/releases/${FOCUSED_RELEASE}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
    if [ -n "$FEATURE_DIR" ]; then
      FEATURE_RELEASE="$FOCUSED_RELEASE"
    fi
  fi
fi

# 3. If still not found, check standalone features
if [ -z "$FEATURE_DIR" ]; then
  FEATURE_DIR=$(ls -d ".planning/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
  if [ -n "$FEATURE_DIR" ]; then
    FEATURE_RELEASE=null
  fi
fi

# 4. Validate feature exists
if [ -z "$FEATURE_DIR" ] || [ ! -d "$FEATURE_DIR" ]; then
  echo "Feature not found: ${FEATURE_ID}"
  echo ""
  echo "Searched in:"
  echo "  .planning/releases/*/features/${FEATURE_ID}-*"
  echo "  .planning/features/${FEATURE_ID}-*"
  echo ""
  echo "Use /feature list to see available features."
  exit 1
fi
```
</step>

<step name="load_feature">
Read feature definition and current state:

```bash
# Read feature.yaml
FEATURE_YAML=$(cat "${FEATURE_DIR}/feature.yaml")
FEATURE_TITLE=$(echo "$FEATURE_YAML" | yq '.title')
FEATURE_GOAL=$(echo "$FEATURE_YAML" | yq '.goal')
FEATURE_STATUS=$(echo "$FEATURE_YAML" | yq '.status')
SUCCESS_CRITERIA=$(echo "$FEATURE_YAML" | yq '.success_criteria[]')
DEPENDS_ON=$(echo "$FEATURE_YAML" | yq '.depends_on[]' 2>/dev/null)

# Check if feature is already completed
if [ "$FEATURE_STATUS" == "completed" ]; then
  echo "Feature ${FEATURE_ID} is already completed."
  echo ""
  echo "Location: ${FEATURE_DIR}"
  echo "Use /feature list to find an active feature."
  exit 1
fi
```
</step>

<step name="build_context">
Based on feature status, gather the relevant context for resumption.

First, check for a pipeline checkpoint that may override status-based routing:

```bash
# Check for pipeline checkpoint
CHECKPOINT_FILE="${FEATURE_DIR}/checkpoint.yaml"
if [ -f "$CHECKPOINT_FILE" ]; then
  CHECKPOINT_STAGE=$(cat "$CHECKPOINT_FILE" | yq '.current_stage')
  echo "Found pipeline checkpoint at stage: ${CHECKPOINT_STAGE}"

  # Route based on checkpoint stage
  case "$CHECKPOINT_STAGE" in
    research)
      echo "Resuming pipeline from plan stage (research complete)"
      # Trigger: /feature plan (research output available from checkpoint)
      ;;
    plan)
      echo "Resuming pipeline from execute stage (plan complete)"
      # Trigger: /feature execute (plan output available from checkpoint)
      ;;
    execute)
      echo "Resuming execution with task skip"
      # Trigger: /feature execute (will skip completed tasks)
      ;;
  esac

  # Show checkpoint info in status display
fi
```

Then, fall through to status-based routing:

**If status is `researching`:**
```bash
# Research is in progress, load any partial findings
echo "Status: researching — Research phase in progress"

# Check for any partial research output
if [ -f "${FEATURE_DIR}/research.md" ]; then
  echo "Partial research found: ${FEATURE_DIR}/research.md"
  cat "${FEATURE_DIR}/research.md"
fi

RESUME_HINT="Continue research or create plan"
NEXT_COMMAND="/yolo:feature plan"
```

**If status is `planning`:**
```bash
# Research done, plan may be partial
echo "Status: planning — Planning phase in progress"

# Load research output if available
if [ -f "${FEATURE_DIR}/research.md" ]; then
  echo "Research output: ${FEATURE_DIR}/research.md"
  cat "${FEATURE_DIR}/research.md"
fi

# Check if plan.md exists but is incomplete
if [ -f "${FEATURE_DIR}/plan.md" ]; then
  echo "Partial plan found: ${FEATURE_DIR}/plan.md"
  cat "${FEATURE_DIR}/plan.md"
fi

RESUME_HINT="Complete plan creation"
NEXT_COMMAND="/yolo:feature plan"
```

**If status is `in_progress`:**
```bash
# Execution underway — load plan and check task progress
echo "Status: in_progress — Execution underway"

# Load plan
if [ -f "${FEATURE_DIR}/plan.md" ]; then
  cat "${FEATURE_DIR}/plan.md"
fi

# Check task progress from state.yaml
TASKS_TOTAL=$(cat .planning/state.yaml | yq '.feature.tasks.total')
TASKS_COMPLETED=$(cat .planning/state.yaml | yq '.feature.tasks.completed')
TASKS_CURRENT=$(cat .planning/state.yaml | yq '.feature.tasks.current')

echo "Tasks: ${TASKS_COMPLETED}/${TASKS_TOTAL} completed"
echo "Current task: ${TASKS_CURRENT}"

# Check for summary.md (indicates execution finished but not verified)
if [ -f "${FEATURE_DIR}/summary.md" ]; then
  echo "Execution summary found — execution may be complete"
  RESUME_HINT="Verify feature or continue remaining tasks"
  NEXT_COMMAND="/yolo:feature verify"
else
  RESUME_HINT="Continue executing tasks"
  NEXT_COMMAND="/yolo:feature execute"
fi
```

**If status is `verifying`:**
```bash
# Verification in progress
echo "Status: verifying — Verification in progress"

# Load verification results so far
if [ -f "${FEATURE_DIR}/verification.md" ]; then
  echo "Partial verification found: ${FEATURE_DIR}/verification.md"
  cat "${FEATURE_DIR}/verification.md"
fi

RESUME_HINT="Complete verification"
NEXT_COMMAND="/yolo:feature verify"
```

**If status is `blocked`:**
```bash
# Feature is blocked
echo "Status: blocked"

BLOCK_REASON=$(echo "$FEATURE_YAML" | yq '.block_reason // "No reason recorded"')
echo "Block reason: ${BLOCK_REASON}"

RESUME_HINT="Resolve blocker, then continue"
NEXT_COMMAND="Resolve blocker first"
```
</step>

<step name="acquire_state_lock">
Acquire state lock (set lock.held_by, lock.acquired_at, lock.expires_at in state.yaml):

```yaml
lock:
  held_by: feature-resume
  acquired_at: ${TIMESTAMP}
  expires_at: ${TIMESTAMP + 60s}
```
</step>

<step name="update_state">
Update state.yaml to set focus to resumed feature and update session:

```yaml
focus:
  release: ${FEATURE_RELEASE}          # Keep release context or null
  feature: ${FEATURE_ID}
  feature_release: ${FEATURE_RELEASE}  # null if standalone

session:
  last_activity: ${TIMESTAMP}
  last_action: "feature:resume ${FEATURE_ID}"
  last_error: null                     # XC-003: Clear last_error on success

  resume:
    context: |
      Resuming Feature: ${FEATURE_ID} (${FEATURE_TITLE}).
      Status: ${FEATURE_STATUS}.
      ${IF_RELEASE}Release: ${FEATURE_RELEASE}.${END_IF}
      ${IF_STANDALONE}Standalone feature.${END_IF}
      ${RESUME_HINT}

updated_at: ${TIMESTAMP}
updated_by: feature-resume
```

Compute and set `_checksum` on state.yaml (XC-002):

```bash
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i "._checksum = \"${_checksum}\"" .planning/state.yaml
```
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

<step name="display_context">
Display the resumed feature status and context:

```
═══════════════════════════════════════════════════════════════
FEATURE RESUMED: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Title:    ${FEATURE_TITLE}
Goal:     ${FEATURE_GOAL}
Status:   ${FEATURE_STATUS}
Location: ${FEATURE_DIR}
${IF_RELEASE}Release:  ${FEATURE_RELEASE}${END_IF}
${IF_STANDALONE}Type:     Standalone${END_IF}

${IF_IN_PROGRESS}
Progress: ${TASKS_COMPLETED}/${TASKS_TOTAL} tasks completed
Current:  ${TASKS_CURRENT}
${END_IF}

Success Criteria:
  - ${CRITERIA_1}
  - ${CRITERIA_2}

───────────────────────────────────────────────────────────────
CONTEXT: ${RESUME_HINT}
───────────────────────────────────────────────────────────────
```
</step>

<step name="route_next">
Suggest next command based on current feature status:

**If `researching` or `planning`:**
```
NEXT STEPS:
  /yolo:feature plan     — Create or continue execution plan
  /research              — Continue research if needed
═══════════════════════════════════════════════════════════════
```

**If `in_progress`:**
```
NEXT STEPS:
  /yolo:feature execute  — Continue executing tasks
  /yolo:feature verify   — Verify if execution is complete
═══════════════════════════════════════════════════════════════
```

**If `verifying`:**
```
NEXT STEPS:
  /yolo:feature verify   — Continue verification
  /yolo:feature complete — Mark complete (if verification passed)
═══════════════════════════════════════════════════════════════
```

**If `blocked`:**
```
BLOCKER DETAILS:
  Reason: ${BLOCK_REASON}

NEXT STEPS:
  Resolve the blocker, then:
  /yolo:feature execute  — Continue execution
  /yolo:feature plan     — Re-plan if approach changed
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).

**Feature not found:**
```
Feature not found: ${FEATURE_ID}

Searched in:
  .planning/releases/*/features/${FEATURE_ID}-*
  .planning/features/${FEATURE_ID}-*

To find features:
  /feature list --release <id>  — Release features
  /feature list --standalone    — Standalone features
  /feature list                 — All features
```

**Feature already completed:**
```
Feature ${FEATURE_ID} is already completed.

Location: ${FEATURE_DIR}
Completed: ${COMPLETED_AT}

Use /feature list to find an active feature.
```

**No active feature:**
```
No feature specified and no focused feature in state.yaml.

Usage:
  /yolo:feature resume <feature-id>  — Resume specific feature
  /yolo:feature resume               — Resume focused feature

Start a feature first with /feature start <id>.
```

</error_handling>

<invariants>
- Read-only except for focus and session fields in state.yaml
- Never modifies feature.yaml or plan.md
- Only updates focus.feature, focus.feature_release, and session fields
- state.yaml always reflects the resumed feature as current focus
- Checksum recomputed after state.yaml update
</invariants>
