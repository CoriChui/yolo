<purpose>
Execute the tasks defined in a feature's plan.md.
Each task is executed atomically with its own commit.
Supports both release-scoped and standalone features.
</purpose>

<triggers>
- `/feature execute <feature-id>` - Execute specific feature
- `/feature execute` - Execute current in_progress feature
</triggers>

<required_reading>
Read state.yaml and feature.yaml before any operation.
Read plan.md for execution instructions.
</required_reading>

<process>

<step name="validate_feature_ready">
Ensure feature is ready for execution:

```bash
FEATURE_ID=$(cat .planning/state.yaml | yq '.feature.id')
FEATURE_STATUS=$(cat .planning/state.yaml | yq '.feature.status')
FEATURE_RELEASE=$(cat .planning/state.yaml | yq '.feature.release')

# Determine feature directory based on release status
if [ "$FEATURE_RELEASE" != "null" ] && [ -n "$FEATURE_RELEASE" ]; then
  # Release-scoped feature
  FEATURE_DIR=$(ls -d "releases/${FEATURE_RELEASE}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
else
  # Standalone feature
  FEATURE_DIR="features/${FEATURE_ID}"
fi

# Must be in_progress
if [ "$FEATURE_STATUS" != "in_progress" ]; then
  echo "Feature is not ready for execution (status: ${FEATURE_STATUS})"
  exit 1
fi

# Must have plan.md
if [ ! -f "${FEATURE_DIR}/plan.md" ]; then
  echo "No plan.md found. Run /feature plan first."
  exit 1
fi

# Check for existing checkpoint (pipeline resume)
CHECKPOINT_FILE="${FEATURE_DIR}/checkpoint.yaml"
HAS_CHECKPOINT=false
SKIP_TASKS=0

if [ -f "$CHECKPOINT_FILE" ]; then
  HAS_CHECKPOINT=true
  CHECKPOINT_STAGE=$(cat "$CHECKPOINT_FILE" | yq '.current_stage')
  TASKS_COMPLETED=$(cat "$CHECKPOINT_FILE" | yq '.outputs.tasks_completed // 0')

  echo "Found checkpoint: stage=${CHECKPOINT_STAGE}, tasks_completed=${TASKS_COMPLETED}"

  if [ "$CHECKPOINT_STAGE" = "execute" ]; then
    # Partial execution — skip completed tasks
    SKIP_TASKS=${TASKS_COMPLETED}
    echo "Resuming execution from task $((SKIP_TASKS + 1))"
  fi
fi
```
</step>

<step name="load_execution_context">
Load all context needed for execution:

```bash
# Load plan
PLAN_CONTENT=$(cat "${FEATURE_DIR}/plan.md")

# Load feature definition
FEATURE_YAML=$(cat "${FEATURE_DIR}/feature.yaml")
FEATURE_TITLE=$(echo "$FEATURE_YAML" | yq '.title')

# Record execution start
EXEC_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
```
</step>

<step name="check_needs_decision">
Check if plan output indicates a pending design decision (WF-022):

```bash
# Check if plan.md contains a needs_decision marker
if grep -q "needs_decision" "${FEATURE_DIR}/plan.md" 2>/dev/null; then
  echo "WARNING: A design decision is pending for this feature."
  echo "Review plan.md for details before proceeding."
  echo "Use /feature plan --resolve to address pending decisions."
fi
```
</step>

<step name="parse_tasks">
Extract tasks from plan.md:

Parse each `### Task N:` section to get:
- Task name
- Description
- Files to create/modify
- Verification criteria
- Done criteria

Build task list:
```
tasks = [
  {num: 1, name: "...", files: [...], verify: [...], done: [...]},
  {num: 2, name: "...", files: [...], verify: [...], done: [...]},
  ...
]
```
</step>

<step name="checkpoint_before_task">
Record a git checkpoint before each task execution:

```bash
# Save current HEAD as rollback point
ROLLBACK_SHA=$(git rev-parse HEAD)

# Record in memory for this execution
TASK_CHECKPOINTS[${task.num}]="${ROLLBACK_SHA}"
```

This enables rollback if the task or its fix attempt fails.
</step>

<step name="execute_tasks">
# Load orchestrator
@orchestration/agent-orchestrator.md

for task in parsed_tasks:
  # Skip tasks completed in previous run (checkpoint resume)
  if [ ${task.num} -le ${SKIP_TASKS} ]; then
    echo "Skipping task ${task.num} (completed in previous run)"
    continue
  fi

  # Update state: starting task
  Update state.yaml: feature.tasks.current = task.name

  # Spawn execute agent
  task_result: spawn_agent_with_profile(
    contract: "execute",
    input:
      task:
        id: task.num
        title: task.name
        description: task.description
        files: task.files
        verification: task.verify     # WF-013: field named "verification" per execute contract
      context: task.files
      style_guide: null               # WF-012: explicit null for style_guide
    profile: "${PROFILE:-balanced}"
  )

  # Handle result
  if task_result.status == "completed":
    # Commit using agent's suggested message
    git add ${task_result.files_changed[*].path}
    git commit -m "${task_result.commit_message}"

    completed_tasks.append({
      num: task.num,
      name: task.name,
      commit: git rev-parse --short HEAD,
      files: task_result.files_changed
    })

    # Save execution checkpoint
    cat > "${CHECKPOINT_FILE}" << EOF
    pipeline: feature-full
    feature_id: "${FEATURE_ID}"
    updated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
    current_stage: execute
    outputs:
      tasks_completed: ${#completed_tasks[@]}
      tasks_total: ${#parsed_tasks[@]}
    EOF

  elif task_result.status == "blocked":
    # Log blocker and continue or stop based on severity
    Log: "Task ${task.num} blocked: ${task_result.blockers}"

    # Rollback changes from blocked task
    if [ -n "${ROLLBACK_SHA}" ]; then
      # Revert files changed by the blocked task
      CHANGED_FILES=$(git diff --name-only ${ROLLBACK_SHA} HEAD)
      if [ -n "$CHANGED_FILES" ]; then
        git checkout ${ROLLBACK_SHA} -- ${CHANGED_FILES}
        git commit -m "revert(${FEATURE_ID}): rollback blocked task ${task.num}

Task: ${task.name}
Rolled back to: ${ROLLBACK_SHA}"
      fi
    fi

    # Trigger error handling
    trigger: on-execution-failed
    context:
      task: task
      blockers: task_result.blockers
      status: "blocked"

  elif task_result.status == "failed":
    # Attempt fix with execute agent (WF-011: use spawn_agent_with_profile)
    fix_result: spawn_agent_with_profile(
      contract: "execute",
      input:
        task:
          id: task.num
          title: "Fix: ${task.name}"
          description: |
            Original task failed. Error: ${task_result.notes}
            Fix the issues and complete the task.
          files: task_result.files_changed[*].path || task.files
          verification: task.verify
        context: task_result.files_changed[*].path || task.files
        previous_attempt:
          error: task_result.notes
          files_changed: task_result.files_changed[*].path
      profile: "${PROFILE:-balanced}"
    )

    if fix_result.status == "completed":
      # Commit the fix
      git add ${fix_result.files_changed[*].path}
      git commit -m "${fix_result.commit_message}"
      completed_tasks.append({
        num: task.num,
        name: task.name,
        commit: git rev-parse --short HEAD,
        files: fix_result.files_changed
      })
    else:
      # Escalate - stop execution
      Log: "Task ${task.num} failed after fix attempt"

      # Rollback changes from failed task
      if [ -n "${ROLLBACK_SHA}" ]; then
        # Revert files changed by the failed task
        CHANGED_FILES=$(git diff --name-only ${ROLLBACK_SHA} HEAD)
        if [ -n "$CHANGED_FILES" ]; then
          git checkout ${ROLLBACK_SHA} -- ${CHANGED_FILES}
          git commit -m "revert(${FEATURE_ID}): rollback failed task ${task.num}

Task: ${task.name}
Rolled back to: ${ROLLBACK_SHA}"
        fi
      fi

      # Trigger error handling
      trigger: on-execution-failed
      context:
        task: task
        error: fix_result.notes
        status: "failed"
        fix_attempted: true

      break
</step>

<step name="rollback_task">
Rollback utility — used when a task fails and its fix attempt also fails:

```bash
# Called with: ROLLBACK_SHA, FEATURE_ID, task.num, task.name
CHANGED_FILES=$(git diff --name-only ${ROLLBACK_SHA} HEAD)

if [ -n "$CHANGED_FILES" ]; then
  echo "Rolling back ${#CHANGED_FILES[@]} files to ${ROLLBACK_SHA}"
  git checkout ${ROLLBACK_SHA} -- ${CHANGED_FILES}
  git commit -m "revert(${FEATURE_ID}): rollback task ${task.num}

Task: ${task.name}
Rolled back to: ${ROLLBACK_SHA}
Reason: Task failed after fix attempt"

  rollback_count=$((rollback_count + 1))
fi
```

**Rollback rules:**
- Only rollback if fix attempt also fails (give fix a chance first)
- Rollback uses `git checkout <sha> -- <files>` (surgical, not reset)
- Each rollback gets its own commit for traceability
- Track rollback count in execution metrics
</step>

<step name="handle_checkpoints">
If plan.md defines checkpoints:

**checkpoint:human-verify:**
```
╔═══════════════════════════════════════════════════════════════╗
║  CHECKPOINT: Verification Required                            ║
╚═══════════════════════════════════════════════════════════════╝

Feature:  ${FEATURE_ID}
${IF_RELEASE}Release:  ${FEATURE_RELEASE}${END_IF}
Progress: ${COMPLETED}/${TOTAL} tasks complete
Task: ${CHECKPOINT_TASK}

Built: ${WHAT_WAS_BUILT}

How to verify:
  1. ${STEP_1}
  2. ${STEP_2}

────────────────────────────────────────────────────────────────
→ YOUR ACTION: Type "approved" or describe issues
────────────────────────────────────────────────────────────────
```

Wait for user response before continuing.
</step>

<step name="create_summary">
After all tasks complete, create summary.md:

```markdown
# Feature: ${FEATURE_ID} - ${FEATURE_TITLE}

## Summary

**Status:** Executed
${IF_RELEASE}**Release:** ${FEATURE_RELEASE}${ELSE}**Type:** Standalone${END_IF}

## Overview

${ONE_LINE_SUMMARY_OF_ACCOMPLISHMENTS}

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | ${TASK_1_NAME} | ${COMMIT_1} | ${FILES_1} |
| 2 | ${TASK_2_NAME} | ${COMMIT_2} | ${FILES_2} |

## Files Created/Modified

### Created
- `${FILE_1}` - ${DESCRIPTION}

### Modified
- `${FILE_2}` - ${WHAT_CHANGED}

## Deviations from Plan

${IF_DEVIATIONS}
### Auto-fixed Issues

**1. ${DEVIATION_TITLE}**
- Found during: Task ${N}
- Issue: ${DESCRIPTION}
- Fix: ${WHAT_WAS_DONE}
- Files: ${AFFECTED_FILES}
${ELSE}
None — plan executed as written.
${END_IF}

## Rollbacks

${IF_ROLLBACKS}
| Task | Rolled Back To | Files Reverted | Reason |
|------|---------------|----------------|--------|
| ${TASK_NUM} | ${ROLLBACK_SHA} | ${FILE_COUNT} | ${REASON} |
${ELSE}
None — all tasks succeeded.
${END_IF}

## Execution Metrics

- Started: ${EXEC_START}
- Completed: ${EXEC_END}
- Duration: ${DURATION}
- Tasks: ${COMPLETED}/${TOTAL}
- Rollbacks: ${ROLLBACK_COUNT}
- Commits: ${COMMIT_COUNT}
```

Write to `${FEATURE_DIR}/summary.md`.
</step>

<step name="acquire_state_lock_execute">
Acquire state lock (set lock.held_by, lock.acquired_at, lock.expires_at in state.yaml):

```yaml
lock:
  held_by: feature-execute
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
  status: in_progress                # WF-010: stay in_progress, feature-verify handles transition to verifying
  tasks:
    total: ${TASK_COUNT}
    completed: ${COMPLETED_COUNT}
    current: null
  executed_at: ${TIMESTAMP}

session:
  last_activity: ${TIMESTAMP}
  last_action: "Executed feature ${FEATURE_ID}"
  last_error: null                   # XC-003: Clear last_error on success

  resume:
    context: |
      Feature ${FEATURE_ID}: ${FEATURE_TITLE} executed.
      ${IF_RELEASE}Release: ${FEATURE_RELEASE}.${END_IF}
      ${IF_STANDALONE}Standalone feature.${END_IF}
      ${COMPLETED}/${TOTAL} tasks done.
      Ready for verification.

updated_at: ${TIMESTAMP}
updated_by: feature-execute
```

Compute and set `_checksum` on state.yaml (XC-002).
</step>

<step name="release_state_lock_execute">
Release state lock (clear lock fields in state.yaml):

```yaml
lock:
  held_by: null
  acquired_at: null
  expires_at: null
```
</step>

<step name="commit_summary">
Commit execution artifacts:

```bash
git add "${FEATURE_DIR}/summary.md"
git add .planning/state.yaml

git commit -m "docs(${FEATURE_ID}): complete feature execution

Tasks completed: ${TASK_COUNT}/${TOTAL}
Summary: ${FEATURE_DIR}/summary.md
"
```
</step>

<step name="report_completion">
Report execution complete:

```
═══════════════════════════════════════════════════════════════
FEATURE EXECUTED: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:   ${FEATURE_TITLE}
${IF_RELEASE}Release:   ${FEATURE_RELEASE}${END_IF}
${IF_STANDALONE}Type:      Standalone${END_IF}
Tasks:     ${COMPLETED}/${TOTAL} complete
Duration:  ${DURATION}
Commits:   ${COMMIT_COUNT}

Location:  ${FEATURE_DIR}
Summary:   ${FEATURE_DIR}/summary.md

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature verify   — Verify feature achieved its goal
  /feature complete — Mark feature complete
═══════════════════════════════════════════════════════════════
```

```bash
# Clean up checkpoint on successful completion
rm -f "${FEATURE_DIR}/checkpoint.yaml"
```
</step>

</process>

<deviation_rules>
**Rule 1: Auto-fix bugs** — Fix immediately, track in summary
**Rule 2: Auto-add critical** — Add missing security/validation, track
**Rule 3: Auto-fix blocking** — Fix deps/configs that block progress
**Rule 4: Ask about architectural** — STOP for structural changes
</deviation_rules>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).

**Task verification failed:**
Present retry/skip/stop options, record in summary if skipped.

**All tasks failed:**
```
Feature execution failed: no tasks completed successfully.

Feature: ${FEATURE_ID}
Location: ${FEATURE_DIR}

Review errors above and run /feature execute again,
or use /feature plan to revise the plan.
```

</error_handling>

<invariants>
- Each task gets its own atomic commit
- Deviations always tracked in summary
- state.yaml updated after execution
- summary.md created with full execution record
- Feature directory path depends on release vs standalone status
- Failed tasks are rolled back to pre-execution git state
- Rollbacks are surgical (file-level, not hard reset)
- Each rollback gets its own atomic commit for traceability
- Fix attempt runs before rollback (rollback is last resort)
</invariants>
