<purpose>
Start a pending release — moves to ACTIVE status and runs research.
This explores the codebase, defines features, and auto-creates them.
Supports optional release ID parameter (defaults to focused release).
</purpose>

<triggers>
- `/release start` - Start the focused release
- `/release start <id>` - Start specific release by ID
</triggers>

<process>

<step name="determine_release">
Determine which release to start:

**If ID provided:**
```bash
RELEASE_ID=${ARG}
```

**If no ID:**
```bash
RELEASE_ID=$(cat .planning/state.yaml | yq '.focus.release')
```

Validate release exists and is pending:
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
Create one with /release new <slug>
═══════════════════════════════════════════════════════════════
```

**If already active:**
```
═══════════════════════════════════════════════════════════════
RELEASE ALREADY ACTIVE
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" is already active.
Use /release status to see progress.
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

**If completed:**
```
═══════════════════════════════════════════════════════════════
RELEASE ALREADY COMPLETED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" has already been completed.
Use /release status ${RELEASE_ID} to view its archive.
═══════════════════════════════════════════════════════════════
```

**If failed:**
```
═══════════════════════════════════════════════════════════════
RELEASE FAILED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" is in a failed state.
Investigate or create a new release with /release new <slug>
═══════════════════════════════════════════════════════════════
```

**If cancelled:**
```
═══════════════════════════════════════════════════════════════
RELEASE CANCELLED
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" has been cancelled.
Create a new release with /release new <slug>
═══════════════════════════════════════════════════════════════
```
</step>

<step name="read_intake">
Read captured intake for AUXILIARY context:

```bash
INTAKE_VERSION=$(cat ".planning/releases/${RELEASE_ID}/release.yaml" | yq '.intake.current')
INTAKE_DIR=".planning/releases/${RELEASE_ID}/intake/${INTAKE_VERSION}"
cat "${INTAKE_DIR}/manifest.yaml"
cat "${INTAKE_DIR}/*/digest.md" 2>/dev/null
```

Intake provides:
- Design references (Figma)
- External requirements (Notion)
- Context notes

**Remember:** Intake is auxiliary. Codebase is truth.
</step>

<step name="explore_codebase">
# PROFILE loaded from .claude/yolo/config.yaml or defaulting to "balanced"

# Load orchestrator
@orchestration/agent-orchestrator.md

# Spawn research agent for release-level exploration
research_result: spawn_agent_with_profile(
  contract: "research",
  input:
    goal: "Understand codebase architecture for release ${RELEASE_ID}"
    scope: "src/"
    intake:
      version: "${INTAKE_VERSION}"
      path: ".planning/releases/${RELEASE_ID}/intake/${INTAKE_VERSION}"
    depth: "deep"
  profile: "${PROFILE:-balanced}"
)

# Store findings for next steps
codebase_findings: research_result.findings
intake_insights: research_result.intake_insights
patterns: research_result.patterns
</step>

<step name="define_release_goal">
Based on codebase exploration and intake context, define:

**1. Goal statement:**
What will this release achieve? Be specific.

**2. Success criteria:**
Observable outcomes that prove the goal is met.

Present to user for approval:
```
═══════════════════════════════════════════════════════════════
RELEASE GOAL
═══════════════════════════════════════════════════════════════

Goal:
  ${RELEASE_GOAL}

Success Criteria:
  - ${CRITERION_1}
  - ${CRITERION_2}
  - ${CRITERION_3}

Does this look correct?
═══════════════════════════════════════════════════════════════
```
</step>

<step name="auto_create_features">
# Spawn plan agent for feature breakdown
plan_result: spawn_agent_with_profile(
  contract: "plan",
  input:
    goal: "${RELEASE_GOAL}"
    context: "${codebase_findings}"
    intake_insights: "${intake_insights}"
    gaps: "${research_result.gaps}"
    max_tasks: 10
    constraints:
      - "Each task represents a feature, not implementation step"
      - "Features should be independently deliverable"
  profile: "${PROFILE:-balanced}"
)

# Convert plan tasks to features
features: []
for task in plan_result.tasks:
  features.append({
    id: task.id,
    name: slugify(task.title),
    goal: task.description,
    depends_on: task.depends_on,
    status: "pending"
  })

Present feature breakdown to user for review:
```
═══════════════════════════════════════════════════════════════
FEATURES (auto-created from research)
═══════════════════════════════════════════════════════════════

${for feature in features}
  ${feature.id}: ${feature.name}
      "${feature.goal}"
${endfor}

Review the feature breakdown. Adjust if needed.
═══════════════════════════════════════════════════════════════
```
</step>

<step name="create_feature_directories">
Create feature directories inside release:

```bash
FEATURE_BASE=".planning/releases/${RELEASE_ID}/features"

for feature in ${FEATURES}; do
  FEATURE_ID=$(echo "$feature" | yq '.id')
  FEATURE_NAME=$(echo "$feature" | yq '.name')
  FEATURE_DIR="${FEATURE_BASE}/${FEATURE_ID}-${FEATURE_NAME}"

  mkdir -p "$FEATURE_DIR"

  cat > "$FEATURE_DIR/feature.yaml" << EOF
id: ${FEATURE_ID}
name: ${FEATURE_NAME}
release: ${RELEASE_ID}
status: pending

goal: |
  ${FEATURE_GOAL}

depends_on: []

created: ${TIMESTAMP}
EOF
done
```
</step>

<step name="create_requirements">
Create requirements.md with detailed requirements traced to features:

```markdown
# Requirements — ${RELEASE_ID}

## Overview
${RELEASE_GOAL}

## Success Criteria
- ${CRITERION_1}
- ${CRITERION_2}

## Feature Breakdown

### Feature 01: Foundation
${FEATURE_01_REQUIREMENTS}

### Feature 02: Auth
${FEATURE_02_REQUIREMENTS}

...
```
</step>

<step name="update_release_file">
Update .planning/releases/${RELEASE_ID}/release.yaml:

```yaml
id: "${RELEASE_ID}"
slug: "${RELEASE_SLUG}"
title: "${RELEASE_TITLE}"
created: ${CREATED_TIMESTAMP}

goal: |
  ${RELEASE_GOAL}

success_criteria:
  - ${CRITERION_1}
  - ${CRITERION_2}

intake:
  current: "${INTAKE_VERSION}"
  locked: false

features:
  total: ${FEATURE_COUNT}
  completed: 0
  list:
    - id: "01"
      name: foundation
      status: pending
    - id: "02"
      name: auth
      status: pending
    - id: "03"
      name: billing
      status: pending

progress:
  features_total: ${FEATURE_COUNT}
  features_completed: 0
  percentage: 0

status: active
started_at: ${TIMESTAMP}
completed_at: null
paused_at: null
failed_at: null
cancelled_at: null

archive: null
```
</step>

<step name="update_state">
# Acquire state lock
Update .planning/state.yaml:

```yaml
focus:
  release: "${RELEASE_ID}"

releases:
  - id: "${RELEASE_ID}"
    slug: "${RELEASE_SLUG}"
    status: active                    # Updated from pending
    created: ${CREATED_TIMESTAMP}
    started_at: ${TIMESTAMP}          # Set start time
    intake:
      current: "${INTAKE_VERSION}"
      locked: false
    progress:
      features_total: ${FEATURE_COUNT}
      features_completed: 0
      percentage: 0
  # ... other releases unchanged ...

session:
  last_activity: ${TIMESTAMP}
  last_action: "release-start ${RELEASE_ID}"
  last_error: null                    # Cleared on success

updated_at: ${TIMESTAMP}
updated_by: release-start
_checksum: ${COMPUTED_CHECKSUM}       # Recomputed after write
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
RELEASE STARTED: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Goal:
  ${RELEASE_GOAL}

Features: ${FEATURE_COUNT} (auto-created)
  01: foundation
  02: auth
  03: billing

Intake: ${INTAKE_VERSION} (${SOURCE_COUNT} sources)
Requirements: .planning/releases/${RELEASE_ID}/requirements.md

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature start 01  — Start first feature
  /status            — View release status
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<notes>
- Supports optional release ID parameter (defaults to focused release)
- Requires a pending release
- Explores codebase to understand reality
- Uses intake as auxiliary context
- Auto-creates features from research (user reviews breakdown)
- Creates requirements.md traced to features
- Features created in .planning/releases/id/features/ (release-scoped)
- Intake remains OPEN — can still capture during active release
</notes>
