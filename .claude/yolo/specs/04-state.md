# State Management

## Purpose

state.yaml is the single point of project state. Read first in every workflow. Tracks all active releases and the current focus.

## Location

```
.planning/state.yaml
```

## Format

```yaml
# .planning/state.yaml

# Format version
schema_version: 2

# Last update
updated_at: 2026-02-10T14:30:00Z
updated_by: feature-complete

# ═══════════════════════════════════════════════════════════════
# FOCUS (what we're working on now)
# ═══════════════════════════════════════════════════════════════
focus:
  release: "2026-02-04-mvp"          # Currently focused release (null if none)
  feature: "03-billing"               # Currently active feature
  feature_release: "2026-02-04-mvp"  # Release of current feature (null if standalone)

# ═══════════════════════════════════════════════════════════════
# RELEASES (all active/pending releases)
# ═══════════════════════════════════════════════════════════════
releases:
  - id: "2026-02-04-mvp"
    slug: "mvp"
    status: active                    # pending | active | completed
    created: 2026-02-04T10:00:00Z
    started_at: 2026-02-04T14:00:00Z
    intake:
      current: "mvp-v1.1"
      locked: false
    progress:
      features_total: 4
      features_completed: 2
      percentage: 50

  - id: "2026-02-10-mobile"
    slug: "mobile"
    status: pending
    created: 2026-02-10T09:00:00Z
    started_at: null
    intake:
      current: "mobile-v1"
      locked: false
    progress:
      features_total: 0
      features_completed: 0
      percentage: 0

# ═══════════════════════════════════════════════════════════════
# STANDALONE FEATURES
# ═══════════════════════════════════════════════════════════════
standalone_features:
  total: 2
  active: 0
  list:
    - id: "dark-mode"
      status: pending
    - id: "export-csv"
      status: pending

# ═══════════════════════════════════════════════════════════════
# CURRENT FEATURE (detailed)
# ═══════════════════════════════════════════════════════════════
feature:
  id: "03-billing"
  release: "2026-02-04-mvp"           # null if standalone
  status: in_progress                  # pending | researching | planning | in_progress | blocked | verifying | completed | dropped

  tasks:
    total: 6
    completed: 2
    current: "Implement payment acceptance"

  started_at: 2026-02-08T09:00:00Z

# ═══════════════════════════════════════════════════════════════
# SESSION
# ═══════════════════════════════════════════════════════════════
session:
  last_activity: 2026-02-10T14:30:00Z
  last_action: "Completed task: Set up billing service"

  last_error:
    at: null
    workflow: null
    message: null
    recoverable: null
    recovery_hint: null

  resume:
    context: |
      Working on Feature 03: Billing in release 2026-02-04-mvp.
      Completed billing service setup.
      Next task: implement payment acceptance.

      Other active releases:
      - 2026-02-10-mobile (pending, not started)

# ═══════════════════════════════════════════════════════════════
# METRICS (optional)
# ═══════════════════════════════════════════════════════════════
metrics:
  releases_completed: 0
  features_completed: 2
  total_tasks_completed: 14

# ═══════════════════════════════════════════════════════════════
# LOCK
# ═══════════════════════════════════════════════════════════════
lock:
  held_by: null
  acquired_at: null
  expires_at: null

# Integrity checksum (hash of state excluding _checksum and lock)
_checksum: null
```

## Key Concepts

### Focus

The `focus` section tracks what the user is currently working on:
- `release`: The release that commands operate on by default
- `feature`: The currently active feature
- `feature_release`: Which release the current feature belongs to (null for standalone)

### Releases Array

All pending and active releases are tracked in the `releases` array. Each entry includes:
- Status and progress
- Intake state (current version, locked status)
- Timestamps

Completed releases are removed from this array (moved to archive).

### Standalone Features

Features without a release are tracked separately in `standalone_features`.

## When Read

| Workflow | What It Reads |
|----------|---------------|
| `/status` | Everything |
| `/release *` | focus.release, releases array |
| `/release focus` | Reads focus, writes focus.release |
| `/feature *` | feature section, focus |
| `/intake *` | focus.release → release.intake |
| Resume | session.resume |
| Pipeline executor | focus, releases[focused].intake |
| Agent orchestrator | feature section (to construct agent input) |

## When Updated

| Event | What Gets Updated |
|-------|-------------------|
| Release created | releases array, focus.release |
| Release started | releases[id].status, releases[id].started_at |
| Release focus changed | focus.release, focus.feature, feature section |
| Release completed | releases array (removed), archive |
| Intake captured | releases[id].intake.current |
| Feature started | feature section, focus.feature |
| Feature attached | standalone_features, releases[id].progress |
| Feature detached | standalone_features, releases[id].progress |
| Task completed | feature.tasks.completed |
| Feature completed | feature.status, releases[id].progress |
| Any activity | session.last_activity, session.last_action |

## Commands

```bash
/status                           # Show current state
/status --full                    # Detailed output
/status --releases                # Focus on releases
```

## /status Output

```
══════════════════════════════════════════════════════════════════
PROJECT STATUS
══════════════════════════════════════════════════════════════════

RELEASES (2 active)
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

STANDALONE FEATURES (2)
──────────────────────────────────────────────────────────────────
  ○ dark-mode (pending)
  ○ export-csv (pending)

LAST ACTIVITY: 14:30 today
  "Completed task: Set up billing service"

══════════════════════════════════════════════════════════════════
NEXT ACTIONS:
  /task next              — Continue with current task
  /feature status         — See feature details
  /release focus <id>     — Switch to different release
══════════════════════════════════════════════════════════════════
```

## Invariants

1. **state.yaml always exists** after init
2. **Releases array tracks all pending/active** — completed are archived
3. **Focus points to valid release** — or null if no releases
4. **One current feature** — feature section (can be null)
5. **Updated after every action** — updated_at is current

## Focus Behavior

### Automatic Focus

- Creating a release sets it as focused
- Starting a feature sets it as current

### Manual Focus

```bash
/release focus 2026-02-10-mobile
```

Updates:
- `focus.release` → "2026-02-10-mobile"
- Commands now operate on mobile release by default

### Focus Switch Protocol

When `focus.release` changes:
- If the new release has an in-progress feature, set `focus.feature` to that feature's ID
- Otherwise, set `focus.feature` to null and clear the feature detail section

### Commands and Focus

Commands use focused release unless overridden:

| Command | Uses Focus | Override |
|---------|------------|----------|
| `/release start` | Yes | `/release start 2026-02-10-mobile` |
| `/release status` | Yes | `/release status 2026-02-10-mobile` |
| `/intake capture` | Yes | `--release 2026-02-10-mobile` |
| `/feature start 01` | Yes | `--release 2026-02-10-mobile` |

## Session Restoration

When starting a new Claude session:

1. Reads state.yaml
1b. Validate _checksum — if mismatch, warn user and offer `/status --verify --fix`
1c. Check schema_version — if outdated, run migration
2. Understands all active releases
3. Knows which release is focused
4. Uses session.resume.context for additional context
5. Continues work

```yaml
session:
  resume:
    context: |
      Working on Feature 03: Billing in release 2026-02-04-mvp.
      Completed billing service setup.
      Next task: implement payment acceptance.

      Other active releases:
      - 2026-02-10-mobile (pending, not started)

      Notes: Use Supabase functions for transactions
```

This allows Claude to instantly understand context without reading all files.

## Schema Migration

When upgrading from schema_version 1 to 2:
- Convert single release to releases array
- Add focus section
- Add standalone_features section
- Move intake inside release entries

## Workflow Lock

To prevent concurrent modifications, state.yaml uses a lightweight lock:

### Lock Schema

```yaml
# Added to state.yaml root
lock:
  held_by: null          # Workflow name (e.g., "feature-start")
  acquired_at: null      # ISO 8601 timestamp
  expires_at: null       # Auto-release after 5 minutes
```

### Lock Protocol

```
1. ACQUIRE:
   - Read state.yaml
   - If lock.held_by is null OR lock.expires_at < now():
     - Set lock.held_by = workflow_name
     - Set lock.acquired_at = now()
     - Set lock.expires_at = now() + 5min
     - Write state.yaml
     - ATOMIC WRITE GUARD: Immediately re-read state.yaml and verify
       that lock.held_by matches the current workflow. If not, back off
       (random 100-500ms delay) and retry acquisition from the start.
       In practice, Claude Code sessions are single-threaded, so concurrent
       lock acquisition is rare. This guard protects against edge cases
       with parallel sessions.
   - Else:
     - Fail: "State locked by {lock.held_by} since {lock.acquired_at}"

2. RELEASE:
   - Set lock.held_by = null
   - Set lock.acquired_at = null
   - Set lock.expires_at = null
   - Write state.yaml

3. AUTO-EXPIRE:
   - If lock.expires_at < now(), treat as unlocked
   - Prevents deadlock from crashed workflows
```

### Lock Granularity

- Lock is global (one lock for entire state.yaml)
- Fine-grained locks not needed since workflows are sequential within a session
- Lock primarily guards against corruption from context resets or parallel sessions
- Parallel sessions across different releases will contend on the global lock. This is an accepted trade-off for simplicity. Per-release locking may be introduced if contention becomes an issue.

## Agent Access Rules

Agents are **stateless** and MUST NOT interact with state directly.

> **Note:** The rules below apply to all agent variants. "execute-* agent" refers to any execute variant (e.g., execute-code, execute-test, etc.), all invoked via Task.

| Action | Allowed? | Who Does It |
|--------|----------|-------------|
| Read state.yaml | NO | Workflow passes relevant state as agent input |
| Write state.yaml | NO | Workflow updates state after agent returns |
| Read feature.yaml | NO | Workflow passes feature data as agent input |
| Write feature.yaml | NO | Workflow updates after agent returns |
| Read plan.md | YES (execute-* agent via Task) | Agent reads task details for execution |
| Write plan.md | NO | Workflow updates task checkboxes |
| Read source code | YES | All agent variants can read project source code |
| Write source code | YES (execute-* agent via Task only) | Only execute-* agent modifies code |

### Enforcement

This is enforced by convention (agent prompts) not by technical restriction. Agent baselines include:
```
<constraints>
- Never read or write .planning/state.yaml
- Never modify feature.yaml or plan.md
- All state context is provided in your input
</constraints>
```

## State Integrity

### Checksum

```yaml
# state.yaml root
_checksum: "sha256:abc123..."   # Hash of state excluding _checksum and lock
```

- Computed on every write
- Validated on every read
- Mismatch indicates external/manual edit or corruption
- On mismatch: warn user, offer recovery

**Checksum Mismatch Behavior:** Read-only workflows (e.g., /status) warn but continue. Write workflows halt and require `--force` or `/status --verify --fix` before proceeding.

### Canonical Sources for Derived Fields

| Field | Canonical Source | Derivation |
|-------|-----------------|------------|
| `releases[].progress.features_total` | Computed | Count of directories in `releases/<id>/features/` |
| `releases[].progress.features_completed` | Computed | Count where `feature.yaml` has `status: completed` |
| `releases[].progress.percentage` | Computed | `(completed / total) * 100` |
| `feature.tasks.total` | `plan.md` | Count of task entries in plan |
| `feature.tasks.completed` | `plan.md` | Count of checked `[x]` task entries |
| `standalone_features.total` | Computed | Count of `features/` directories |
| `standalone_features.active` | Computed | Count where status is in_progress/planning/researching |

### Reconciliation

`/status --verify` command:
1. Reads state.yaml
2. Computes derived fields from source files
3. Reports any discrepancies
4. Offers to fix with `--fix` flag

## Error Tracking

```yaml
# state.yaml
session:
  last_activity: 2026-02-10T15:00:00Z
  last_action: feature-complete
  last_error:                          # NEW
    at: null                           # When error occurred
    workflow: null                     # Which workflow failed
    message: null                      # Human-readable error
    recoverable: null                  # boolean
    recovery_hint: null                # Suggested recovery action
```

### Error Recording

Workflows MUST record errors before failing:
```yaml
last_error:
  at: 2026-02-10T14:30:00Z
  workflow: "feature-complete"
  message: "Verification failed: 2 of 5 criteria not met"
  recoverable: true
  recovery_hint: "Fix failing criteria and run /feature verify"
```

### Error Clearing

Errors are cleared on next successful workflow execution.

## State Backup

### Automatic Backup

Before any write operation, workflows MUST create a backup:

```bash
# Before writing state.yaml
cp .planning/state.yaml .planning/state.yaml.bak
```

This creates a single rolling backup. The `.bak` file always contains the state before the last successful write.

### Backup Protocol

All workflows that modify state.yaml follow this sequence:

```
1. Acquire lock
2. Validate _checksum
3. BACKUP: cp state.yaml state.yaml.bak
4. Modify state
5. Compute new _checksum
6. Release lock
```

### Backup Restoration

If state.yaml is corrupted but `.bak` exists:

```bash
# Restore from backup
cp .planning/state.yaml.bak .planning/state.yaml

# Verify checksum
# If valid, continue working
# If invalid, fall back to /init --recover
```

### .gitignore

The backup file should NOT be committed:

```
# Add to .gitignore
.planning/state.yaml.bak
.planning/state.yaml.lock
```

## Recovery

If state.yaml is corrupted or missing:

### Automatic Recovery

```
/init --recover
```

Process:
0. Check for `.planning/state.yaml.bak` — if valid, restore from backup first
1. Scan `releases/*/release.yaml` → rebuild `releases[]` array
2. Scan `features/*/feature.yaml` → rebuild `standalone_features`
3. Scan `releases/*/features/*/feature.yaml` → rebuild release progress
4. Set `focus` to null (user must re-focus)
5. Clear `session` context
6. Compute and set `_checksum`

### Manual Recovery

If `/init --recover` fails:
1. Delete `.planning/state.yaml`
2. Run `/init` to create fresh state
3. Manually re-focus: `/release focus <id>`
4. Re-start current feature: `/feature start <goal>`

### Prevention

- State.yaml should be committed to git regularly
- Recovery can use git history: `git checkout HEAD -- .planning/state.yaml`