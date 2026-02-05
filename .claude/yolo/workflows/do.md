# /do Workflow

# Template: .claude/yolo/templates/do.yaml
# Note: Canonical directory is .planning/do/ — index.yaml references .planning/quick/ and should be updated

## Purpose

Execute small ad-hoc tasks with YOLO guarantees:
- Atomic commits
- Full tracking in DO.yaml
- Multiple tasks in parallel
- Execution history

## File Structure

```
.planning/
└── do/
    ├── DO.yaml                  # Central file (active + history)
    ├── 001-fix-login/
    │   ├── plan.md              # Task plan
    │   └── summary.md           # Result (after completion)
    └── 002-add-validation/
        ├── plan.md
        └── summary.md
```

## DO.yaml Format

```yaml
active:
  - id: "003"
    description: "Add rate limiting"
    started: "2026-02-03"
    status: in_progress
    progress: { completed: 2, total: 3 }
    directory: "003-add-rate-limiting"
  - id: "002"
    description: "Fix validation"
    started: "2026-02-02"
    status: blocked
    progress: { completed: 1, total: 2 }
    directory: "002-fix-validation"

completed:
  - id: "001"
    description: "Setup logging"
    completed: "2026-02-01"
    commits: 2
    duration: "1h"
    directory: "001-setup-logging"

cancelled: []

stats:
  total_completed: 1
  total_cancelled: 0
  average_duration: "1h"
  this_week: 1
```

---

## Commands

### /do [description]

Start a new task.

### /do list

Show active and recent tasks.

### /do status [id]

Detailed status of a specific task.

### /do continue [id]

Continue working on a task.

### /do complete [id]

Mark task as complete.

### /do cancel [id]

Cancel a task.

---

## Flow: /do [description]

### Step 1: Initialize

```bash
# Create directory if not exists
mkdir -p .planning/do

# Create DO.yaml if not exists
if [ ! -f .planning/do/DO.yaml ]; then
  # Create from template
fi
```

### Step 2: Get description

If not provided — prompt interactively:

```
What needs to be done?
> _
```

### Step 3: Generate ID and slug

```bash
# Find next number
last=$(ls -1d .planning/do/[0-9][0-9][0-9]-* 2>/dev/null | \
  sort -r | head -1 | xargs -I{} basename {} | grep -oE '^[0-9]+')
next_num=$(printf "%03d" $((10#${last:-0} + 1)))

# Slug from description
slug=$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | \
  sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-30)

DO_ID="${next_num}"
DO_DIR=".planning/do/${next_num}-${slug}"
```

### Step 4: Explore codebase

Before planning:

1. Determine scope from description
2. Find relevant files (Glob, Grep)
3. Read key files
4. Understand current architecture in this area

### Step 5: Create plan

Create `${DO_DIR}/plan.md`:

```markdown
# Do ${DO_ID}: ${DESCRIPTION}

**Started:** ${date}
**Status:** in_progress

## Context

[What was discovered during codebase exploration]

## Tasks

- [ ] Task 1: Description
  - Files: `path/to/file.ts`

- [ ] Task 2: Description
  - Files: `path/to/another.ts`

## Notes

[Additional notes]
```

### Step 6: Update DO.yaml

# XC-001: Acquire lock before modifying DO.yaml
```bash
# Acquire lock
LOCK_FILE=".planning/do/DO.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: DO.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

Add to `active` array with initial status `pending` (transitions to `in_progress` when exploration begins):

```yaml
- id: "${DO_ID}"
  description: "${DESCRIPTION}"
  started: "${date}"
  status: pending
  progress: { completed: 0, total: ${task_count} }
  directory: "${next_num}-${slug}"
```

# XC-002: Compute checksum after DO.yaml write
```bash
_checksum=$(sha256sum .planning/do/DO.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/do/DO.yaml
```

# XC-003: Update session fields in state.yaml on task creation
```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Created /do #${DO_ID}: ${DESCRIPTION}\"" .planning/state.yaml
yq -i ".session.last_error = null" .planning/state.yaml

# Compute state.yaml checksum
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```

### Step 7: Output

```
───────────────────────────────
YOLO > /do STARTED

#${DO_ID}: ${DESCRIPTION}

Tasks: ${task_count}
Directory: ${DO_DIR}

Next: Execute tasks or /do continue ${DO_ID}
───────────────────────────────
```

---

## Flow: /do continue [id]

### Step 1: Find task

```bash
# If id not provided — show active list
# If provided — find directory
DO_DIR=$(ls -d .planning/do/${id}-* 2>/dev/null | head -1)
```

### Step 2: Load context

Read `${DO_DIR}/plan.md`:
- Current status
- Completed tasks
- Next task

### Step 3: Execute next task

# Spawn execute-standard agent for task execution
```bash
spawn_agent_with_profile() # contract: execute
```

1. Explore task files
2. Make changes
3. Verify (lint, types)
4. Commit atomically:

```bash
git add <files>
git commit -m "fix(<scope>): description

Part of /do #${DO_ID}: ${DESCRIPTION}"
```

### Step 4: Update plan.md

- Mark task as completed `[x]`
- Add commit hash

### Step 5: Update DO.yaml

# XC-001: Acquire lock before modifying DO.yaml
```bash
LOCK_FILE=".planning/do/DO.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: DO.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

Update progress in `active` array.

# XC-002: Compute checksum after DO.yaml write
```bash
_checksum=$(sha256sum .planning/do/DO.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/do/DO.yaml
```

# XC-003: Update session fields in state.yaml on task completion
```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Completed task in /do #${DO_ID}\"" .planning/state.yaml
yq -i ".session.last_error = null" .planning/state.yaml
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```

### Step 6: Check completion

If all tasks completed — suggest `/do complete ${DO_ID}`.

---

## Flow: /do complete [id]

### Step 1: Validation

- Check that all tasks in plan.md are marked `[x]`
- If not — show incomplete tasks

### Step 1.5: Acquire lock

# XC-001: Acquire lock before modifying DO.yaml
```bash
LOCK_FILE=".planning/do/DO.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: DO.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

### Step 2: Create summary.md

```markdown
# Do ${DO_ID}: ${DESCRIPTION}

**Completed:** ${date}
**Duration:** ${duration}

## Result

[Brief description of what was done]

## Commits

| Hash | Message |
|------|---------|
| abc123 | fix(auth): description |
| def456 | fix(auth): description |

## Files Changed

- `src/auth/login.ts`
- `src/auth/validation.ts`

## Notes

[Notes if any]
```

### Step 3: Update DO.yaml

1. Remove from `active` array
2. Add to `completed` array
3. Update `stats`

# XC-002: Compute checksum after DO.yaml write
```bash
_checksum=$(sha256sum .planning/do/DO.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/do/DO.yaml
```

# XC-003: Update session fields in state.yaml on completion
```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Completed /do #${DO_ID}: ${DESCRIPTION}\"" .planning/state.yaml
yq -i ".session.last_error = null" .planning/state.yaml
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/state.yaml
```

### Step 4: Final commit

```bash
git add ${DO_DIR}/
git add .planning/do/DO.yaml
git commit -m "docs(do-${DO_ID}): complete - ${DESCRIPTION}"
```

### Step 5: Output

```
───────────────────────────────
YOLO > /do COMPLETE

#${DO_ID}: ${DESCRIPTION}

Duration: ${duration}
Commits: ${commit_count}
Files: ${files_count}

───────────────────────────────
```

---

## Flow: /do list

### Output

```
AD-HOC TASKS (/do)
──────────────────

Active (2):
  #003  Add rate limiting       in_progress  2/3 tasks
  #002  Fix validation          blocked      1/2 tasks

Recent (3):
  #001  Setup logging           completed    2026-02-01

Commands:
  /do continue 003    Continue task
  /do complete 003    Mark complete
  /do "new task"      Start new
```

---

## Flow: /do cancel [id]

### Step 0: Status validation

# WA-030: Validate task status before cancellation
```bash
TASK_STATUS=$(yq ".active[] | select(.id == \"${DO_ID}\") | .status" .planning/do/DO.yaml)
if [ "$TASK_STATUS" != "pending" ] && [ "$TASK_STATUS" != "in_progress" ]; then
  echo "ERROR: Cannot cancel task #${DO_ID} — status is '${TASK_STATUS}'. Only 'pending' or 'in_progress' tasks can be cancelled."
  exit 1
fi
```

### Step 1: Confirmation

```
Cancel /do #${DO_ID}: ${DESCRIPTION}?

This will:
- Mark task as cancelled
- Keep directory for reference
- NOT revert any commits

[Yes] [No]
```

### Step 1.5: Acquire lock

# XC-001: Acquire lock before modifying DO.yaml
```bash
LOCK_FILE=".planning/do/DO.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: DO.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

### Step 2: Update DO.yaml

1. Remove from `active` array
2. Add to `cancelled` array

# XC-002: Compute checksum after DO.yaml write
```bash
_checksum=$(sha256sum .planning/do/DO.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/do/DO.yaml
```

# XC-003: Update session fields in state.yaml on cancellation
```bash
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Cancelled /do #${DO_ID}: ${DESCRIPTION}\"" .planning/state.yaml
yq -i ".session.last_error = null" .planning/state.yaml
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```

### Step 3: Update plan.md

Add status `cancelled` and reason.

---

## Status Transitions

```
pending → in_progress → completed
pending → cancelled
in_progress → failed → in_progress (retry)
in_progress → cancelled
```

- `pending`: Initial status at task creation (before exploration begins)
- `in_progress`: Task is being actively worked on
- `completed`: All tasks done, summary created
- `cancelled`: Cancelled by user (only from `pending` or `in_progress`)
- `failed`: Execution error occurred — record error in `session.last_error`, can retry

### Handling `failed` transition

On execution error:
```bash
# XC-003: Record error on failure
yq -i ".session.last_error = \"${ERROR_MESSAGE}\"" .planning/state.yaml
yq -i ".session.last_activity = \"$(date -Iseconds)\"" .planning/state.yaml
yq -i ".session.last_action = \"Failed /do #${DO_ID}: ${ERROR_MESSAGE}\"" .planning/state.yaml

# Update task status
yq -i "(.active[] | select(.id == \"${DO_ID}\")).status = \"failed\"" .planning/do/DO.yaml
```

## Constraints

- Maximum 5 tasks per /do plan
- If more — suggest creating a feature instead
- Do not use for architectural changes
- Maximum 3 active /do tasks simultaneously (recommendation)

## Success Criteria

- [ ] DO.yaml exists and is up-to-date
- [ ] Each task has a directory with plan.md
- [ ] Commits are atomic with reference to /do #ID
- [ ] History is preserved in DO.yaml completed array
- [ ] Statistics are updated
