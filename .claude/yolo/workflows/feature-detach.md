<purpose>
Detach a feature from a release to make it standalone.
Moves the feature directory from .planning/releases/<id>/features/ to .planning/features/
and converts the ID to a slug.
</purpose>

<triggers>
- `/feature detach <feature-id> <release-id>` - Detach feature from release
- `/feature detach <feature-id>` - Detach from focused release (if feature found there)
</triggers>

<process>

<step name="load_state">
Read current project state:

```bash
cat .planning/state.yaml
```

Extract:
- `focus.release` - Currently focused release
- `releases` - Array of active releases
- `standalone_features` - Standalone features list
</step>

<step name="resolve_feature_and_release">
Determine which feature and release:

**If release-id provided:**
```bash
FEATURE_ID=${ARG_1}
RELEASE_ID=${ARG_2}
```

**If only feature-id provided:**
```bash
FEATURE_ID=${ARG_1}

# Try focused release first
FOCUSED_RELEASE=$(cat .planning/state.yaml | yq '.focus.release')
if [ -n "$FOCUSED_RELEASE" ] && [ "$FOCUSED_RELEASE" != "null" ]; then
  FEATURE_DIR=$(ls -d ".planning/releases/${FOCUSED_RELEASE}/features/${FEATURE_ID}"* 2>/dev/null | head -1)
  if [ -n "$FEATURE_DIR" ]; then
    RELEASE_ID="$FOCUSED_RELEASE"
  fi
fi

# If not found, search all releases
if [ -z "$RELEASE_ID" ]; then
  for release in $(ls .planning/releases/); do
    FEATURE_DIR=$(ls -d ".planning/releases/${release}/features/${FEATURE_ID}"* 2>/dev/null | head -1)
    if [ -n "$FEATURE_DIR" ]; then
      RELEASE_ID="$release"
      break
    fi
  done
fi

if [ -z "$RELEASE_ID" ]; then
  echo "Feature ${FEATURE_ID} not found in any release."
  exit 1
fi
```
</step>

<step name="validate_inputs">
Validate the feature and release:

**1. Validate release exists:**
```bash
RELEASE_DIR=".planning/releases/${RELEASE_ID}"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "Release not found: ${RELEASE_ID}"
  exit 1
fi
```

**2. Validate feature exists in release:**
```bash
FEATURE_DIR=$(ls -d "${RELEASE_DIR}/features/${FEATURE_ID}"* 2>/dev/null | head -1)

if [ -z "$FEATURE_DIR" ] || [ ! -d "$FEATURE_DIR" ]; then
  echo "Feature ${FEATURE_ID} not found in release ${RELEASE_ID}"
  echo ""
  echo "Features in ${RELEASE_ID}:"
  ls -1 "${RELEASE_DIR}/features/" 2>/dev/null || echo "  (none)"
  exit 1
fi

# Extract feature name from directory (e.g., "02-auth" -> "auth")
FEATURE_FULL_ID=$(basename "$FEATURE_DIR")
FEATURE_SLUG=$(echo "$FEATURE_FULL_ID" | sed 's/^[0-9]*-//')
```
</step>

<step name="check_feature_status">
Check if feature is currently in progress:

```bash
FEATURE_STATUS=$(cat "${FEATURE_DIR}/feature.yaml" | yq '.status')
CURRENT_FEATURE=$(cat .planning/state.yaml | yq '.feature.id')
CURRENT_RELEASE=$(cat .planning/state.yaml | yq '.feature.release')

# Guard: reject detach for active features unless --force is used
if [[ "$FEATURE_STATUS" =~ ^(researching|planning|in_progress|verifying)$ ]]; then
  if [ "$FORCE_FLAG" != "true" ]; then
    echo "Cannot detach feature in '${FEATURE_STATUS}' state."
    echo "Use --force to override, or wait until the feature is pending/completed."
    exit 1
  fi
fi

if [ "$CURRENT_FEATURE" == "$FEATURE_FULL_ID" ] && [ "$CURRENT_RELEASE" == "$RELEASE_ID" ]; then
  echo "Warning: Feature ${FEATURE_FULL_ID} is currently active."
  echo "Proceeding will update the current feature context."
fi
```
</step>

<step name="check_standalone_conflict">
Check if a standalone feature with the same slug already exists:

```bash
STANDALONE_DIR=".planning/features/${FEATURE_SLUG}"

if [ -d "$STANDALONE_DIR" ]; then
  echo "A standalone feature with slug '${FEATURE_SLUG}' already exists."
  echo ""
  echo "Options:"
  echo "  1. Rename the existing standalone feature"
  # TODO: --as flag not yet implemented
  echo "  2. Use a different slug once --as flag is implemented"
  exit 1
fi
```
</step>

<step name="move_feature_directory">
Move feature from release to standalone:

```bash
SOURCE_DIR="$FEATURE_DIR"
TARGET_DIR=".planning/features/${FEATURE_SLUG}"

# Ensure features directory exists
mkdir -p ".planning/features"

# Move the directory
mv "$SOURCE_DIR" "$TARGET_DIR"
```
</step>

<step name="update_feature_yaml">
Update feature.yaml to remove release reference:

```yaml
# ${TARGET_DIR}/feature.yaml

id: "${FEATURE_SLUG}"
name: ${FEATURE_SLUG}
# ... existing fields ...

# Clear release context
release: null
depends_on: []  # Clear release-scoped dependencies
# Note: requirements[] is preserved as historical references after detach
```

Updates:
- `id` field to the slug (no numeric prefix)
- `release` field to null
- Clear `depends_on` (release-scoped dependencies no longer valid)
- Keep all other fields intact
</step>

<step name="update_release_yaml">
Remove feature from release.yaml features list:

```yaml
# ${RELEASE_DIR}/release.yaml

features:
  total: ${TOTAL - 1}
  completed: ${COMPLETED_ADJUSTED}  # Decrement if feature was completed

  list:
    # Remove entry for ${FEATURE_FULL_ID}
```
</step>

<step name="update_state">
# Acquire state lock
Update state.yaml:

```yaml
# Update releases array - decrement feature count
releases:
  - id: "${RELEASE_ID}"
    progress:
      features_total: ${TOTAL - 1}
      features_completed: ${COMPLETED_ADJUSTED}
      percentage: ${NEW_PERCENTAGE}

# Update standalone_features - add to list
standalone_features:
  total: ${TOTAL + 1}
  list:
    # Add entry
    - id: "${FEATURE_SLUG}"
      status: ${FEATURE_STATUS}

# If this was the current feature, update focus
${IF_CURRENT_FEATURE}
focus:
  feature: "${FEATURE_SLUG}"
  feature_release: null              # Now standalone

feature:
  id: "${FEATURE_SLUG}"
  release: null                      # Now standalone
  # ... keep other fields ...
${END_IF}

session:
  last_activity: ${TIMESTAMP}
  last_action: "Detached feature ${FEATURE_FULL_ID} from release ${RELEASE_ID}"
  last_error: null                    # Cleared on success

  resume:
    context: |
      Detached feature ${FEATURE_FULL_ID} from release ${RELEASE_ID}.
      Now standalone as: ${FEATURE_SLUG}
      Location: ${TARGET_DIR}

updated_at: ${TIMESTAMP}
updated_by: feature-detach
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
Commit the detach operation:

```bash
git add .planning/

git commit -m "chore: detach feature ${FEATURE_FULL_ID} from release ${RELEASE_ID}

- Moved: .planning/releases/${RELEASE_ID}/features/${FEATURE_FULL_ID} -> .planning/features/${FEATURE_SLUG}
- Now standalone feature: ${FEATURE_SLUG}
- Updated release.yaml and state.yaml
"
```
</step>

<step name="report_success">
Report successful detach:

```
═══════════════════════════════════════════════════════════════
FEATURE DETACHED
═══════════════════════════════════════════════════════════════

Feature:     ${FEATURE_FULL_ID} -> ${FEATURE_SLUG}
From:        Release ${RELEASE_ID}
Status:      ${FEATURE_STATUS}

Old location: ${SOURCE_DIR}
New location: ${TARGET_DIR}

───────────────────────────────────────────────────────────────
RELEASE UPDATE

${RELEASE_ID}: ${NEW_COMPLETED}/${NEW_TOTAL} features
${PROGRESS_BAR}

───────────────────────────────────────────────────────────────
STANDALONE FEATURES

  ${FEATURE_SLUG} (${FEATURE_STATUS})
  ${OTHER_STANDALONE_FEATURES}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature start ${FEATURE_SLUG}  — Continue working on feature
  /feature attach ${FEATURE_SLUG} <release>  — Attach to different release
  /feature list --standalone  — See all standalone features
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

**Feature not found in release:**
```
Feature ${FEATURE_ID} not found in release ${RELEASE_ID}

Features in ${RELEASE_ID}:
  ${LIST_OF_FEATURES}

Usage: /feature detach <feature-id> <release-id>
```

**Release not found:**
```
Release not found: ${RELEASE_ID}

Available releases:
  ${LIST_OF_RELEASES}

Usage: /feature detach <feature-id> <release-id>
```

**Standalone slug conflict:**
```
A standalone feature with slug '${FEATURE_SLUG}' already exists.

Location: .planning/features/${FEATURE_SLUG}

Options:
  1. Rename or remove the existing standalone feature
  # TODO: --as flag not yet implemented
  2. Use a different slug once --as flag is implemented
```

**Feature not found in any release:**
```
Feature ${FEATURE_ID} not found in any release.

To find features:
  /feature list --release <id>  — List features in specific release
  /feature list  — List all features

Is this already a standalone feature?
  /feature list --standalone  — Check standalone features
```

</error_handling>

<invariants>
- Feature moves from .planning/releases/<id>/features/ to .planning/features/
- Feature ID converted from "02-auth" to "auth" (slug only)
- feature.yaml updated: release set to null, id to slug
- release.yaml updated: feature removed from list, counts adjusted
- state.yaml updated: standalone_features incremented, release progress updated
- If feature was current, focus is updated
- Dependencies are cleared (release-scoped deps no longer valid)
- Git commit tracks the operation
</invariants>

<notes>
- Detach is required before attaching to a different release
- Feature status is preserved during detach
- Feature work history (research, plan, summary) is preserved
- Release-scoped dependencies are cleared (may need to re-establish)
- Completed features can be detached (useful for reorganization)
</notes>
