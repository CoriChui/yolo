<purpose>
Show status of all releases with focused release indicator.
Can show overview of all releases or details of a specific release.
</purpose>

<triggers>
- `/release status` - Show all releases with focused indicator
- `/release status <id>` - Show specific release details
</triggers>

<process>

<step name="validate_checksum">
Validate `_checksum` in state.yaml:

```bash
STORED_CHECKSUM=$(cat .planning/state.yaml | yq '._checksum')
COMPUTED_CHECKSUM=$(compute_checksum .planning/state.yaml)
if [ "$STORED_CHECKSUM" != "$COMPUTED_CHECKSUM" ]; then
  echo "Warning: state.yaml checksum mismatch (stored: ${STORED_CHECKSUM}, computed: ${COMPUTED_CHECKSUM})"
  echo "State may have been modified externally. Continuing with current state."
fi
```
</step>

<step name="load_state">
Load current state:

```bash
cat .planning/state.yaml 2>/dev/null
```

Extract:
- `focus.release` - currently focused release
- `releases[]` - all pending/active releases
</step>

<step name="no_releases">
If no releases exist:

```
═══════════════════════════════════════════════════════════════
NO RELEASES
═══════════════════════════════════════════════════════════════

No releases in progress.

───────────────────────────────────────────────────────────────
COMMANDS:
  /release new <slug>  — Create new release
  /status              — View project overview
═══════════════════════════════════════════════════════════════
```
</step>

<step name="display_all_releases">
If no specific ID provided, show ALL releases:

```
═══════════════════════════════════════════════════════════════
RELEASES
═══════════════════════════════════════════════════════════════

★ 2026-02-04-mvp (active) [FOCUSED]
  Progress: ████████░░░░░░░░░░░░ 50% (2/4 features)
  Intake: mvp-v1.1 (open)
  Started: 2026-02-04

○ 2026-02-10-mobile (pending)
  Progress: not started
  Intake: mobile-v1 (open)
  Created: 2026-02-10

○ 2026-02-15-billing (active)
  Progress: ██░░░░░░░░░░░░░░░░░░ 10% (1/10 features)
  Intake: billing-v1 (open)
  Started: 2026-02-15

───────────────────────────────────────────────────────────────
COMMANDS:
  /release focus <id>   — Switch focused release
  /release status <id>  — See release details
  /release new <slug>   — Create new release
  /release start [id]   — Start a pending release
  /release end [id]     — Complete a release
═══════════════════════════════════════════════════════════════
```

**Legend:**
- `★` = Focused release (commands operate on this by default)
- `○` = Other releases
- `[FOCUSED]` = Explicit focused indicator
</step>

<step name="load_specific_release">
If specific release ID provided:

```bash
RELEASE_ID=${ARG}
RELEASE_DIR=".planning/releases/${RELEASE_ID}"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "Release not found: ${RELEASE_ID}"
  exit 1
fi

cat "${RELEASE_DIR}/release.yaml"
```
</step>

<step name="display_pending_release">
If specific release is PENDING:

```
═══════════════════════════════════════════════════════════════
RELEASE: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Status: PENDING (not started)
Created: ${CREATED_DATE}
${FOCUSED_INDICATOR}

Intake: ${INTAKE_VERSION}
  Location: .planning/releases/${RELEASE_ID}/intake/${INTAKE_VERSION}/
  Sources: ${SOURCE_LIST_OR_NONE}
  Files:   ${FILE_COUNT}

The release is ready to start after intake capture.

───────────────────────────────────────────────────────────────
COMMANDS:
  /intake capture [src]         — Capture more materials
  /release start ${RELEASE_ID}  — Start release (runs research)
  /release focus ${RELEASE_ID}  — Set as focused release
═══════════════════════════════════════════════════════════════
```
</step>

<step name="display_active_release">
If specific release is ACTIVE:

```
═══════════════════════════════════════════════════════════════
RELEASE: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Status: ACTIVE
Started: ${STARTED_DATE}
${FOCUSED_INDICATOR}

Goal:
  ${RELEASE_GOAL}

Success Criteria:
  - ${CRITERION_1}
  - ${CRITERION_2}

Features: ${COMPLETED}/${TOTAL}
  [x] 01: foundation (completed)
  [>] 02: auth (in_progress)
  [ ] 03: billing (pending)
  [ ] 04: repairs (pending)

Intake: ${INTAKE_VERSION}
  Location: .planning/releases/${RELEASE_ID}/intake/${INTAKE_VERSION}/
  Sources: figma, notion
  Files:   12

───────────────────────────────────────────────────────────────
COMMANDS:
  /feature start <id>         — Start feature
  /feature status             — Current feature details
  /intake capture [src]       — Add more intake
  /release end ${RELEASE_ID}  — Complete release
  /release focus ${RELEASE_ID}— Set as focused release
═══════════════════════════════════════════════════════════════
```
</step>

<step name="display_paused_release">
If specific release is PAUSED:

```
═══════════════════════════════════════════════════════════════
RELEASE: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Status: PAUSED
Started: ${STARTED_DATE}
Paused:  ${PAUSED_DATE}
${FOCUSED_INDICATOR}

Goal:
  ${RELEASE_GOAL}

Features: ${COMPLETED}/${TOTAL}
  [x] 01: foundation (completed)
  [|] 02: auth (paused)
  [ ] 03: billing (pending)

───────────────────────────────────────────────────────────────
COMMANDS:
  /release resume ${RELEASE_ID}  — Resume release
  /release end ${RELEASE_ID}     — Complete release
═══════════════════════════════════════════════════════════════
```
</step>

<step name="display_failed_release">
If specific release is FAILED:

```
═══════════════════════════════════════════════════════════════
RELEASE: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Status: FAILED
Started: ${STARTED_DATE}
Failed:  ${FAILED_DATE}
${FOCUSED_INDICATOR}

Goal:
  ${RELEASE_GOAL}

Features: ${COMPLETED}/${TOTAL}
  ${FEATURE_LIST}

Failure reason:
  ${FAILURE_REASON}

───────────────────────────────────────────────────────────────
COMMANDS:
  /release new <slug>  — Create new release
  /release status      — View all releases
═══════════════════════════════════════════════════════════════
```
</step>

<step name="display_cancelled_release">
If specific release is CANCELLED:

```
═══════════════════════════════════════════════════════════════
RELEASE: ${RELEASE_ID}
═══════════════════════════════════════════════════════════════

Status: CANCELLED
Created: ${CREATED_DATE}
Cancelled: ${CANCELLED_DATE}
${FOCUSED_INDICATOR}

Goal:
  ${RELEASE_GOAL}

───────────────────────────────────────────────────────────────
COMMANDS:
  /release new <slug>  — Create new release
  /release status      — View all releases
═══════════════════════════════════════════════════════════════
```
</step>

<step name="display_completed_release">
If specific release is COMPLETED (viewing archived):

```
═══════════════════════════════════════════════════════════════
RELEASE: ${RELEASE_ID} (archived)
═══════════════════════════════════════════════════════════════

Status: COMPLETED
Started: ${STARTED_DATE}
Completed: ${COMPLETED_DATE}
Duration: ${DURATION}

Goal:
  ${RELEASE_GOAL}

Features: ${COMPLETED}/${TOTAL}
  [x] 01: foundation
  [x] 02: auth
  [x] 03: billing

Intake: ${INTAKE_VERSION} (locked)

Output:
  .planning/releases/${RELEASE_ID}/output/schema.md
  .planning/releases/${RELEASE_ID}/output/api.md
  .planning/releases/${RELEASE_ID}/output/architecture.md

═══════════════════════════════════════════════════════════════
```
</step>

</process>

<notes>
- Shows ALL releases when no ID specified
- Focused release marked with ★ and [FOCUSED]
- Progress bar shows feature completion
- Can view specific release details with ID parameter
- Completed releases are archived but still viewable
</notes>
