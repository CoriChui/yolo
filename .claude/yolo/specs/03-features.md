# Feature Layer

## Purpose

Feature is an atomic work unit with clear scope. Features can belong to a release or exist standalone. They explore the codebase, plan, execute, and verify.

## Key Concept

**Feature = Explore → Plan → Execute → Verify**

Features can be:
- **Release-scoped**: Created during `/release start`, live in `releases/id/features/`
- **Standalone**: Created independently, live in `features/`

## Structure

### Release Features (nested inside release)

```
releases/2026-02-04-mvp/
├── release.yaml
├── intake/
└── features/                      # Release-scoped features
    ├── 01-foundation/
    │   ├── feature.yaml
    │   ├── research/
    │   │   └── discovery.md
    │   ├── plan.md
    │   ├── verification.md
    │   └── summary.md
    │
    └── 02-auth/
        └── ...
```

### Standalone Features (no release)

```
features/                          # Standalone features
├── dark-mode/
│   ├── feature.yaml
│   ├── research/
│   ├── plan.md
│   └── summary.md
│
└── export-csv/
    └── ...
```

## Feature ID

### Release Features
Sequential number within release:
- `01-foundation`
- `02-auth`
- `03-billing`

### Standalone Features
Slug only:
- `dark-mode`
- `export-csv`
- `performance-optimization`

## feature.yaml

### Release Feature

```yaml
# releases/2026-02-04-mvp/features/02-auth/feature.yaml

id: "02"
name: auth
title: "Authentication and Authorization"
created: 2026-02-05T10:00:00Z

# Context
release: "2026-02-04-mvp"          # Parent release
depends_on: ["01-foundation"]

# Goal
goal: |
  Implement authentication via Supabase Auth
  with 2FA support for enhanced security.

# Success criteria
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

# Progress
status: in_progress             # pending | researching | planning | in_progress | blocked | verifying | completed | dropped
started_at: 2026-02-05T10:00:00Z
completed_at: null

# Tasks (from plan.md)
tasks:
  total: 8
  completed: 5
  current: "Implement password reset"

# Research
research:
  required: true
  completed: true
  file: research/discovery.md
```

### Standalone Feature

```yaml
# features/dark-mode/feature.yaml

id: "dark-mode"
name: dark-mode
title: "Dark Mode Theme Support"
created: 2026-02-10T14:00:00Z

# Context
release: null                      # No release (standalone)
depends_on: []

# Goal
goal: |
  Add dark mode support with system preference detection
  and manual toggle.

# Success criteria
success_criteria:
  - "Dark mode colors applied correctly"
  - "Respects system preference by default"
  - "User can toggle manually"
  - "Preference persists between sessions"

# Requirements
requirements: []

# Progress
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

## Feature Lifecycle

```
┌─────────────┐
│   pending   │  ← Feature created (auto or manual)
└──────┬──────┘
       │
       │ /feature start <id> [--release <id>]
       ↓
┌─────────────┐
│ researching │  ← Research agent explores codebase + intake
└──────┬──────┘
       │
       │ Research completed
       ↓
┌─────────────┐
│  planning   │  ← Plan agent creates plan.md
└──────┬──────┘
       │
       │ plan.md created
       ↓
┌─────────────┐
│ in_progress │  ← Executing tasks
└──────┬──────┘
       │
       │ All tasks completed
       ↓
┌─────────────┐
│  verifying  │  ← Checking success criteria
└──────┬──────┘
       │
       │ Verification passed
       ↓
┌─────────────┐
│  completed  │  ← summary.md created, commit
└─────────────┘
```

## Auto-Creation from Research

When `/release start` runs, features are automatically created from research:

```
/release start 2026-02-04-mvp
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Research explores codebase + intake                            │
│                                                                 │
│  Findings:                                                      │
│  - Need foundation setup (DB, routing)                          │
│  - Need auth system                                             │
│  - Need billing module                                          │
└──────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Auto-create features:                                          │
│                                                                 │
│  releases/2026-02-04-mvp/features/                              │
│  ├── 01-foundation/feature.yaml  ← Created                      │
│  ├── 02-auth/feature.yaml        ← Created                      │
│  └── 03-billing/feature.yaml     ← Created                      │
│                                                                 │
│  User reviews and approves feature breakdown                    │
└─────────────────────────────────────────────────────────────────┘
```

## Attach / Detach

Features can move between standalone and release-scoped:

### Attach: Standalone → Release

```bash
/feature attach dark-mode 2026-02-04-mvp
```

**Preconditions:** Feature status must be `pending` or `completed` for safe operation. Features with running agents should not be moved. `depends_on` entries referencing features in the source release/context should be reviewed.

1. Move `features/dark-mode/` → `releases/2026-02-04-mvp/features/04-dark-mode/`
2. Assign sequential ID within release
3. Update `feature.yaml`: `release: "2026-02-04-mvp"`
4. Update `release.yaml`: add to features list
5. Update `state.yaml`

### Detach: Release → Standalone

```bash
/feature detach 02-auth 2026-02-04-mvp
```

**Preconditions:** Feature status must be `pending` or `completed` for safe operation. Features with running agents should not be moved. `depends_on` entries referencing features in the source release/context should be reviewed.

1. Move `releases/2026-02-04-mvp/features/02-auth/` → `features/auth/`
2. Convert ID to slug
3. Update `feature.yaml`: `release: null`
4. Update `release.yaml`: remove from features list
5. Update `state.yaml`

**Note:** Features cannot move directly between releases. To move from release A to release B:
1. Detach from A (becomes standalone)
2. Attach to B

## plan.md

```markdown
# Feature 02: Auth — Plan

**Goal:** Implement authentication via Supabase Auth with 2FA
**Release:** 2026-02-04-mvp

## Codebase Context

Based on exploration:
- Supabase client already configured in src/integrations/
- No existing auth components
- User type defined but not used

## Tasks

### 1. Set up Supabase Auth client
- [ ] Configure supabase client with auth
- [ ] Add AuthProvider to App.tsx
- [ ] Create useAuth hook

### 2. Login flow
- [ ] Create LoginPage component
- [ ] Implement login form
- [ ] Handle errors
- [ ] Redirect after successful login

### 3. Two-factor authentication
- [ ] Add two_factor_codes table
- [ ] Implement code sending
- [ ] Create code entry form

### 4. Password reset
- [ ] Create ForgotPasswordPage
- [ ] Create ResetPasswordPage

### 5. Session persistence
- [ ] Configure persistSession
- [ ] Test after reload

## Acceptance Criteria

- [ ] User can login via email/password
- [ ] User can enable 2FA
- [ ] Session persists between reloads
- [ ] User can reset password
```

## research/discovery.md

```markdown
# Feature 02: Auth — Research

## Codebase Exploration

### Existing Setup
- Supabase client: src/integrations/supabase/client.ts
- Types: src/integrations/supabase/types.ts
- No auth components yet

### Patterns Found
- React Query for data fetching
- Zustand for state
- shadcn/ui components

## Technical Research

### Supabase Auth
- Built-in email/password support
- Session management out of the box
- No built-in 2FA — need custom table

## Recommendation

Use Supabase Auth + custom 2FA via table.
```

## summary.md

```markdown
# Feature 02: Auth — Summary

**Status:** Completed
**Release:** 2026-02-04-mvp
**Duration:** 2026-02-05 → 2026-02-08

## Delivered

- ✅ Email/password login
- ✅ Two-factor authentication
- ✅ Session persistence
- ✅ Password reset

## Changes

### Created files
- src/pages/Login.tsx
- src/pages/ForgotPassword.tsx
- src/pages/ResetPassword.tsx
- src/components/auth/TwoFactorForm.tsx
- src/hooks/useAuth.ts

### Modified files
- src/App.tsx (added AuthProvider)

### Database
- Added two_factor_codes table

## Commits

- feat(02-01): Set up Supabase Auth client
- feat(02-02): Implement login flow
- feat(02-03): Add two-factor authentication
- feat(02-04): Implement password reset
- feat(02-05): Session persistence
```

## Commands

```bash
# Feature management
/feature start <id>              # Start feature (→ researching → planning)
/feature start <id> --release <release-id>  # Start feature <id> within specific release (for disambiguation when multiple releases have features)
/feature start <slug>            # Start standalone feature
/feature plan                    # Create plan.md
/feature execute                 # Execute tasks
/feature verify                  # Check success criteria
/feature complete                # Complete feature

# Creating standalone feature
/feature new <slug>              # Create new standalone feature

# Attach/Detach
/feature attach <feature> <release>   # Standalone → Release
/feature detach <feature> <release>   # Release → Standalone

# Viewing
/feature status                  # Current feature status
/feature show <id>               # Specific feature details
/feature list                    # List all features (release + standalone)
/feature list --release <id>     # List features in specific release
/feature list --standalone       # List standalone features only

# Research
/research [topic]                # Conduct research
```

## Rules

1. **Features can be standalone** — don't require a release
2. **Release features are nested** — in `releases/id/features/`
3. **Standalone features in root** — in `features/`
4. **Explore codebase first** — understand what exists
5. **Planning before execution** — plan.md first
6. **Verification is mandatory** — check success criteria
7. **Summary captures results** — what was done, what changed
8. **Attach/detach is explicit** — features don't move automatically
9. **No direct release-to-release moves** — must detach first

## Agent Phase Mapping

Each feature phase maps to a specific agent contract and implementation:

| Phase | Status | Agent Contract | Implementations | Default (balanced) |
|-------|--------|----------------|------------------|--------------------|
| Research | `researching` | `research` | thorough, quick, interactive | thorough (opus) |
| Planning | `planning` | `plan` | detailed, minimal | detailed (opus) |
| Execution | `in_progress` | `execute` | standard, fix | standard (sonnet) |
| Verification | `verifying` | `verify` | strict, basic | basic (haiku) |
| Decision (if needed) | — | `decide` | conversation | conversation (opus) |

### Agent Invocation Flow

```
/feature start <goal>
    ↓
Workflow reads state.yaml
    ↓
spawn_agent("research-${profile.research}", {
  goal: FEATURE_GOAL,
  scope: SCOPE,
  intake: { version, path }
})
    ↓ returns: findings, patterns, gaps, intake_insights
spawn_agent("plan-${profile.plan}", {
  goal: FEATURE_GOAL,
  context: research.findings,
  intake_insights: research.intake_insights,
  gaps: research.gaps
})
    ↓ returns: tasks[], execution_order
for each task in execution_order:
  spawn_agent("execute-${profile.execute}", {
    task: task,
    context: task.files
  })
    ↓ returns: status, files_changed, commit_message
spawn_agent("verify-${profile.verify}", {
  criteria: plan.tasks[*].verification,
  files: execute_results[*].files_changed
})
    ↓ returns: passed, results[], issues[]
Workflow updates state.yaml
```

### Agent Statelessness Rule

Agents MUST NOT:
- Read or write `.planning/state.yaml`
- Modify `feature.yaml` or `plan.md` directly
- Access other features' directories

Agents receive all context via input and return structured output. Workflows handle all state updates.

## Extended Feature Statuses

| Status | Meaning | Transitions From | Transitions To |
|--------|---------|------------------|----------------|
| `pending` | In roadmap, not started | (initial) | `researching`, `dropped` |
| `researching` | Research agent exploring | `pending` | `planning` |
| `planning` | Plan agent creating tasks | `researching` | `in_progress`, `pending` (rejected) |
| `in_progress` | Execute agent working | `planning`, `verifying` (failed) | `verifying`, `blocked` |
| `blocked` | Waiting on dependency | `in_progress` | `in_progress` (unblocked) |
| `verifying` | Verify agent checking | `in_progress` | `completed`, `in_progress` (failed) |
| `completed` | All criteria met | `verifying` | (terminal) |
| `dropped` | Removed from scope | `pending`, `planning` | (terminal) |

### Blocked State Details

When a feature enters `blocked`:

```yaml
# feature.yaml
status: blocked
blocked:
  since: 2026-02-05T10:00:00Z
  reason: "Waiting for auth feature to complete"
  dependency: "01-auth"         # Feature ID or external reference
  type: feature | external | technical
```

Unblocking:
- Automatic when `depends_on` feature reaches `completed`
- Manual via `/feature unblock <id>`

## Dependency Enforcement

### Rules

1. Feature CANNOT enter `in_progress` if any `depends_on` feature is not `completed`
2. `/feature start` WILL warn and block if dependencies are unmet
3. Circular dependencies are rejected at plan creation time
4. Use `--force` to override dependency check (at your own risk)
5. Dependencies are NOT transitive. If feature C depends on B, and B depends on A, feature C must explicitly list both A and B in `depends_on` if it requires A to be completed.

### Dependency Check Algorithm

```
function can_start(feature):
  for dep_id in feature.depends_on:
    dep = load_feature(dep_id)
    if dep.status != "completed":
      return { blocked: true, reason: f"{dep_id} is {dep.status}" }
  return { blocked: false }
```

### Cross-Context Dependencies

Dependencies can reference features outside the current context:

| Format | Example | Meaning |
|--------|---------|---------|
| `"01-foundation"` | Same release feature | Feature 01 in same release |
| `"release:<release-id>/<feature-id>"` | Cross-release | Feature in different release |
| `"standalone:<feature-slug>"` | Standalone | Standalone feature |

```
function resolve_dependency(dep_ref, current_release):
  if dep_ref.startsWith("release:"):
    parts = dep_ref.replace("release:", "").split("/")
    return load_feature_from_release(parts[0], parts[1])
  elif dep_ref.startsWith("standalone:"):
    slug = dep_ref.replace("standalone:", "")
    return load_standalone_feature(slug)
  else:
    # Default: same release
    return load_feature_from_release(current_release, dep_ref)
```

**Note:** Cross-context dependencies should be used sparingly. Prefer same-release dependencies when possible.

### Cascading Updates

When a feature completes:
1. Check all features that `depends_on` this feature
2. If ALL their dependencies are now `completed`, auto-transition from `blocked` to `in_progress`
3. Notify user of newly unblocked features

## Task Tracking

### Source of Truth: `plan.md`

`plan.md` is the canonical source for task definitions and status (checkboxes).

`feature.yaml.tasks` is a **computed summary** updated by workflows:

| Event | Updates |
|-------|---------|
| `/feature plan` completes | Sets `tasks.total`, initializes `tasks.completed = 0` |
| Task execution completes | Increments `tasks.completed`, updates `tasks.current` |
| `/feature complete` | Verifies `tasks.completed == tasks.total` |

### Reconciliation

If `feature.yaml.tasks` drifts from `plan.md`:
- `plan.md` always wins
- `/feature status` recalculates from `plan.md` checkboxes
- Workflows re-sync on every feature operation

## Verification Output

The verify agent produces `verification.md`:

```markdown
# Feature NN: <Title> — Verification

## Summary
**Result:** PASS | FAIL
**Verified at:** 2026-02-05T16:00:00Z
**Agent:** verify-strict

## Criteria Results

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | User can login via email/password | PASS | Unit test passes, manual test OK |
| 2 | Session persists between reloads | PASS | e2e test confirms |
| 3 | Password reset sends email | FAIL | Email service not configured |

## Issues Found

### Issue 1: Email service not configured
- **Severity:** error
- **File:** src/services/email.ts
- **Details:** Email transport is using mock in production config
- **Suggestion:** Add real SMTP configuration

## Next Steps
- [ ] Fix email service configuration
- [ ] Re-run verification
```

## Error Handling

| Failure | Feature Status | Recovery |
|---------|---------------|----------|
| Research agent fails | Stays `researching` | Retry `/feature start` |
| Research finds nothing relevant | Returns to `pending` | User refines goal or scope |
| Plan agent fails | Stays `researching` | Retry plan or user creates manual plan |
| Plan rejected by user | Returns to `pending` | User refines goal |
| Execute agent fails on task | Stays `in_progress` | Trigger `on-execution-failed` → fix agent |
| Task blocked by dependency | Moves to `blocked` | Wait or `/feature unblock --force` |
| Verification fails | Returns to `in_progress` | Fix issues, re-verify |
| Feature impossible | Move to `dropped` | `/feature drop <id> --reason "..."` |

### Iteration / Rework

If a completed feature needs changes:
1. Create a new feature for the change (preferred)
2. OR: `/feature reopen <id>` returns to `in_progress`
   - Requires justification
   - Creates audit entry in feature.yaml
   - Previous verification preserved in `verification-v1.md`
