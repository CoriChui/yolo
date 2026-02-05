<purpose>
Mark a feature as complete after verification passes.
Updates release progress (for release features) and prepares for next feature.
Supports both release-scoped and standalone features.

NOTE (WF-020): This workflow is for manual/CLI-triggered completion.
The pipeline's on_complete handler handles automated pipeline completion separately.
</purpose>

<triggers>
- `/feature complete <feature-id>` - Complete specific feature
- `/feature complete` - Complete current verified feature
</triggers>

<process>

<step name="validate_completion">
Ensure feature is ready to be completed:

```bash
FEATURE_ID=$(cat .planning/state.yaml | yq '.feature.id')
FEATURE_STATUS=$(cat .planning/state.yaml | yq '.feature.status')
FEATURE_RELEASE=$(cat .planning/state.yaml | yq '.feature.release')

# Determine feature directory based on release status
if [ "$FEATURE_RELEASE" != "null" ] && [ -n "$FEATURE_RELEASE" ]; then
  # Release-scoped feature
  FEATURE_DIR=$(ls -d "releases/${FEATURE_RELEASE}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
  IS_RELEASE_FEATURE=true
else
  # Standalone feature
  FEATURE_DIR="features/${FEATURE_ID}"
  IS_RELEASE_FEATURE=false
fi

# WF-019: Valid post-verification status is "verifying" (or "completed" from auto-completion)
if [ "$FEATURE_STATUS" != "verifying" ] && [ "$FEATURE_STATUS" != "completed" ]; then
  echo "Feature cannot be completed (status: ${FEATURE_STATUS})"
  echo "Run /feature verify first."
  exit 1
fi
```

**If status is "verifying" (human verification pending):**
```
Feature verification is in progress (human checks pending).

Options:
1. Complete — Confirm human checks passed, mark complete
2. Re-verify — Run /feature verify to re-check

Select option:
```
</step>

<step name="update_feature_yaml">
Update feature.yaml to completed status:

```yaml
status: completed
completed_at: ${TIMESTAMP}

metrics:
  started_at: ${STARTED_AT}
  completed_at: ${COMPLETED_AT}
  duration: ${DURATION}
  tasks_completed: ${TASK_COUNT}
```
</step>

<step name="update_release_progress" condition="release feature only">
**Only for release-scoped features:**

Update release progress:

```bash
if [ "$IS_RELEASE_FEATURE" = true ]; then
  RELEASE_FILE="releases/${FEATURE_RELEASE}/release.yaml"

  # Read current progress
  FEATURES_COMPLETED=$(cat "$RELEASE_FILE" | yq '.features.completed')
  FEATURES_TOTAL=$(cat "$RELEASE_FILE" | yq '.features.total')
fi
```

Update release.yaml:
```yaml
features:
  completed: ${FEATURES_COMPLETED + 1}
  total: ${FEATURES_TOTAL}

  list:
    - id: ${FEATURE_ID}
      status: completed
      completed_at: ${TIMESTAMP}
```
</step>

<step name="cascade_unblock_dependents">
When a feature completes, check if any other features were blocked on it and auto-unblock them:

**For release features — check within same release:**

```bash
UNBLOCKED_FEATURES=()

if [ "$IS_RELEASE_FEATURE" = true ]; then
  # Scan all features in the same release
  for feature_dir in releases/${FEATURE_RELEASE}/features/*/; do
    if [ ! -f "${feature_dir}/feature.yaml" ]; then continue; fi

    OTHER_STATUS=$(cat "${feature_dir}/feature.yaml" | yq '.status')
    OTHER_DEPENDS=$(cat "${feature_dir}/feature.yaml" | yq '.depends_on[]' 2>/dev/null)
    OTHER_ID=$(cat "${feature_dir}/feature.yaml" | yq '.id')

    # Skip if not blocked
    if [ "$OTHER_STATUS" != "blocked" ]; then continue; fi

    # Check if this feature was in their depends_on
    DEPENDS_ON_US=false
    for dep in $OTHER_DEPENDS; do
      if [ "$dep" = "${FEATURE_ID}" ] || [ "$dep" = "${FEATURE_ID}-${FEATURE_NAME}" ]; then
        DEPENDS_ON_US=true
        break
      fi
    done

    if [ "$DEPENDS_ON_US" = false ]; then continue; fi

    # Check if ALL their dependencies are now completed
    ALL_DEPS_MET=true
    for dep in $OTHER_DEPENDS; do
      DEP_DIR=$(ls -d "releases/${FEATURE_RELEASE}/features/${dep}-"* 2>/dev/null | head -1)
      if [ -z "$DEP_DIR" ]; then
        DEP_DIR=$(ls -d "releases/${FEATURE_RELEASE}/features/${dep}" 2>/dev/null)
      fi
      DEP_STATUS=$(cat "${DEP_DIR}/feature.yaml" 2>/dev/null | yq '.status')
      if [ "$DEP_STATUS" != "completed" ]; then
        ALL_DEPS_MET=false
        break
      fi
    done

    if [ "$ALL_DEPS_MET" = true ]; then
      # Auto-unblock: transition from blocked back to pending
      echo "Auto-unblocking feature ${OTHER_ID} — all dependencies met"
      yq -i '.status = "pending" | .blocked.since = null | .blocked.reason = null | .blocked.dependency = null | .blocked.type = null' "${feature_dir}/feature.yaml"
      UNBLOCKED_FEATURES+=("${OTHER_ID}")
    fi
  done
fi
```

**For standalone features — check all standalone features:**

```bash
if [ "$IS_RELEASE_FEATURE" = false ]; then
  for feature_dir in features/*/; do
    if [ ! -f "${feature_dir}/feature.yaml" ]; then continue; fi

    OTHER_STATUS=$(cat "${feature_dir}/feature.yaml" | yq '.status')
    OTHER_DEPENDS=$(cat "${feature_dir}/feature.yaml" | yq '.depends_on[]' 2>/dev/null)
    OTHER_ID=$(cat "${feature_dir}/feature.yaml" | yq '.id')

    if [ "$OTHER_STATUS" != "blocked" ]; then continue; fi

    # Check if this feature was in their depends_on
    DEPENDS_ON_US=false
    for dep in $OTHER_DEPENDS; do
      if [ "$dep" = "${FEATURE_ID}" ]; then
        DEPENDS_ON_US=true
        break
      fi
    done

    if [ "$DEPENDS_ON_US" = false ]; then continue; fi

    # Check if ALL their dependencies are now completed
    ALL_DEPS_MET=true
    for dep in $OTHER_DEPENDS; do
      DEP_DIR=$(ls -d "features/${dep}" 2>/dev/null)
      DEP_STATUS=$(cat "${DEP_DIR}/feature.yaml" 2>/dev/null | yq '.status')
      if [ "$DEP_STATUS" != "completed" ]; then
        ALL_DEPS_MET=false
        break
      fi
    done

    if [ "$ALL_DEPS_MET" = true ]; then
      echo "Auto-unblocking feature ${OTHER_ID} — all dependencies met"
      yq -i '.status = "pending" | .blocked.since = null | .blocked.reason = null | .blocked.dependency = null | .blocked.type = null' "${feature_dir}/feature.yaml"
      UNBLOCKED_FEATURES+=("${OTHER_ID}")
    fi
  done
fi
```
</step>

<step name="update_standalone_features" condition="standalone feature only">
**Only for standalone features:**

Update state.yaml standalone_features section:

```bash
if [ "$IS_RELEASE_FEATURE" = false ]; then
  # Update standalone_features list in state.yaml
  # Mark feature as completed
fi
```
</step>

<step name="acquire_state_lock_complete">
Acquire state lock (set lock.held_by, lock.acquired_at, lock.expires_at in state.yaml):

```yaml
lock:
  held_by: feature-complete
  acquired_at: ${TIMESTAMP}
  expires_at: ${TIMESTAMP + 60s}
```
</step>

<step name="update_state">
Update state.yaml:

```yaml
# Clear focus feature (completed)
focus:
  release: ${FOCUS_RELEASE}           # Keep current
  feature: null                        # Clear - no active feature
  feature_release: null

# Update feature section
feature:
  id: ${FEATURE_ID}
  release: ${FEATURE_RELEASE}          # null if standalone
  status: completed
  completed_at: ${TIMESTAMP}

${IF_RELEASE_FEATURE}
# Update release progress in releases array
releases:
  - id: ${FEATURE_RELEASE}
    progress:
      features_completed: ${NEW_COUNT}
      features_total: ${TOTAL}
      percentage: ${PERCENTAGE}
${END_IF}

${IF_STANDALONE_FEATURE}
# Update standalone_features list
standalone_features:
  list:
    - id: ${FEATURE_ID}
      status: completed
${END_IF}

session:
  last_activity: ${TIMESTAMP}
  last_action: "Completed feature ${FEATURE_ID}"
  last_error: null                   # XC-003: Clear last_error on success

  resume:
    context: |
      Completed Feature: ${FEATURE_ID} (${FEATURE_TITLE}).
      ${IF_RELEASE}Release ${FEATURE_RELEASE} progress: ${NEW_COUNT}/${TOTAL}.${END_IF}
      ${IF_STANDALONE}Standalone feature completed.${END_IF}
      ${NEXT_ACTION_HINT}

updated_at: ${TIMESTAMP}
updated_by: feature-complete
```

Compute and set `_checksum` on state.yaml (XC-002).
</step>

<step name="release_state_lock_complete">
Release state lock (clear lock fields in state.yaml):

```yaml
lock:
  held_by: null
  acquired_at: null
  expires_at: null
```
</step>

<step name="commit_completion">
Commit feature completion:

```bash
git add "${FEATURE_DIR}/feature.yaml"
${IF_RELEASE_FEATURE}
git add "${RELEASE_FILE}"
${END_IF}
git add .planning/state.yaml

# Include unblocked feature.yaml files in commit
if [ ${#UNBLOCKED_FEATURES[@]} -gt 0 ]; then
  for f in "${UNBLOCKED_FEATURES[@]}"; do
    git add releases/${FEATURE_RELEASE}/features/${f}*/feature.yaml 2>/dev/null
    git add features/${f}/feature.yaml 2>/dev/null
  done
fi

git commit -m "docs(${FEATURE_ID}): mark feature complete

Feature: ${FEATURE_ID} - ${FEATURE_TITLE}
${IF_RELEASE}Release: ${FEATURE_RELEASE}
Release progress: ${COMPLETED}/${TOTAL} features${END_IF}
${IF_STANDALONE}Type: Standalone${END_IF}
Duration: ${DURATION}
"
```
</step>

<step name="determine_next_action">
Determine what's next:

**For release features:**
```bash
if [ "$IS_RELEASE_FEATURE" = true ]; then
  # Check if more features remain in release
  NEXT_FEATURE=$(cat "$RELEASE_FILE" | yq '.features.list[] | select(.status == "pending") | .id' | head -1)

  # Check if release is complete
  REMAINING=$(cat "$RELEASE_FILE" | yq '.features.list[] | select(.status != "completed")' | wc -l)
fi
```

**If more release features remain:**
- Next action: `/feature start ${NEXT_FEATURE}`

**If release complete:**
- Next action: `/release end`

**For standalone features:**
- Check for other pending standalone features
- Or suggest starting work on a release
</step>

<step name="report_completion">
Report feature completed:

**Release feature with more features remaining:**
```
═══════════════════════════════════════════════════════════════
FEATURE COMPLETE: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:   ${FEATURE_TITLE}
Release:   ${FEATURE_RELEASE}
Duration:  ${DURATION}
Progress:  ${COMPLETED}/${TOTAL} features (${PERCENTAGE}%)

Location:  ${FEATURE_DIR}
Summary:   ${FEATURE_DIR}/summary.md

───────────────────────────────────────────────────────────────
NEXT UP

Feature ${NEXT_FEATURE}: ${NEXT_NAME}
${NEXT_GOAL}

  /feature start ${NEXT_FEATURE}

Tip: /clear first for fresh context
═══════════════════════════════════════════════════════════════
```

**Release feature with release complete:**
```
═══════════════════════════════════════════════════════════════
FEATURE COMPLETE: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:   ${FEATURE_TITLE}
Release:   ${FEATURE_RELEASE}
Duration:  ${DURATION}

Location:  ${FEATURE_DIR}

╔═══════════════════════════════════════════════════════════════╗
║  RELEASE COMPLETE!                                            ║
║                                                               ║
║  All ${TOTAL} features finished.                              ║
║  Release: ${FEATURE_RELEASE}                                  ║
╚═══════════════════════════════════════════════════════════════╝

───────────────────────────────────────────────────────────────
NEXT STEPS

  /release end — Archive release, generate output specs
═══════════════════════════════════════════════════════════════
```

**Standalone feature completed:**
```
═══════════════════════════════════════════════════════════════
FEATURE COMPLETE: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:   ${FEATURE_TITLE}
Type:      Standalone
Duration:  ${DURATION}

Location:  ${FEATURE_DIR}
Summary:   ${FEATURE_DIR}/summary.md

───────────────────────────────────────────────────────────────
${IF_MORE_STANDALONE}
OTHER STANDALONE FEATURES

  ${PENDING_FEATURE_1}: ${TITLE_1}
  ${PENDING_FEATURE_2}: ${TITLE_2}

  /feature start <id>  — Start another standalone feature
${END_IF}

${IF_ACTIVE_RELEASES}
ACTIVE RELEASES

  ${RELEASE_1}: ${RELEASE_PROGRESS_1}
  ${RELEASE_2}: ${RELEASE_PROGRESS_2}

  /feature start <id> --release <release>  — Work on release feature
${END_IF}

  /feature attach ${FEATURE_ID} <release>  — Attach to a release
═══════════════════════════════════════════════════════════════
```

**Unblocked features section (appended to any of the above reports when applicable):**
```
${IF_UNBLOCKED}
───────────────────────────────────────────────────────────────
UNBLOCKED FEATURES
  ${for each unblocked_id in UNBLOCKED_FEATURES:}
  ✓ ${unblocked_id} — all dependencies now met
  ${endfor}

  These features can now be started.
${END_IF}
```
</step>

</process>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).

**Feature not verified:**
```
Feature was not verified.

Feature: ${FEATURE_ID}
Location: ${FEATURE_DIR}

Verification ensures feature achieved its goal, not just completed tasks.

Options:
1. Run /feature verify first (recommended)
2. Complete without verification (risky)
```

</error_handling>

<notes>
- Completion updates both feature and release tracking (for release features)
- Standalone features update standalone_features in state.yaml
- Release completion triggers output spec generation
- All state changes committed for audit trail
- Feature can be attached to a release after completion if desired
- Completing a feature auto-unblocks dependents (cascading dependency resolution)
- Only transitions from blocked → pending (user must explicitly start unblocked features)
</notes>
