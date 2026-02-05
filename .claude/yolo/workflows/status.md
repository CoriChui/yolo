<purpose>
Display overall project status including all active releases, current feature, and standalone features.
Shows focused release with indicator. Provides quick orientation and suggests next action.
</purpose>

<triggers>
- `/status` - Show full project status
- `/status --full` - Show detailed status
- `/status --releases` - Focus on releases overview
</triggers>

<process>

<step name="load_all_state">
Load complete project state (schema v2):

```bash
# Core state
STATE=$(cat .planning/state.yaml 2>/dev/null)

# Focus info
FOCUSED_RELEASE=$(echo "$STATE" | yq '.focus.release')
CURRENT_FEATURE=$(echo "$STATE" | yq '.focus.feature')
FEATURE_RELEASE=$(echo "$STATE" | yq '.focus.feature_release')

# All active releases
RELEASES=$(echo "$STATE" | yq '.releases[]')

# Release count
RELEASE_COUNT=$(echo "$STATE" | yq '.releases | length')

# Standalone features
STANDALONE_TOTAL=$(echo "$STATE" | yq '.standalone_features.total')
STANDALONE_ACTIVE=$(echo "$STATE" | yq '.standalone_features.active')
STANDALONE_LIST=$(echo "$STATE" | yq '.standalone_features.list[]')

# Current feature details
FEATURE=$(echo "$STATE" | yq '.feature')

# Session info
LAST_ACTIVITY=$(echo "$STATE" | yq '.session.last_activity')
LAST_ACTION=$(echo "$STATE" | yq '.session.last_action')
```
</step>

<step name="load_release_details">
For each release, load additional info:

```bash
for RELEASE_ID in $(echo "$STATE" | yq '.releases[].id'); do
  RELEASE_ENTRY=$(echo "$STATE" | yq ".releases[] | select(.id == \"${RELEASE_ID}\")")
  RELEASE_STATUS=$(echo "$RELEASE_ENTRY" | yq '.status')
  RELEASE_SLUG=$(echo "$RELEASE_ENTRY" | yq '.slug')
  INTAKE_VERSION=$(echo "$RELEASE_ENTRY" | yq '.intake.current')
  INTAKE_LOCKED=$(echo "$RELEASE_ENTRY" | yq '.intake.locked')
  FEATURES_TOTAL=$(echo "$RELEASE_ENTRY" | yq '.progress.features_total')
  FEATURES_COMPLETED=$(echo "$RELEASE_ENTRY" | yq '.progress.features_completed')
  PROGRESS_PCT=$(echo "$RELEASE_ENTRY" | yq '.progress.percentage')
done
```
</step>

<step name="calculate_progress">
Calculate progress bars for each release:

```bash
# Progress bar
FILLED=$((PROGRESS_PCT / 10))
EMPTY=$((10 - FILLED))
PROGRESS_BAR=$(printf '█%.0s' $(seq 1 $FILLED))$(printf '░%.0s' $(seq 1 $EMPTY))
```
</step>

<step name="determine_suggested_action">
Suggest next action based on current state:

**Decision tree:**

| Condition | Suggested Action |
|-----------|------------------|
| focus.feature && feature.status == "planning" | `/feature plan` |
| focus.feature && feature.status == "in_progress" | `/feature execute` or `/task next` |
| focus.feature && feature.status == "verifying" | `/feature verify` |
| focus.feature && feature.status == "completed" | `/feature start ${next}` |
| focused release has all features complete | `/release end` |
| no focus.feature && focused release exists | `/feature start <id>` |
| no releases exist | `/release new <name>` |
</step>

<step name="display_full_status">
Display comprehensive status (default):

```
══════════════════════════════════════════════════════════════════
PROJECT STATUS
══════════════════════════════════════════════════════════════════

RELEASES (${RELEASE_COUNT} active)
──────────────────────────────────────────────────────────────────
  ★ 2026-02-04-mvp (active) [FOCUSED]
    Progress: ████████░░░░░░░░░░░░ 50% (2/4 features)
    Intake: mvp-v1.1 (open)

  ○ 2026-02-10-mobile (pending)
    Progress: not started
    Intake: mobile-v1 (open)

CURRENT FEATURE
──────────────────────────────────────────────────────────────────
  03-billing (in_progress) — Release: 2026-02-04-mvp
  Tasks: ████░░░░░░ 33% (2/6)
  Current: "Implement payment acceptance"
  Started: 2026-02-08 (2 days ago)

STANDALONE FEATURES (${STANDALONE_TOTAL})
──────────────────────────────────────────────────────────────────
  ○ dark-mode (pending)
  ○ export-csv (pending)

LAST ACTIVITY: ${LAST_ACTIVITY}
  "${LAST_ACTION}"

══════════════════════════════════════════════════════════════════
NEXT ACTIONS:
  /task next              — Continue with current task
  /feature status         — See feature details
  /release focus <id>     — Switch to different release
══════════════════════════════════════════════════════════════════
```
</step>

<step name="display_releases_list">
Show releases with status indicators:

```
RELEASES (2 active)
──────────────────────────────────────────────────────────────────
  ★ 2026-02-04-mvp (active) [FOCUSED]
    Progress: ████████░░░░░░░░░░░░ 50% (2/4 features)
    Intake: mvp-v1.1 (open)

  ○ 2026-02-10-mobile (pending)
    Progress: not started
    Intake: mobile-v1 (open)
```

Indicators:
- ★ focused release
- ● active (not focused)
- ○ pending
</step>

<step name="display_feature_detail">
Show current feature with task progress:

```
CURRENT FEATURE
──────────────────────────────────────────────────────────────────
  03-billing (in_progress) — Release: 2026-02-04-mvp
  Tasks: ████░░░░░░ 33% (2/6)
  Current: "Implement payment acceptance"
  Started: 2026-02-08 (2 days ago)
```

If no current feature:
```
CURRENT FEATURE
──────────────────────────────────────────────────────────────────
  (none active)

  Start a feature:
    /feature start 03-billing
    /feature start dark-mode    (standalone)
```
</step>

<step name="display_standalone">
Show standalone features count and list:

```
STANDALONE FEATURES (2)
──────────────────────────────────────────────────────────────────
  ○ dark-mode (pending)
  ○ export-csv (pending)
```

Indicators:
- ✓ completed
- ► in_progress
- ○ pending
</step>

</process>

<special_states>

**No project initialized:**
```
══════════════════════════════════════════════════════════════════
NO PROJECT FOUND
══════════════════════════════════════════════════════════════════

No .planning/state.yaml found.

To start:
  1. /init                — Initialize YOLO workflow
  2. /release new <name>  — Create first release

Codebase is the source of truth.
Intake is optional auxiliary context (lives inside release).
══════════════════════════════════════════════════════════════════
```

**No releases:**
```
══════════════════════════════════════════════════════════════════
PROJECT STATUS
══════════════════════════════════════════════════════════════════

RELEASES (0)
──────────────────────────────────────────────────────────────────
  (none)

STANDALONE FEATURES (${STANDALONE_TOTAL})
──────────────────────────────────────────────────────────────────
  ○ dark-mode (pending)
  ○ export-csv (pending)

══════════════════════════════════════════════════════════════════
NEXT ACTIONS:
  /release new <name>     — Create a release
  /feature start <slug>   — Start standalone feature
══════════════════════════════════════════════════════════════════
```

**Focused release complete:**
```
══════════════════════════════════════════════════════════════════
RELEASE COMPLETE: 2026-02-04-mvp
══════════════════════════════════════════════════════════════════

All 4 features finished!

▶ Next: /release end
        (generates output specs, archives release)

Other releases:
  ○ 2026-02-10-mobile (pending) — /release focus 2026-02-10-mobile
══════════════════════════════════════════════════════════════════
```

</special_states>

<notes>
- Status provides orientation after context resets
- Shows ALL active releases with focused indicator (★)
- Shows standalone features count separately
- Suggested action guides workflow continuation
- Intake is release-scoped (shown per release)
- Codebase is always the source of truth
# Note: 05-commands.md routing table should be updated to reference this workflow instead of (inline)
</notes>
