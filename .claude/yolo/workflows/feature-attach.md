<purpose>
Attach a standalone feature to a release.
Moves the feature directory from .planning/features/ to .planning/releases/<id>/features/
and assigns it a sequential ID within the release.
</purpose>

<triggers>
- `/feature attach <feature-slug> <release-id>` - Attach standalone feature to release
</triggers>

<process>

<step name="load_state">
Read current project state:

```bash
cat .planning/state.yaml
```

Extract:
- `standalone_features.list` - List of standalone features
- `releases` - Array of active releases
- `focus` - Current focus state
</step>

<step name="validate_inputs">
Validate the feature and release:

**1. Validate feature exists and is standalone:**
```bash
FEATURE_SLUG=${ARG_1}
# Note: FEATURE_SLUG matches the slug portion of the feature directory name
STANDALONE_DIR=".planning/features/${FEATURE_SLUG}"

if [ ! -d "$STANDALONE_DIR" ]; then
  echo "Standalone feature not found: ${FEATURE_SLUG}"
  echo ""
  echo "Available standalone features:"
  ls -1 .planning/features/ 2>/dev/null || echo "  (none)"
  exit 1
fi

# Read feature.yaml to verify it's standalone
FEATURE_RELEASE=$(cat "${STANDALONE_DIR}/feature.yaml" | yq '.release')
if [ "$FEATURE_RELEASE" != "null" ] && [ -n "$FEATURE_RELEASE" ]; then
  echo "Feature ${FEATURE_SLUG} is already attached to release: ${FEATURE_RELEASE}"
  echo "Use /feature detach first to move it to a different release."
  exit 1
fi
```

**2. Validate release exists and is active:**
```bash
RELEASE_ID=${ARG_2}
RELEASE_DIR=".planning/releases/${RELEASE_ID}"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "Release not found: ${RELEASE_ID}"
  echo ""
  echo "Available releases:"
  ls -1 .planning/releases/ 2>/dev/null || echo "  (none)"
  exit 1
fi

RELEASE_STATUS=$(cat "${RELEASE_DIR}/release.yaml" | yq '.status')
if [ "$RELEASE_STATUS" == "completed" ]; then
  echo "Cannot attach to completed release: ${RELEASE_ID}"
  exit 1
fi
if [ "$RELEASE_STATUS" == "failed" ]; then
  echo "Cannot attach to failed release: ${RELEASE_ID}"
  exit 1
fi
if [ "$RELEASE_STATUS" == "cancelled" ]; then
  echo "Cannot attach to cancelled release: ${RELEASE_ID}"
  exit 1
fi
```
</step>

<step name="check_feature_status">
Check if feature is currently in progress:

```bash
FEATURE_STATUS=$(cat "${STANDALONE_DIR}/feature.yaml" | yq '.status')
CURRENT_FEATURE=$(cat .planning/state.yaml | yq '.feature.id')

# Guard: reject attach for active features unless --force is used
if [[ "$FEATURE_STATUS" =~ ^(researching|planning|in_progress|verifying)$ ]]; then
  if [ "$FORCE_FLAG" != "true" ]; then
    echo "Cannot attach feature in '${FEATURE_STATUS}' state."
    echo "Use --force to override, or wait until the feature is pending/completed."
    exit 1
  fi
fi

if [ "$CURRENT_FEATURE" == "$FEATURE_SLUG" ]; then
  echo "Warning: Feature ${FEATURE_SLUG} is currently active."
  echo "Proceeding will update the current feature context."
fi
```
</step>

<step name="calculate_new_id">
Determine the sequential ID for the feature in the release:

```bash
# Count existing features in release
FEATURES_DIR="${RELEASE_DIR}/features"
mkdir -p "$FEATURES_DIR"

# Find highest existing number
HIGHEST=$(ls -1 "$FEATURES_DIR" 2>/dev/null | grep -E "^[0-9]+" | sort -n | tail -1 | cut -d'-' -f1)
if [ -z "$HIGHEST" ]; then
  HIGHEST=0
fi

# New ID is highest + 1
NEW_NUM=$((HIGHEST + 1))
NEW_ID=$(printf "%02d" $NEW_NUM)
NEW_FEATURE_ID="${NEW_ID}-${FEATURE_SLUG}"
```
</step>

<step name="move_feature_directory">
Move feature from standalone to release:

```bash
SOURCE_DIR=".planning/features/${FEATURE_SLUG}"
TARGET_DIR="${RELEASE_DIR}/features/${NEW_FEATURE_ID}"

# Move the directory
mv "$SOURCE_DIR" "$TARGET_DIR"
```
</step>

<step name="update_feature_yaml">
Update feature.yaml with release information:

```yaml
# ${TARGET_DIR}/feature.yaml

id: "${NEW_ID}"
name: ${FEATURE_SLUG}
# ... existing fields ...

# Update context
release: "${RELEASE_ID}"
```

Also update:
- `id` field to the new sequential ID
- Keep all other fields intact
</step>

<step name="update_release_yaml">
Add feature to release.yaml features list:

```yaml
# ${RELEASE_DIR}/release.yaml

features:
  total: ${TOTAL + 1}
  completed: ${COMPLETED}

  list:
    # ... existing features ...
    - id: "${NEW_FEATURE_ID}"
      name: ${FEATURE_SLUG}
      status: ${FEATURE_STATUS}
      attached_at: ${TIMESTAMP}
```
</step>

<step name="update_state">
# Acquire state lock
Update state.yaml:

```yaml
# Update releases array - increment feature count
releases:
  - id: "${RELEASE_ID}"
    progress:
      features_total: ${TOTAL + 1}
      # ... other fields ...

# Update standalone_features - remove from list
standalone_features:
  total: ${TOTAL - 1}
  list:
    # Remove ${FEATURE_SLUG} from list

# If this was the current feature, update focus
${IF_CURRENT_FEATURE}
focus:
  feature: "${NEW_FEATURE_ID}"
  feature_release: "${RELEASE_ID}"

feature:
  id: "${NEW_FEATURE_ID}"
  release: "${RELEASE_ID}"
  # ... keep other fields ...
${END_IF}

session:
  last_activity: ${TIMESTAMP}
  last_action: "Attached feature ${FEATURE_SLUG} to release ${RELEASE_ID}"
  last_error: null                    # Cleared on success

  resume:
    context: |
      Attached standalone feature ${FEATURE_SLUG} to release ${RELEASE_ID}.
      New feature ID: ${NEW_FEATURE_ID}
      Location: ${TARGET_DIR}

updated_at: ${TIMESTAMP}
updated_by: feature-attach
_checksum: ${COMPUTED_CHECKSUM}       # Recomputed after write
```

# Release state lock

On failure, record error before releasing lock:
```yaml
session:
  last_error: "${ERROR_MESSAGE}"
```
</step>

<step name="commit_changes">
Commit the attach operation:

```bash
git add .planning/

git commit -m "chore: attach feature ${FEATURE_SLUG} to release ${RELEASE_ID}

- Moved: .planning/features/${FEATURE_SLUG} -> .planning/releases/${RELEASE_ID}/features/${NEW_FEATURE_ID}
- New ID: ${NEW_FEATURE_ID}
- Updated release.yaml and state.yaml
"
```
</step>

<step name="report_success">
Report successful attach:

```
═══════════════════════════════════════════════════════════════
FEATURE ATTACHED
═══════════════════════════════════════════════════════════════

Feature:     ${FEATURE_SLUG}
New ID:      ${NEW_FEATURE_ID}
Release:     ${RELEASE_ID}

Old location: .planning/features/${FEATURE_SLUG}
New location: ${TARGET_DIR}

───────────────────────────────────────────────────────────────
RELEASE PROGRESS

${RELEASE_ID}: ${COMPLETED}/${NEW_TOTAL} features
${PROGRESS_BAR}

Features:
  ${FEATURE_LIST}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature start ${NEW_FEATURE_ID}  — Start working on feature
  /feature list --release ${RELEASE_ID}  — See all release features
  /release status ${RELEASE_ID}  — See release status
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

**Feature not found:**
```
Standalone feature not found: ${FEATURE_SLUG}

Available standalone features:
  ${LIST_OF_STANDALONE_FEATURES}

Usage: /feature attach <feature-slug> <release-id>
```

**Feature already attached:**
```
Feature ${FEATURE_SLUG} is already attached to release: ${CURRENT_RELEASE}

To move to a different release:
  1. /feature detach ${FEATURE_SLUG} ${CURRENT_RELEASE}
  2. /feature attach ${FEATURE_SLUG} ${NEW_RELEASE}
```

**Release not found:**
```
Release not found: ${RELEASE_ID}

Available releases:
  ${LIST_OF_RELEASES}

Usage: /feature attach <feature-slug> <release-id>
```

**Release completed:**
```
Cannot attach to completed release: ${RELEASE_ID}

The release has already been completed and archived.
Create a new release or attach to an active release.
```

</error_handling>

<invariants>
- Feature moves from .planning/features/ to .planning/releases/<id>/features/
- Feature gets a sequential ID within the release (e.g., 04-dark-mode)
- feature.yaml updated with release reference
- release.yaml updated with new feature in list
- state.yaml updated: standalone_features decremented, release progress updated
- If feature was current, focus is updated
- Git commit tracks the operation
</invariants>

<notes>
- Features cannot move directly between releases (must detach first)
- Feature status is preserved during attach
- Feature work history (research, plan, summary) is preserved
- Sequential IDs ensure proper ordering within release
</notes>
