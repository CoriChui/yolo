<purpose>
Resume an active debug session by loading its persistent state and continuing investigation.
Restores the full debugging context including evidence, eliminated hypotheses, and current focus.
Enforces session mutation rules to prevent re-investigation of eliminated hypotheses.
</purpose>

<triggers>
- `/yolo:debug continue <session-id>` - Resume a specific debug session
- `/yolo:debug continue` - Resume the most recent active debug session
</triggers>

<process>

<step name="load_state">
Read current project state:

```bash
cat .planning/state.yaml
```

Extract:
- `session.last_activity` - When last action occurred
- `session.last_action` - What was last done
- `session.last_error` - Any previous error
</step>

<step name="find_session">
Determine which debug session to resume:

**If session-id provided:**

```bash
SESSION_ID=${ARG}
DEBUG_DIR=".planning/debug/${SESSION_ID}"

if [ ! -d "$DEBUG_DIR" ] || [ ! -f "$DEBUG_DIR/session.yaml" ]; then
  echo "Debug session not found: ${SESSION_ID}"
  echo ""
  echo "Use /debug list to see available sessions."
  exit 1
fi
```

**If no session-id provided, find most recent active session:**

```bash
# Find all active sessions (status != resolved && status != abandoned)
LATEST_SESSION=""
LATEST_UPDATED=""

for session_file in .planning/debug/*/session.yaml; do
  [ -f "$session_file" ] || continue

  # Skip resolved directory
  case "$session_file" in
    */resolved/*) continue ;;
  esac

  STATUS=$(yq '.status' "$session_file")
  if [ "$STATUS" != "resolved" ] && [ "$STATUS" != "abandoned" ]; then
    UPDATED=$(yq '.updated' "$session_file")
    if [ -z "$LATEST_UPDATED" ] || [ "$UPDATED" \> "$LATEST_UPDATED" ]; then
      LATEST_UPDATED="$UPDATED"
      LATEST_SESSION="$session_file"
    fi
  fi
done

if [ -z "$LATEST_SESSION" ]; then
  echo "No active debug sessions found."
  echo ""
  echo "Start a new session with /debug <issue description>"
  echo "Or check resolved sessions with /debug list"
  exit 1
fi

DEBUG_DIR=$(dirname "$LATEST_SESSION")
SESSION_ID=$(basename "$DEBUG_DIR")
```
</step>

<step name="load_session">
Read the debug session file:

```bash
SESSION_YAML=$(cat "${DEBUG_DIR}/session.yaml")

SESSION_STATUS=$(echo "$SESSION_YAML" | yq '.status')
SESSION_STARTED=$(echo "$SESSION_YAML" | yq '.started')
SESSION_UPDATED=$(echo "$SESSION_YAML" | yq '.updated')
```

Validate session is resumable:

```bash
if [ "$SESSION_STATUS" == "resolved" ]; then
  echo "Debug session ${SESSION_ID} is already resolved."
  echo ""
  echo "Root cause: $(echo "$SESSION_YAML" | yq '.resolution.root_cause')"
  echo "Fix: $(echo "$SESSION_YAML" | yq '.resolution.fix')"
  echo ""
  echo "Start a new session with /debug <issue>"
  exit 1
fi

if [ "$SESSION_STATUS" == "abandoned" ]; then
  echo "Debug session ${SESSION_ID} was abandoned."
  echo ""
  echo "Start a new session with /debug <issue>"
  exit 1
fi
```
</step>

<step name="restore_context">
Parse session.yaml to rebuild the full debugging state:

```bash
# IMMUTABLE — original issue description (never changes)
TRIGGER=$(echo "$SESSION_YAML" | yq '.trigger')

# IMMUTABLE — observed behavior (never changes)
SYMPTOMS_EXPECTED=$(echo "$SESSION_YAML" | yq '.symptoms.expected')
SYMPTOMS_ACTUAL=$(echo "$SESSION_YAML" | yq '.symptoms.actual')
SYMPTOMS_ERRORS=$(echo "$SESSION_YAML" | yq '.symptoms.errors')
SYMPTOMS_REPRODUCTION=$(echo "$SESSION_YAML" | yq '.symptoms.reproduction')
SYMPTOMS_TIMELINE=$(echo "$SESSION_YAML" | yq '.symptoms.timeline')

# APPEND-ONLY — accumulated facts discovered during investigation
EVIDENCE=$(echo "$SESSION_YAML" | yq '.evidence')
EVIDENCE_COUNT=$(echo "$SESSION_YAML" | yq '.evidence | length')

# APPEND-ONLY — rejected hypotheses (prevents re-investigation)
ELIMINATED=$(echo "$SESSION_YAML" | yq '.eliminated')
ELIMINATED_COUNT=$(echo "$SESSION_YAML" | yq '.eliminated | length')

# OVERWRITE — current investigation focus
CURRENT_HYPOTHESIS=$(echo "$SESSION_YAML" | yq '.current_focus.hypothesis')
CURRENT_TEST=$(echo "$SESSION_YAML" | yq '.current_focus.test')
CURRENT_EXPECTING=$(echo "$SESSION_YAML" | yq '.current_focus.expecting')
CURRENT_NEXT=$(echo "$SESSION_YAML" | yq '.current_focus.next')

# OVERWRITE — session status
# gathering | investigating | fixing | verifying
STATUS=${SESSION_STATUS}

# OVERWRITE — resolution (empty until root cause found)
RESOLUTION_ROOT_CAUSE=$(echo "$SESSION_YAML" | yq '.resolution.root_cause')
RESOLUTION_FIX=$(echo "$SESSION_YAML" | yq '.resolution.fix')
RESOLUTION_VERIFICATION=$(echo "$SESSION_YAML" | yq '.resolution.verification')
```
</step>

<step name="acquire_state_lock">
Acquire state lock (set lock.held_by, lock.acquired_at, lock.expires_at in state.yaml):

```yaml
lock:
  held_by: debug-resume
  acquired_at: ${TIMESTAMP}
  expires_at: ${TIMESTAMP + 60s}
```
</step>

<step name="update_state">
Update state.yaml to reflect debug session resume:

```yaml
session:
  last_activity: ${TIMESTAMP}
  last_action: "debug:resume ${SESSION_ID}"
  last_error: null                     # XC-003: Clear last_error on success

  resume:
    context: |
      Resuming debug session: ${SESSION_ID}.
      Status: ${STATUS}.
      Trigger: ${TRIGGER}.
      Evidence items: ${EVIDENCE_COUNT}.
      Eliminated hypotheses: ${ELIMINATED_COUNT}.
      Current focus: ${CURRENT_HYPOTHESIS}.
      Next action: ${CURRENT_NEXT}.

updated_at: ${TIMESTAMP}
updated_by: debug-resume
```

Compute and set `_checksum` on state.yaml (XC-002):

```bash
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i "._checksum = \"${_checksum}\"" .planning/state.yaml
```
</step>

<step name="release_state_lock">
Release state lock (clear lock fields in state.yaml):

```yaml
lock:
  held_by: null
  acquired_at: null
  expires_at: null
```
</step>

<step name="display_status">
Display the restored debug session context:

```
═══════════════════════════════════════════════════════════════
DEBUG SESSION RESUMED: ${SESSION_ID}
═══════════════════════════════════════════════════════════════

Trigger:  ${TRIGGER}
Status:   ${STATUS}
Started:  ${SESSION_STARTED}
Updated:  ${SESSION_UPDATED}

───────────────────────────────────────────────────────────────
SYMPTOMS (immutable)
───────────────────────────────────────────────────────────────
  Expected:     ${SYMPTOMS_EXPECTED}
  Actual:       ${SYMPTOMS_ACTUAL}
  Errors:       ${SYMPTOMS_ERRORS}
  Reproduction: ${SYMPTOMS_REPRODUCTION}
  Timeline:     ${SYMPTOMS_TIMELINE}

───────────────────────────────────────────────────────────────
EVIDENCE COLLECTED (${EVIDENCE_COUNT} items, append-only)
───────────────────────────────────────────────────────────────
${FOR entry IN EVIDENCE}
  - Checked: ${entry.checked}
    Found:   ${entry.found}
    Implies: ${entry.implication}
    When:    ${entry.when}
${END_FOR}

───────────────────────────────────────────────────────────────
ELIMINATED HYPOTHESES (${ELIMINATED_COUNT}, append-only)
───────────────────────────────────────────────────────────────
${FOR hyp IN ELIMINATED}
  - Hypothesis: ${hyp.hypothesis}
    Disproved:  ${hyp.evidence_against}
    When:       ${hyp.when}
${END_FOR}

───────────────────────────────────────────────────────────────
CURRENT FOCUS (overwrite)
───────────────────────────────────────────────────────────────
  Hypothesis: ${CURRENT_HYPOTHESIS}
  Test:       ${CURRENT_TEST}
  Expecting:  ${CURRENT_EXPECTING}
  Next:       ${CURRENT_NEXT}

═══════════════════════════════════════════════════════════════
```
</step>

<step name="continue_loop">
Continue the investigation based on status and current_focus.next:

**If status is `gathering`:**
```bash
# Continue gathering evidence — read more files, reproduce issue
echo "Continuing evidence gathering..."
echo "Next action: ${CURRENT_NEXT}"

# Spawn research agent for continued investigation
spawn_agent_with_profile() # contract: research — gathers evidence, reads code, runs diagnostics
```

**If status is `investigating`:**
```bash
# Test current hypothesis
echo "Continuing investigation..."
echo "Testing hypothesis: ${CURRENT_HYPOTHESIS}"
echo "Test: ${CURRENT_TEST}"
echo "Expected result: ${CURRENT_EXPECTING}"
echo "Next action: ${CURRENT_NEXT}"

# Scientific method loop:
# 1. Execute the test defined in current_focus.test
# 2. Analyze result:
#    - If disproved → append to eliminated, form new hypothesis
#    - If evidence found → append to evidence
#    - If root cause confirmed → status = fixing
```

**If status is `fixing`:**
```bash
# Apply the identified fix
echo "Continuing fix application..."
echo "Root cause: ${RESOLUTION_ROOT_CAUSE}"
echo "Next action: ${CURRENT_NEXT}"

# Spawn execute-fix agent for applying the fix
spawn_agent_with_profile() # contract: execute-fix — applies targeted fix based on root cause
```

**If status is `verifying`:**
```bash
# Verify the fix works
echo "Continuing fix verification..."
echo "Fix applied: ${RESOLUTION_FIX}"
echo "Next action: ${CURRENT_NEXT}"

# Spawn verify agent for fix verification
spawn_agent_with_profile() # contract: verify — runs reproduction steps, confirms fix

# If verification fails → status = investigating (back to investigation)
# If verification passes → proceed to resolve
```

After each loop iteration, update session.yaml:

```bash
# Update session.yaml with new state
yq -i ".updated = \"$(date +%Y-%m-%d)\"" "${DEBUG_DIR}/session.yaml"
yq -i ".status = \"${NEW_STATUS}\"" "${DEBUG_DIR}/session.yaml"
yq -i ".current_focus.hypothesis = \"${NEW_HYPOTHESIS}\"" "${DEBUG_DIR}/session.yaml"
yq -i ".current_focus.test = \"${NEW_TEST}\"" "${DEBUG_DIR}/session.yaml"
yq -i ".current_focus.expecting = \"${NEW_EXPECTING}\"" "${DEBUG_DIR}/session.yaml"
yq -i ".current_focus.next = \"${NEW_NEXT}\"" "${DEBUG_DIR}/session.yaml"

# Append to evidence (APPEND ONLY — never overwrite existing entries)
yq -i ".evidence += [{\"checked\": \"${CHECKED}\", \"found\": \"${FOUND}\", \"implication\": \"${IMPLICATION}\", \"when\": \"$(date +%Y-%m-%d)\"}]" "${DEBUG_DIR}/session.yaml"

# Append to eliminated (APPEND ONLY — never overwrite existing entries)
yq -i ".eliminated += [{\"hypothesis\": \"${DISPROVED_HYP}\", \"evidence_against\": \"${EVIDENCE_AGAINST}\", \"when\": \"$(date +%Y-%m-%d)\"}]" "${DEBUG_DIR}/session.yaml"
```

**Session mutation rules (CRITICAL):**

| Field | Rule | Enforcement |
|-------|------|-------------|
| `trigger` | IMMUTABLE | Never written after session creation |
| `symptoms` | IMMUTABLE | Never written after session creation |
| `eliminated` | APPEND ONLY | Use `yq .eliminated +=` only |
| `evidence` | APPEND ONLY | Use `yq .evidence +=` only |
| `current_focus` | OVERWRITE | Full replacement on each iteration |
| `status` | OVERWRITE | Transitions: gathering -> investigating -> fixing -> verifying -> resolved |
| `resolution` | OVERWRITE | Evolves until fix confirmed |
</step>

</process>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).

**No active sessions:**
```
No active debug sessions found.

All sessions are either resolved or abandoned.

Commands:
  /debug <issue>   — Start a new debug session
  /debug list      — Show all sessions (including resolved)
```

**Session not found:**
```
Debug session not found: ${SESSION_ID}

Available sessions:
${FOR session IN ACTIVE_SESSIONS}
  ${session.id}  ${session.status}  "${session.trigger}"
${END_FOR}

Commands:
  /debug continue <id>  — Resume a specific session
  /debug list            — Show all sessions
```

**Session already resolved:**
```
Debug session ${SESSION_ID} is already resolved.

Root cause: ${RESOLUTION_ROOT_CAUSE}
Fix:        ${RESOLUTION_FIX}
Resolved:   ${RESOLVED_DATE}

Start a new session with /debug <issue description>.
```

</error_handling>

<invariants>
- Never modify trigger or symptoms fields (IMMUTABLE)
- Only append to eliminated and evidence arrays (APPEND ONLY)
- current_focus, status, and resolution are overwritten each iteration
- Eliminated hypotheses prevent re-investigation of disproved theories
- Session file IS the debugging brain — all state persists across context resets
- state.yaml session fields updated on resume, checksum recomputed
</invariants>
