<purpose>
Switch the focused release.
The focused release is used as default for commands like /release start, /intake capture, etc.
</purpose>

<triggers>
- `/release focus <id>` - Set focused release by ID
- `/release focus` - Show current focus
</triggers>

<process>

<step name="load_state">
Load current state:

```bash
cat .planning/state.yaml 2>/dev/null
```

Extract:
- `focus.release` - currently focused release
- `releases[]` - all pending/active releases
</step>

<step name="show_current_focus">
If no ID provided, show current focus:

```
═══════════════════════════════════════════════════════════════
CURRENT FOCUS
═══════════════════════════════════════════════════════════════

Focused release: ${FOCUS_RELEASE}
Status: ${STATUS}
Progress: ${PROGRESS}

───────────────────────────────────────────────────────────────
OTHER RELEASES:
  ○ ${OTHER_RELEASE_1} (${STATUS_1})
  ○ ${OTHER_RELEASE_2} (${STATUS_2})

───────────────────────────────────────────────────────────────
COMMANDS:
  /release focus <id>  — Switch to different release
  /release status      — See all releases
═══════════════════════════════════════════════════════════════
```

If no focus set:
```
═══════════════════════════════════════════════════════════════
NO FOCUS SET
═══════════════════════════════════════════════════════════════

No release is currently focused.

Available releases:
  ○ ${RELEASE_1} (${STATUS_1})
  ○ ${RELEASE_2} (${STATUS_2})

───────────────────────────────────────────────────────────────
COMMANDS:
  /release focus <id>  — Set focused release
  /release new <slug>  — Create new release
═══════════════════════════════════════════════════════════════
```
</step>

<step name="validate_release">
If ID provided, validate release exists:

```bash
RELEASE_ID=${ARG}

# Check if release exists in state
RELEASE_EXISTS=$(cat .planning/state.yaml | yq ".releases[] | select(.id == \"${RELEASE_ID}\")")

if [ -z "$RELEASE_EXISTS" ]; then
  # Also check if directory exists (might be completed)
  if [ ! -d ".planning/releases/${RELEASE_ID}" ]; then
    echo "Release not found"
    exit 1
  fi
fi
```

**If release not found:**
```
═══════════════════════════════════════════════════════════════
RELEASE NOT FOUND
═══════════════════════════════════════════════════════════════

Release "${RELEASE_ID}" not found.

Available releases:
  ○ 2026-02-04-mvp (active)
  ○ 2026-02-10-mobile (pending)

───────────────────────────────────────────────────────────────
COMMANDS:
  /release status  — See all releases
  /release new     — Create new release
═══════════════════════════════════════════════════════════════
```
</step>

<step name="update_focus">
# Acquire state lock
# Warning: Focused release is archived — most commands will not work on it
# (Display this warning if the release is completed and has no state entry)

Update .planning/state.yaml:

```yaml
focus:
  release: "${RELEASE_ID}"            # Updated to new release
  feature: null                       # Clear current feature (see below)
  feature_release: null               # Clear feature release (see below)

# releases array unchanged

session:
  last_activity: ${TIMESTAMP}
  last_action: "release-focus ${RELEASE_ID}"
  last_error: null                    # Cleared on success

updated_at: ${TIMESTAMP}
updated_by: release-focus
_checksum: ${COMPUTED_CHECKSUM}       # Recomputed after write
```

# After setting focus.release, check the target release for an in_progress feature.
# If found, set focus.feature to that feature's ID and focus.feature_release to the release ID.
```yaml
# If in_progress feature found in target release:
focus:
  release: "${RELEASE_ID}"
  feature: "${IN_PROGRESS_FEATURE_ID}"
  feature_release: "${RELEASE_ID}"
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
FOCUS CHANGED
═══════════════════════════════════════════════════════════════

Now focused on: ${RELEASE_ID}
Status: ${STATUS}
Progress: ${PROGRESS}

Commands will now operate on this release by default:
  /release start    → starts ${RELEASE_ID}
  /intake capture   → captures to ${RELEASE_ID}
  /feature start    → creates in ${RELEASE_ID}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /release status   — See release details
  /feature start    — Start a feature
  /intake capture   — Capture materials
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<notes>
- Focus determines which release commands operate on by default
- Changing focus clears current feature context
- Can focus on both pending and active releases
- Commands can still override focus with explicit ID parameter
- Creating a new release automatically sets focus to it
</notes>
