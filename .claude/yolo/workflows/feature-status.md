<purpose>
Display detailed status of a specific feature including lifecycle position, task progress,
success criteria, blocking info, associated files, and suggested next action.
Purely read-only — never modifies any files.
</purpose>

<triggers>
- `/yolo:feature status [feature-id]` - Show feature status (uses focused feature if no ID given)
</triggers>

<process>

<step name="load_state">
Read project state:

```bash
STATE=$(cat .planning/state.yaml 2>/dev/null)
if [ -z "$STATE" ]; then
  # No state — show error
  exit 1
fi

FOCUSED_FEATURE=$(echo "$STATE" | yq '.focus.feature')
FEATURE_RELEASE=$(echo "$STATE" | yq '.focus.feature_release')
FOCUSED_RELEASE=$(echo "$STATE" | yq '.focus.release')
```
</step>

<step name="determine_feature">
Determine which feature to display:

```bash
if [ -n "$ARG_FEATURE_ID" ]; then
  FEATURE_ID="$ARG_FEATURE_ID"
elif [ -n "$FOCUSED_FEATURE" ] && [ "$FOCUSED_FEATURE" != "null" ]; then
  FEATURE_ID="$FOCUSED_FEATURE"
else
  # No feature specified and no focused feature — show error
  exit 1
fi
```
</step>

<step name="locate_feature">
Find the feature directory. Check release-scoped first, then standalone:

```bash
# Determine which release to look in
if [ -n "$FEATURE_RELEASE" ] && [ "$FEATURE_RELEASE" != "null" ]; then
  SEARCH_RELEASE="$FEATURE_RELEASE"
elif [ -n "$FOCUSED_RELEASE" ] && [ "$FOCUSED_RELEASE" != "null" ]; then
  SEARCH_RELEASE="$FOCUSED_RELEASE"
else
  SEARCH_RELEASE=""
fi

FEATURE_DIR=""

# 1. Check release-scoped features
if [ -n "$SEARCH_RELEASE" ]; then
  MATCH=$(ls -d .planning/releases/${SEARCH_RELEASE}/features/${FEATURE_ID}-* 2>/dev/null | head -1)
  if [ -n "$MATCH" ]; then
    FEATURE_DIR="$MATCH"
  fi
fi

# 2. Check all releases if not found in focused release
if [ -z "$FEATURE_DIR" ]; then
  MATCH=$(ls -d .planning/releases/*/features/${FEATURE_ID}-* 2>/dev/null | head -1)
  if [ -n "$MATCH" ]; then
    FEATURE_DIR="$MATCH"
  fi
fi

# 3. Check standalone features
if [ -z "$FEATURE_DIR" ]; then
  MATCH=$(ls -d .planning/features/${FEATURE_ID}-* 2>/dev/null | head -1)
  if [ -n "$MATCH" ]; then
    FEATURE_DIR="$MATCH"
  fi
fi

if [ -z "$FEATURE_DIR" ]; then
  # Feature not found — show error
  exit 1
fi
```
</step>

<step name="load_feature">
Read the feature definition:

```bash
FEATURE_YAML=$(cat "${FEATURE_DIR}/feature.yaml")

TITLE=$(echo "$FEATURE_YAML" | yq '.title')
STATUS=$(echo "$FEATURE_YAML" | yq '.status')
RELEASE=$(echo "$FEATURE_YAML" | yq '.release')
PROFILE=$(echo "$FEATURE_YAML" | yq '.profile')
STARTED_AT=$(echo "$FEATURE_YAML" | yq '.started_at')
CRITERIA=$(echo "$FEATURE_YAML" | yq '.success_criteria[]')
BLOCKED_SINCE=$(echo "$FEATURE_YAML" | yq '.blocked.since')
BLOCKED_REASON=$(echo "$FEATURE_YAML" | yq '.blocked.reason')
BLOCKED_DEPENDENCY=$(echo "$FEATURE_YAML" | yq '.blocked.dependency')
```
</step>

<step name="load_plan">
Read the plan if it exists (may not exist if still researching):

```bash
PLAN_EXISTS=false
TASKS=()

if [ -f "${FEATURE_DIR}/plan.md" ]; then
  PLAN_EXISTS=true
  # Parse tasks from plan.md
  # Tasks are typically listed as checklist items: - [ ] or - [x]
  TASKS=$(grep -E '^\s*-\s*\[[ x→]\]' "${FEATURE_DIR}/plan.md")
  TOTAL=$(echo "$TASKS" | wc -l)
  COMPLETED=$(echo "$TASKS" | grep -c '\[x\]')
  CURRENT=$(echo "$TASKS" | grep -c '\[→\]')
fi
```
</step>

<step name="load_verification">
Read verification if it exists:

```bash
VERIFICATION_EXISTS=false
if [ -f "${FEATURE_DIR}/verification.md" ]; then
  VERIFICATION_EXISTS=true
fi
```

Also check for research:

```bash
RESEARCH_EXISTS=false
if [ -f "${FEATURE_DIR}/research.md" ]; then
  RESEARCH_EXISTS=true
fi
```
</step>

<step name="display_status">
Display formatted feature status:

```
═══════════════════════════════════════════════════════════════════
FEATURE STATUS: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════════

  Title:    ${TITLE}
  Status:   ${STATUS}
  Release:  ${RELEASE || "standalone"}
  Profile:  ${PROFILE || "balanced"}
  Started:  ${STARTED_AT || "not started"}

───────────────────────────────────────────────────────────────────
LIFECYCLE
───────────────────────────────────────────────────────────────────

  pending -> researching -> planning -> in_progress -> verifying -> completed
                                                                    ^ YOU ARE HERE

  (Arrow points to current status. If blocked/dropped, shown separately.)

───────────────────────────────────────────────────────────────────
TASKS                                          ${COMPLETED}/${TOTAL}
───────────────────────────────────────────────────────────────────

  [v] Task 1 title
  [v] Task 2 title
  [>] Task 3 title (current)
  [ ] Task 4 title
  [ ] Task 5 title

  (If plan.md does not exist: "No plan yet. Feature is in ${STATUS} phase.")

───────────────────────────────────────────────────────────────────
SUCCESS CRITERIA
───────────────────────────────────────────────────────────────────

  - Criterion 1
  - Criterion 2
  - Criterion 3

  (If no criteria defined: "No success criteria defined.")

───────────────────────────────────────────────────────────────────
BLOCKED                              (only shown if status == blocked)
───────────────────────────────────────────────────────────────────

  Since:      ${BLOCKED_SINCE}
  Reason:     ${BLOCKED_REASON}
  Dependency: ${BLOCKED_DEPENDENCY || "none"}

───────────────────────────────────────────────────────────────────
FILES
───────────────────────────────────────────────────────────────────

  Feature:      ${FEATURE_DIR}/feature.yaml
  Plan:         ${FEATURE_DIR}/plan.md          ${PLAN_EXISTS ? "v" : "-"}
  Research:     ${FEATURE_DIR}/research.md      ${RESEARCH_EXISTS ? "v" : "-"}
  Verification: ${FEATURE_DIR}/verification.md  ${VERIFICATION_EXISTS ? "v" : "-"}

───────────────────────────────────────────────────────────────────
NEXT STEP
───────────────────────────────────────────────────────────────────

  ${route based on status — see determine_next_step}

═══════════════════════════════════════════════════════════════════
```
</step>

<step name="determine_next_step">
Route suggested next action based on current status:

| Status | Suggested Action |
|--------|------------------|
| pending | `/yolo:feature plan` to begin planning |
| researching | `/yolo:feature plan` to continue into planning |
| planning | `/yolo:feature plan` to finalize the plan |
| in_progress | `/yolo:feature execute` to continue implementation |
| verifying | `/yolo:feature verify` to run verification |
| blocked | Resolve blocker, then `/yolo:feature resume` |
| completed | Feature is done! |
| dropped | Feature was dropped. No further action. |
</step>

</process>

<error_handling>

**No state file:**
```
═══════════════════════════════════════════════════════════════════
NO PROJECT FOUND
═══════════════════════════════════════════════════════════════════

No .planning/state.yaml found.

Initialize with /yolo:init first.
═══════════════════════════════════════════════════════════════════
```

**No feature specified and no focused feature:**
```
═══════════════════════════════════════════════════════════════════
NO FEATURE SPECIFIED
═══════════════════════════════════════════════════════════════════

No feature ID provided and no feature is currently focused.

Options:
  /yolo:feature status <feature-id>  — Show specific feature
  /yolo:feature start <feature-id>   — Start and focus a feature
  /yolo:status                       — View project overview
═══════════════════════════════════════════════════════════════════
```

**Feature not found:**
```
═══════════════════════════════════════════════════════════════════
FEATURE NOT FOUND: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════════

No feature matching "${FEATURE_ID}" found in:
  - .planning/releases/*/features/
  - .planning/features/

Check the feature ID and try again.
Use /yolo:status to see available features.
═══════════════════════════════════════════════════════════════════
```

</error_handling>

<invariants>
- PURELY READ-ONLY. Never modifies any files.
- No lock needed. No state.yaml writes.
- Does not create, update, or delete any file or directory.
- Safe to run at any time without side effects.
</invariants>
