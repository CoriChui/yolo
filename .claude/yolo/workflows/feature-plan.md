<purpose>
Create the execution plan (plan.md) for a feature.
Plans are based on CODEBASE exploration, with intake as optional context.
Supports both release-scoped and standalone features.
</purpose>

<triggers>
- `/feature plan <feature-id>` - Create plan for specific feature
- `/feature plan` - Create plan for current planning feature
- `/feature plan --amend` - Amend existing plan for current feature
- `/feature plan --amend "add error handling to all API endpoints"` - Amend with specific instructions
</triggers>

<process>

<step name="validate_feature_status">
Ensure feature is ready for planning:

```bash
FEATURE_STATUS=$(cat .planning/state.yaml | yq '.feature.status')
FEATURE_ID=$(cat .planning/state.yaml | yq '.feature.id')
FEATURE_RELEASE=$(cat .planning/state.yaml | yq '.feature.release')

if [ "$FEATURE_STATUS" != "planning" ] && [ "$FEATURE_STATUS" != "researching" ] && [ "$FEATURE_STATUS" != "in_progress" ]; then
  echo "No feature ready for planning. Use /feature start first."
  exit 1
fi

# Determine feature directory based on release status
if [ "$FEATURE_RELEASE" != "null" ] && [ -n "$FEATURE_RELEASE" ]; then
  # Release-scoped feature
  FEATURE_DIR=$(ls -d "releases/${FEATURE_RELEASE}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
else
  # Standalone feature
  FEATURE_DIR="features/${FEATURE_ID}"
fi
```

Check if plan.md already exists:
```bash
if [ -f "${FEATURE_DIR}/plan.md" ]; then
  if [ "$AMEND_FLAG" = true ]; then
    AMEND_MODE=true
    EXISTING_PLAN=$(cat "${FEATURE_DIR}/plan.md")
    echo "Amendment mode: modifying existing plan"
  else
    echo "plan.md already exists for this feature."
    echo ""
    echo "Options:"
    echo "  /feature execute        — Execute existing plan"
    echo "  /feature plan --amend   — Amend existing plan"
    echo "  rm ${FEATURE_DIR}/plan.md  — Delete and re-plan"
    exit 1
  fi
fi
```
</step>

<step name="check_intake" condition="release feature with intake">
Read intake version for research agent context:

```bash
if [ "$FEATURE_RELEASE" != "null" ] && [ -n "$FEATURE_RELEASE" ]; then
  RELEASE_FILE="releases/${FEATURE_RELEASE}/release.yaml"
  INTAKE_VERSION=$(cat "$RELEASE_FILE" 2>/dev/null | yq '.intake.current')
  RELEASE_GOAL=$(cat "$RELEASE_FILE" 2>/dev/null | yq '.goal')
fi
```

**Note:** Research agent handles intake processing automatically.
</step>

<step name="set_researching_status">
Update state.yaml to reflect research phase (WF-005):

```yaml
feature:
  status: "researching"
```
</step>

<step name="explore_codebase">
```bash
# Skip research in amendment mode — we already have context
if [ "$AMEND_MODE" = true ]; then
  echo "Skipping research (amendment mode)"
  codebase_findings="${EXISTING_PLAN}"
  # Jump to amend_plan step
  continue
fi
```

# Load orchestrator
@orchestration/agent-orchestrator.md

# Spawn research agent
research_result: spawn_agent_with_profile(
  contract: "research",
  input:
    goal: "${FEATURE_GOAL}"
    scope: "${SCOPE:-src/}"
    intake:
      version: "${INTAKE_VERSION}"
      path: "releases/${FEATURE_RELEASE}/intake/${INTAKE_VERSION}"
    depth: "deep"
    include_external: true
    release_context:
      release_id: "${FEATURE_RELEASE}"
      release_goal: "${RELEASE_GOAL}"
  profile: "${PROFILE:-balanced}"
)

# Handle research agent failure (WF-021)
if research_result.status == "failed":
  Log: "Research agent failed: ${research_result.error}"
  Suggest: "Re-run /feature plan, or narrow scope with /feature plan --scope <path>"
  Record session.last_error in state.yaml
  exit 1

# Store findings
codebase_findings: research_result.findings
patterns: research_result.patterns
relevant_files: research_result.relevant_files
</step>

<step name="create_plan">
```bash
# Skip creation in amendment mode — amend_plan handles it
if [ "$AMEND_MODE" = true ]; then
  # amend_plan step will handle plan creation
  continue
fi
```

# Spawn plan agent
plan_result: spawn_agent_with_profile(
  contract: "plan",
  input:
    goal: "${FEATURE_GOAL}"
    context: "${codebase_findings}"
    intake_insights: "${research_result.intake_insights}"
    gaps: "${research_result.gaps}"
    max_tasks: 5
  profile: "${PROFILE:-balanced}"
)

# Handle plan agent failure (WF-021)
if plan_result.status == "failed":
  Log: "Plan agent failed: ${plan_result.error}"
  Suggest: "Re-run /feature plan, or simplify the feature goal"
  Record session.last_error in state.yaml
  exit 1

# Convert to plan.md format
Write "${FEATURE_DIR}/plan.md":
  # Feature: ${FEATURE_ID} - ${FEATURE_TITLE}

  ## Objective
  ${FEATURE_GOAL}

  ## Context
  ${codebase_findings}

  ## Tasks
  ${for task in plan_result.tasks:}
  ### Task ${task.id}: ${task.title}
  ${task.description}

  **Files:** ${task.files}
  **Verification:** ${task.verification}
  ${end for}

  ## Execution Order
  ${plan_result.execution_order}
</step>

<step name="amend_plan" condition="AMEND_MODE is true">
Amend the existing plan instead of creating from scratch:

**Parse existing plan:**

```bash
# Read existing plan
EXISTING_PLAN=$(cat "${FEATURE_DIR}/plan.md")

# Extract completed tasks (checkmarks that should be preserved)
COMPLETED_TASKS=$(grep -n '^\- \[x\]' "${FEATURE_DIR}/plan.md" || true)

# Extract existing task sections
EXISTING_TASKS=$(grep -A 100 '## Tasks' "${FEATURE_DIR}/plan.md" | head -100)

# Read amendment instructions
AMENDMENT_INSTRUCTIONS="${AMEND_ARGS:-}"
```

**Spawn plan agent with amendment context:**

```
plan_result: spawn_agent_with_profile(
  contract: "plan",
  input:
    goal: "${FEATURE_GOAL}"
    context: |
      ## AMENDMENT MODE

      You are AMENDING an existing plan, not creating from scratch.

      ## Existing Plan
      ${EXISTING_PLAN}

      ## Completed Tasks (DO NOT MODIFY)
      These tasks are already done — preserve their checkmarks:
      ${COMPLETED_TASKS}

      ## Amendment Instructions
      ${AMENDMENT_INSTRUCTIONS}

      ## Rules
      1. Keep completed tasks exactly as-is ([x] checkmarks preserved)
      2. You may add new tasks, modify uncompleted tasks, or reorder uncompleted tasks
      3. Do NOT remove or modify completed tasks
      4. Update the execution order to reflect changes
      5. Keep task IDs stable where possible (renumbering only for new inserts)
    intake_insights: null
    gaps: null
    max_tasks: 10   # Allow more tasks for amendments
  profile: "${PROFILE:-balanced}"
)

if plan_result.status == "failed":
  Log: "Plan amendment failed: ${plan_result.error}"
  Record session.last_error in state.yaml
  exit 1
```

**Backup and write amended plan:**

```bash
# Backup existing plan
cp "${FEATURE_DIR}/plan.md" "${FEATURE_DIR}/plan.md.bak"

# Write amended plan (plan agent output)
Write "${FEATURE_DIR}/plan.md"

# Verify completed tasks preserved
NEW_COMPLETED=$(grep -c '^\- \[x\]' "${FEATURE_DIR}/plan.md" || echo 0)
OLD_COMPLETED=$(grep -c '^\- \[x\]' "${FEATURE_DIR}/plan.md.bak" || echo 0)

if [ "$NEW_COMPLETED" -lt "$OLD_COMPLETED" ]; then
  echo "WARNING: Amendment lost completed task checkmarks!"
  echo "Restoring backup — review manually"
  cp "${FEATURE_DIR}/plan.md.bak" "${FEATURE_DIR}/plan.md"
  exit 1
fi

# Clean up backup on success
rm -f "${FEATURE_DIR}/plan.md.bak"
```
</step>

<step name="acquire_state_lock_plan">
Acquire state lock (set lock.held_by, lock.acquired_at, lock.expires_at in state.yaml):

```yaml
lock:
  held_by: feature-plan
  acquired_at: ${TIMESTAMP}
  expires_at: ${TIMESTAMP + 60s}
```
</step>

<step name="update_state">
Update state.yaml:

```yaml
feature:
  id: ${FEATURE_ID}
  release: ${FEATURE_RELEASE}    # null if standalone
  status: in_progress
  plan_created_at: ${TIMESTAMP}

  tasks:
    total: ${TASK_COUNT}          # May be different after amendment
    completed: ${COMPLETED_COUNT}  # Preserve existing completed count (0 for new plans)
    current: "${FIRST_UNCOMPLETED_TASK}"

session:
  last_activity: ${TIMESTAMP}
  last_action: "${AMEND_MODE ? 'Amended' : 'Created'} plan for feature ${FEATURE_ID}"
  last_error: null                   # XC-003: Clear last_error on success

  resume:
    context: |
      Feature ${FEATURE_ID}: ${FEATURE_TITLE}
      ${IF_RELEASE}Release: ${FEATURE_RELEASE}${END_IF}
      ${IF_STANDALONE}Standalone feature${END_IF}
      Plan created with ${TASK_COUNT} tasks.
      Ready to execute.

updated_at: ${TIMESTAMP}
updated_by: feature-plan
```

Compute and set `_checksum` on state.yaml (XC-002).
</step>

<step name="release_state_lock_plan">
Release state lock (clear lock fields in state.yaml):

```yaml
lock:
  held_by: null
  acquired_at: null
  expires_at: null
```
</step>

<step name="report_success">
Report plan created:

```
═══════════════════════════════════════════════════════════════
PLAN CREATED: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:  ${FEATURE_TITLE}
${IF_RELEASE}Release:  ${FEATURE_RELEASE}${END_IF}
${IF_STANDALONE}Type:     Standalone${END_IF}
Plan:     ${FEATURE_DIR}/plan.md
Tasks:    ${TASK_COUNT}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature execute  — Execute the plan
  cat ${FEATURE_DIR}/plan.md  — Review plan first
═══════════════════════════════════════════════════════════════
```

**If amendment mode:**
```
═══════════════════════════════════════════════════════════════
PLAN AMENDED: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:  ${FEATURE_TITLE}
${IF_RELEASE}Release:  ${FEATURE_RELEASE}${END_IF}
Plan:     ${FEATURE_DIR}/plan.md
Tasks:    ${TASK_COUNT} (${COMPLETED_COUNT} completed, ${NEW_TASKS} new/modified)

Changes:
  ${AMENDMENT_SUMMARY}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature execute  — Execute the amended plan (skips completed tasks)
  cat ${FEATURE_DIR}/plan.md  — Review amended plan
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).

**No feature in progress:**
```
No feature is currently in planning state.

Use /feature start <id> to start a feature first.

To find features:
  /feature list --release <id>  — Release features
  /feature list --standalone    — Standalone features
```

**Plan already exists:**
```
plan.md already exists for this feature.

Location: ${FEATURE_DIR}/plan.md

Options:
  /feature execute            — Execute existing plan
  /feature plan --amend       — Amend existing plan
  /feature plan --amend "..."  — Amend with instructions
  rm ${FEATURE_DIR}/plan.md   — Delete and re-plan from scratch

Use --amend to modify tasks without losing completed work.
```

</error_handling>

<notes>
- Planning explores CODEBASE first (source of truth)
- Intake is auxiliary context (optional, only for release features)
- Tasks should be granular enough for atomic commits
- plan.md is the execution contract for the feature
- Feature directory depends on release vs standalone status
- Amendment mode preserves completed tasks and only modifies pending work
- Plan backup (.bak) is created before amendment for safety
- Completed task checkmarks are verified after amendment
</notes>
