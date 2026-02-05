# YAML Schemas

## Intake Manifest

```yaml
# releases/2026-02-04-mvp/intake/mvp-v1/manifest.yaml

version: "mvp-v1"                  # String: {slug}-v{number}
type: major                        # Enum: major | patch
created: 2026-02-03T15:00:00Z
release: "2026-02-04-mvp"          # Parent release ID

# Sources
sources:
  - name: figma
    captured_at: 2026-02-03T15:00:00Z
    files: 42
    digest: figma/digest.md
  - name: notion
    captured_at: 2026-02-03T14:30:00Z
    files: 5
    digest: notion/digest.md
  - name: notes
    captured_at: 2026-02-03T16:00:00Z
    files: 3
    digest: null                   # Manual, no digest

# For patch versions
parent: null                       # String: parent version ("mvp-v1" for mvp-v1.1)

trigger:
  type: null                       # proposal | external | manual
  ref: null                        # Reference to trigger source

# Stats
stats:
  total_files: 50
  sources: 3
```

---

## Release

```yaml
# releases/2026-02-04-mvp/release.yaml

id: "2026-02-04-mvp"               # Full ID: YYYY-MM-DD-slug
slug: "mvp"                        # User-provided slug
title: "MVP — Basic Rental System"
created: 2026-02-04T15:00:00Z

# Goal
goal: |
  Working moped rental management system:
  units, clients, contracts, basic billing.

success_criteria:
  - "Operator can create a rental contract"
  - "System charges daily fee automatically"
  - "Financier sees balance for each client"

# Intake (release-scoped)
intake:
  current: "mvp-v1.1"              # Current version
  locked: false                    # Locked when release completes

# Features (nested in release)
features:
  total: 4
  completed: 2

  list:
    - id: "01"
      name: foundation
      status: completed
      completed_at: 2026-02-05T18:00:00Z

    - id: "02"
      name: auth
      status: completed
      completed_at: 2026-02-08T16:00:00Z

    - id: "03"
      name: billing
      status: in_progress
      started_at: 2026-02-08T17:00:00Z

    - id: "04"
      name: repairs
      status: pending

# Progress (derived/cached — computed from features section)
progress:
  features_total: 4
  features_completed: 2
  percentage: 50

# Status
status: active                     # Enum: pending | active | paused | completed | failed | cancelled
started_at: 2026-02-04T15:00:00Z
completed_at: null
paused_at: null
failed_at: null
cancelled_at: null

# Archive (filled on completion)
archive:
  shipped_at: null
  git_range: null
  stats:
    features: null
    tasks: null
    files_changed: null
```

---

## Feature (Release-scoped)

```yaml
# releases/2026-02-04-mvp/features/02-auth/feature.yaml

id: "02"
name: auth
title: "Authentication and Authorization"
created: 2026-02-05T10:00:00Z

# Context
release: "2026-02-04-mvp"          # Parent release (not null for release features)
depends_on:
  - "01-foundation"

# Goal
goal: |
  Implement authentication via Supabase Auth
  with 2FA support for enhanced security.

success_criteria:
  - "User can login via email/password"
  - "User can enable 2FA"
  - "Session persists between reloads"
  - "User can reset password"

# Requirements (from release's requirements.md)
requirements:
  - AUTH-01
  - AUTH-02
  - AUTH-03

# Status
status: completed                  # Enum: pending | researching | planning | in_progress | blocked | verifying | completed | dropped
started_at: 2026-02-05T10:00:00Z
completed_at: 2026-02-08T16:00:00Z

# Blocked (populated when status: blocked)
blocked:
  since: null
  reason: null
  dependency: null
  type: null                       # Enum: feature | external | technical

# Tasks (synced from plan.md)
tasks:
  total: 8
  completed: 8
  current: null

# Research
research:
  required: true
  completed: true
  file: research/discovery.md
```

---

## Feature (Standalone)

```yaml
# features/dark-mode/feature.yaml

id: "dark-mode"                    # Slug ID for standalone
name: dark-mode
title: "Dark Mode Theme Support"
created: 2026-02-10T14:00:00Z

# Context
release: null                      # null = standalone feature
depends_on: []

# Goal
goal: |
  Add dark mode support with system preference detection
  and manual toggle.

success_criteria:
  - "Dark mode colors applied correctly"
  - "Respects system preference by default"
  - "User can toggle manually"
  - "Preference persists between sessions"

# Requirements (none for standalone)
requirements: []

# Status
status: pending
started_at: null
completed_at: null

# Tasks
tasks:
  total: 0
  completed: 0
  current: null

# Research
research:
  required: true
  completed: false
  file: null
```

---

## State

```yaml
# .planning/state.yaml

schema_version: 2                  # Updated schema version

updated_at: 2026-02-10T14:30:00Z
updated_by: feature-complete

# Lock
lock:
  held_by: null
  acquired_at: null
  expires_at: null

_checksum: null

# ═══════════════════════════════════════════════════════════════
# FOCUS
# ═══════════════════════════════════════════════════════════════
focus:
  release: "2026-02-04-mvp"        # Currently focused release
  feature: "03-billing"            # Currently active feature
  feature_release: "2026-02-04-mvp"  # Feature's release (null if standalone)

# ═══════════════════════════════════════════════════════════════
# RELEASES (all active/pending)
# ═══════════════════════════════════════════════════════════════
releases:
  - id: "2026-02-04-mvp"
    slug: "mvp"
    status: active                 # pending | active | paused | completed | failed | cancelled
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
# CURRENT FEATURE
# ═══════════════════════════════════════════════════════════════
feature:
  id: "03-billing"
  release: "2026-02-04-mvp"        # null if standalone
  status: in_progress              # Enum: pending | researching | planning | in_progress | blocked | verifying | completed | dropped

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
# METRICS
# ═══════════════════════════════════════════════════════════════
metrics:
  releases_completed: 0
  features_completed: 2
  total_tasks_completed: 14
```

---

## DO Task

```yaml
# .planning/do/DO.yaml

active:
  - id: "003"
    description: "Add rate limiting"
    started: "2026-02-03"
    status: in_progress
    progress: { completed: 2, total: 3 }
    directory: "003-add-rate-limiting"

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

## Debug Session

```yaml
# .planning/debug/<session-id>/session.yaml

id: "auth-token-expired"
created: 2026-02-03T10:00:00Z
updated: 2026-02-03T14:30:00Z

# Status
status: investigating             # gathering | investigating | fixing | verifying | resolved | abandoned

# Trigger
trigger: |
  Token expires too fast, users get logged out after 1 minute

# Symptoms
symptoms:
  expected: "Token should last 24 hours"
  actual: "Token expires after 60 seconds"
  errors: "JWT expired error in console"
  reproduction: "Login, wait 1 minute, refresh page"
  timeline: "Started after Redis update"

# Focus
focus:
  hypothesis: "Redis TTL config"
  test: "Check Redis TTL settings"
  expecting: "TTL should be 86400, might be 60"
  next: "Run redis-cli TTL command"

# Eliminated
eliminated:
  - hypothesis: "Cache issue"
    evidence: "Cache disabled, same behavior"
    when: "2026-02-03T11:00:00Z"

# Evidence
evidence:
  - checked: "Redis logs"
    found: "TTL set to 60s"
    implication: "Token expires in 1 min"
    when: "2026-02-03T12:00:00Z"

# Resolution (empty until resolved)
resolution:
  root_cause: null
  fix: null
  verification: null
  files_changed: []
```

---

## Sync Config

```yaml
# .planning/sync/config.yaml

tracker: github

github:
  repository: owner/repo          # Auto-detected from git remote

mapping:
  release:                         # YOLO release ← tracker types
    - epic
    - initiative
  feature:                         # YOLO feature ← tracker types
    - feature
    - story
    - user-story
  do:                              # YOLO do ← tracker types
    - bug
    - fix
    - hotfix
    - task
    - chore
  feature-task:                    # YOLO feature-task ← tracker types
    - subtask

sync:
  direction: import               # import | bidirectional
  conflict_resolution: tracker    # tracker wins
  import_comments: true
  import_status: true
  auto_refresh: on-pull           # on-pull | manual | scheduled
```

---

## Schema Corrections and Additions

### Manifest Schema (Complete)

The manifest schema with all fields from `templates/manifest.yaml`:

```yaml
# .planning/releases/<release>/intake/<version>/manifest.yaml
version: null                      # e.g., "mvp-v1"
type: major                        # major | patch
created: null                      # ISO 8601
release: null                      # Release ID

trigger:
  type: null                       # proposal | external | manual
  ref: null                        # Reference to trigger source

sources: []
# Each source:
#   - name: <source>              # Any source from catalog (figma, notion, gdocs, db, openapi, etc.)
#     captured_at: null            # ISO 8601
#     files: 0                     # Number of .md digest files
#     digest: "<source>/digest.md"

contents:
  domain: []                       # Entity files
  contracts: []                    # API contracts, interfaces
  flows: []                        # User flows, sequences
  constraints: []                  # Business rules, limits
  assets:                          # Binary resources (optional)
    screenshots: 0
    exports: 0

notes: null                        # Free-form notes
```

---

### Proposal Schema

```yaml
# .planning/intake/<version>/proposal.yaml
id: null                           # Proposal ID
title: null                        # Proposal title
created: null                      # ISO 8601
author: null                       # Who proposed

status: draft                      # draft | approved | rejected | superseded

summary: null                      # Brief description
motivation: null                   # Why this change

changes:
  sources_to_add: []               # New intake sources to capture
  sources_to_update: []            # Existing sources to re-capture
  sources_to_remove: []            # Sources to remove

impact:
  affected_features: []            # Feature IDs that may need re-evaluation
  breaking_changes: false          # Does this invalidate existing plans?

approval:
  approved_by: null                # User
  approved_at: null                # ISO 8601
  notes: null                      # Approval notes
```

---

## Agent Output Schemas

Agents return structured output matching their contract. These are NOT stored in files — they are passed between pipeline stages.

### Research Agent Output

> **Note:** Intake path should be release-scoped: `.planning/releases/<release>/intake/<version>`.

```yaml
findings: |
  Markdown summary of codebase exploration...
relevant_files:
  - src/models/user.ts
  - src/services/auth.ts
patterns:
  - "Repository pattern for data access"
  - "JWT for authentication"
intake_insights:                   # Only if intake provided
  - source: "figma/digest.md"
    insight: "Login screen requires email + password"
    applies_to: ["src/components/Login.tsx"]
gaps:                              # Intake requirements not in codebase
  - requirement: "Password reset flow"
    current_state: "No reset endpoint exists"
    gap: "Need /api/reset-password endpoint + email service"
concerns:
  - "No rate limiting on auth endpoints"
suggestions:
  - "Consider adding CSRF protection"
user_decisions: []                 # Optional: decisions requiring user input
```

### Plan Agent Output

```yaml
tasks:
  - id: "create-user-model"
    title: "Create user model"
    description: |
      Create TypeScript interface and Prisma model for User...
    files: ["src/models/user.ts", "prisma/schema.prisma"]
    depends_on: []
    verification: "User model exports correct interface"
    intake_ref: "Login screen requirement"
  - id: "setup-auth-endpoints"
    title: "Add auth endpoints"
    description: |
      Create login, register, logout API routes...
    files: ["src/api/auth.ts", "src/middleware/auth.ts"]
    depends_on: ["create-user-model"]
    verification: "Auth endpoints respond with correct status codes"
execution_order: ["create-user-model", "setup-auth-endpoints"]
risks:
  - "Email service dependency for password reset"
assumptions:
  - "PostgreSQL is the database"
coverage:
  - requirement: "User can login"
    addressed_by: ["create-user-model", "setup-auth-endpoints"]
```

### Execute Agent Output

```yaml
status: completed                  # completed | blocked | failed
files_changed:
  - path: "src/models/user.ts"
    action: created
  - path: "prisma/schema.prisma"
    action: modified
commit_message: "Add User model with TypeScript interface"
blockers: []                       # Only if status: blocked
notes: |
  Created User interface with id, email, password hash, timestamps.
  Added Prisma model matching the interface.
```

### Verify Agent Output

```yaml
passed: false
results:
  - criterion: "User model exports correct interface"
    passed: true
    evidence: "src/models/user.ts exports UserInterface"
  - criterion: "Auth endpoints respond correctly"
    passed: false
    evidence: "POST /login returns 500 — missing db connection"
issues:
  - severity: error
    message: "Database connection not configured"
    file: "src/api/auth.ts"
    line: 42
    suggestion: "Add DATABASE_URL to .env"
  - severity: warning
    message: "No input validation on login endpoint"
    file: "src/api/auth.ts"
    line: 42
    suggestion: "Add zod schema validation"
```

### Decide Agent Output

```yaml
decision: "Use JWT with refresh tokens"
rationale: |
  JWT provides stateless auth, refresh tokens handle expiry...
approach: |
  1. Short-lived access token (15min)
  2. Long-lived refresh token (7d) in httpOnly cookie
  3. Token rotation on refresh
alternatives_considered:
  - option: "Session-based auth"
    pros: ["Simpler", "Easy revocation"]
    cons: ["Requires session store", "Not stateless"]
    why_rejected: "Project uses microservices, need stateless"
```

---

## ID Format Reference

| Entity | Format | Example | Notes |
|--------|--------|---------|-------|
| Release ID | `YYYY-MM-DD-slug` | `2026-02-04-mvp` | Date of creation + slug |
| Feature ID (release) | `NN-slug` | `02-auth` | Zero-padded sequential number |
| Feature ID (standalone) | `slug` | `dark-mode` | Lowercase, hyphens only |
| Intake Version | `{slug}-v{N}[.{M}]` | `mvp-v1.1` | Release slug prefix |
| DO Task ID | `NNN` | `003` | Zero-padded three-digit |
| Debug Session ID | `{slug}` | `auth-token-expired` | Descriptive slug, lowercase hyphens |
| Task ID (in plan) | `{slug}` | `setup-auth-middleware` | Slug-based within feature |
| Proposal ID | `prop-{feature}-{seq}` | `prop-02-001` | Feature-scoped sequential |
| Sync Item ID | external reference | `GH#123` | External tracker reference |

### Validation Rules

- Slugs: lowercase alphanumeric + hyphens, max 50 characters
- Dates: ISO 8601 format (`YYYY-MM-DD` or full datetime)
- Numbers: Zero-padded to their format width
