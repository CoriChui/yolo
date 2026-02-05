# /debug Workflow

# Note: This workflow defines the "interactive path" for debugging. The debug.yaml pipeline defines the "automated fast path" using agents. The workflow is used for human-guided investigation; the pipeline for fully automated debug flows.
# Note: /debug:resume in index.yaml maps to the "continue" subcommand flow in this workflow

## Purpose

Systematic debugging using the scientific method with persistent state across context resets.

**Key features:**
- Persistent debug file survives `/clear`
- Eliminated hypotheses prevent re-investigation
- Multiple sessions can run in parallel
- Checkpoint system for user interaction

## File Structure

```
.planning/
└── debug/
    ├── DEBUG.yaml                 # Central tracking (active + resolved)
    ├── auth-token-expired/
    │   └── session.yaml           # Debug session file
    ├── api-timeout/
    │   └── session.yaml
    └── resolved/                # Completed sessions
        └── login-crash/
            └── session.yaml
```

## DEBUG.yaml Format

```markdown
# Debug Sessions

## Active

| ID | Issue | Status | Hypothesis | Started |
|----|-------|--------|------------|---------|
| auth-token-expired | Token expires too fast | investigating | Redis TTL config | 2026-02-03 |
| api-timeout | API calls timeout | gathering | — | 2026-02-03 |

## Resolved

| ID | Issue | Root Cause | Resolved |
|----|-------|------------|----------|
| login-crash | App crashes on login | Null user object | 2026-02-02 |

## Statistics

- Total resolved: 1
- Average resolution time: 2h
- This week: 1
```

---

## Commands

### /debug [issue]

Start new debug session or resume existing.

### /debug list

Show active and recent sessions.

### /debug continue [id]

Continue investigating a session.

### /debug resolve [id]

Mark session as resolved.

### /debug abandon [id]

Abandon a session (move to resolved with "abandoned" status).

---

## Session File Format (session.yaml)

# Session format: see .claude/yolo/templates/debug-session.yaml

```yaml
# .planning/debug/{slug}/session.yaml
id: "{slug}"
status: gathering  # gathering | investigating | fixing | verifying | resolved
started: "2026-02-03"
updated: "2026-02-03"

trigger: "[Verbatim user description of the issue]"

current_focus:
  hypothesis: "[Current theory being tested]"
  test: "[How testing it]"
  expecting: "[What result means if true/false]"
  next: "[Immediate next action]"

symptoms:
  expected: "[What should happen]"
  actual: "[What actually happens]"
  errors: "[Error messages if any]"
  reproduction: "[How to trigger]"
  timeline: "[When it started / always broken]"

eliminated:  # Hypotheses that were disproved (prevents re-investigating)
  - hypothesis: "Cache issue"
    evidence_against: "Cache disabled, same behavior"
    when: "2026-02-03"
  - hypothesis: "Network timeout"
    evidence_against: "Local requests also fail"
    when: "2026-02-03"

evidence:  # Facts discovered during investigation
  - checked: "Redis logs"
    found: "TTL set to 60s"
    implication: "Token expires in 1 min"
    when: "2026-02-03"
  - checked: "Config file"
    found: "No TTL override"
    implication: "Using default"
    when: "2026-02-03"

resolution:
  root_cause: null   # Empty until found
  fix: null          # Empty until applied
  verification: null # Empty until verified
  files_changed: []
```

---

## Flow: /debug [issue]

### Step 1: Check Active Sessions

```bash
# List active sessions
ls .planning/debug/*/session.yaml 2>/dev/null | head -5
```

If sessions exist AND no issue provided:
- Show active sessions
- User picks one to continue OR describes new issue

### Step 2: Initialize (New Session)

```bash
# Create directories
mkdir -p .planning/debug

# Generate slug from issue
slug=$(echo "$ISSUE" | tr '[:upper:]' '[:lower:]' | \
  sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-30)

DEBUG_DIR=".planning/debug/${slug}"
mkdir -p "$DEBUG_DIR"
```

### Step 3: Gather Symptoms

Ask user for each (skip if already provided):

1. **Expected behavior** — What should happen?
2. **Actual behavior** — What happens instead?
3. **Error messages** — Any errors? (paste or describe)
4. **Timeline** — When did this start? Ever worked?
5. **Reproduction** — How do you trigger it?

### Step 4: Create Session File

Create `${DEBUG_DIR}/session.yaml` with:
- Status: `gathering` → `investigating`
- Trigger from user input
- Symptoms filled in
- Current Focus: first hypothesis

### Step 5: Update DEBUG.yaml

# XC-001: Acquire lock before modifying DEBUG.yaml
```bash
LOCK_FILE=".planning/debug/DEBUG.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: DEBUG.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

Add to Active section:

```markdown
| ${slug} | ${issue_short} | investigating | ${first_hypothesis} | ${date} |
```

# XC-002: Compute checksum after DEBUG.yaml write
```bash
_checksum=$(sha256sum .planning/debug/DEBUG.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/debug/DEBUG.yaml
```

# XC-003: Update session fields in state.yaml
```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Started debug session: ${slug}\"" .planning/state.yaml
yq -i ".session.last_error = null" .planning/state.yaml
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```

### Step 6: Begin Investigation

# Spawn research agent for investigation
```bash
spawn_agent_with_profile() # contract: research — investigates hypothesis, reads code, runs diagnostics
```

Scientific method loop:

```
1. Form hypothesis based on symptoms/evidence
2. Design test to prove/disprove
3. Execute test (read code, run commands, check logs)
4. Analyze result:
   - If disproved → add to Eliminated, form new hypothesis
   - If evidence found → add to Evidence
   - If root cause confirmed → proceed to fix
```

### Step 7: Checkpoints

When user input is needed:

```
───────────────────────────────
CHECKPOINT: Need Information

Question: Can you confirm if this happens in production too?

Context: Local testing shows the issue, but I need to verify
it's not environment-specific before proceeding.

[Respond to continue]
───────────────────────────────
```

After user responds:
1. Update session.yaml with response
2. Continue investigation

### Step 8: Root Cause Found

When root cause is confirmed:

```
───────────────────────────────
ROOT CAUSE FOUND

Issue: {slug}

Root Cause: {specific cause with evidence}

Evidence:
- {key finding 1}
- {key finding 2}

Files Involved:
- {file1}: {what's wrong}

Options:
  [Fix now]     Apply fix immediately
  [Plan fix]    Create /do task for fix
  [Manual]      I'll fix it myself
───────────────────────────────
```

### Step 9: Apply Fix (if chosen)

# Spawn execute-fix agent for applying the fix
```bash
spawn_agent_with_profile() # contract: execute-fix — applies targeted fix based on root cause analysis
```

1. Update status to `fixing`
2. Make changes
3. Commit atomically:

```bash
git add <files>
git commit -m "fix(<scope>): description

Fixes #debug/${slug}
Root cause: {brief root cause}"
```

4. Update Resolution section

### Step 10: Verify Fix

# Spawn verify agent for fix verification
```bash
spawn_agent_with_profile() # contract: verify — runs reproduction steps, confirms fix
```

1. Update status to `verifying`
2. Test the fix using reproduction steps
3. If verification fails → back to investigating
4. If verification passes → resolve

### Step 11: Resolve

# XC-001: Acquire lock before modifying DEBUG.yaml
```bash
LOCK_FILE=".planning/debug/DEBUG.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: DEBUG.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

1. Update status to `resolved`
2. Move to resolved directory:

```bash
mkdir -p .planning/debug/resolved
mv .planning/debug/${slug} .planning/debug/resolved/
```

3. Update DEBUG.yaml:
   - Remove from Active
   - Add to Resolved

# XC-002: Compute checksum after DEBUG.yaml write
```bash
_checksum=$(sha256sum .planning/debug/DEBUG.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/debug/DEBUG.yaml
```

# XC-003: Update session fields in state.yaml on resolve
```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Resolved debug session: ${slug}\"" .planning/state.yaml
yq -i ".session.last_error = null" .planning/state.yaml
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```

4. Final commit:

```bash
git add .planning/debug/
git commit -m "docs(debug): resolve ${slug}"
```

---

## Flow: /debug continue [id]

### Step 1: Load Session

```bash
DEBUG_DIR=".planning/debug/${id}"
# Read session.yaml
```

### Step 2: Parse State

From session.yaml:
- Current status
- Current Focus (where we left off)
- Eliminated (what NOT to retry)
- Evidence (what we know)

### Step 3: Resume

Continue from `Next` action in Current Focus.

---

## Flow: /debug list

### Output

```
DEBUG SESSIONS (/debug)
───────────────────────

Active (2):
  auth-token-expired    investigating   "Redis TTL config"
  api-timeout           gathering       —

Recent Resolved (3):
  login-crash           2026-02-02      "Null user object"

Commands:
  /debug continue auth-token-expired
  /debug "new issue description"
```

---

## Section Rules

| Section | Rule | Purpose |
|---------|------|---------|
| **Status** | OVERWRITE | Current state |
| **Trigger** | IMMUTABLE | Original issue, never changes |
| **Current Focus** | OVERWRITE | Where Claude is NOW |
| **Symptoms** | IMMUTABLE | Reference point |
| **Eliminated** | APPEND only | Prevents re-investigating |
| **Evidence** | APPEND only | Builds the case |
| **Resolution** | OVERWRITE | Evolves until fixed |

---

## Resume Behavior

When Claude reads session.yaml after `/clear`:

1. Parse Status → know current state
2. Read Current Focus → know exactly what was happening
3. Read Eliminated → know what NOT to retry
4. Read Evidence → know what's been learned
5. Continue from Next action

**The file IS the debugging brain.**

---

## Constraints

- Maximum 3 active debug sessions (recommendation)
- Keep Evidence entries brief (1-2 lines)
- If Evidence grows large (10+ entries) → check Eliminated, may be going in circles
- For complex multi-file issues → consider creating a feature instead

## Success Criteria

- [ ] DEBUG.yaml exists and is up-to-date
- [ ] Each session has directory with session.yaml
- [ ] Eliminated section prevents re-investigation
- [ ] Root cause confirmed before fixing
- [ ] Fix verified before resolving
- [ ] History preserved in DEBUG.yaml Resolved
