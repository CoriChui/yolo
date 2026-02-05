# Release Layer

## Purpose

Release defines a body of work. It creates an intake, explores the codebase, auto-creates features from research, and produces output specs for visibility. Multiple releases can run in parallel.

## Key Concept

**Release = Create intake → Explore reality → Auto-create features → Execute → Document output**

Each release is **independent** — it starts from current codebase state, has its own intake, and does not depend on other releases.

## Release ID Format

```
YYYY-MM-DD-slug
```

Examples:
- `2026-02-04-mvp`
- `2026-02-10-mobile-app`
- `2026-03-15-billing-integration`

The date is auto-generated from when the release is created. The slug is user-provided.

## Structure

```
releases/
├── 2026-02-04-mvp/
│   ├── release.yaml           # Goal, status, feature list
│   ├── requirements.md        # What we're building
│   │
│   ├── intake/                # Release-scoped intake
│   │   ├── mvp-v1/
│   │   │   ├── manifest.yaml
│   │   │   ├── figma/
│   │   │   └── notion/
│   │   └── mvp-v1.1/
│   │
│   ├── features/              # Release-scoped features
│   │   ├── 01-foundation/
│   │   │   ├── feature.yaml
│   │   │   ├── plan.md
│   │   │   └── summary.md
│   │   └── 02-billing/
│   │
│   └── output/                # Generated after completion
│       ├── schema.md
│       ├── api.md
│       └── architecture.md
│
└── 2026-02-10-mobile/         # Another parallel release
    ├── release.yaml
    ├── intake/
    ├── features/
    └── output/
```

## release.yaml

```yaml
id: "2026-02-04-mvp"
slug: "mvp"
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
  current: "mvp-v1.1"
  locked: false

# Features (auto-created from research)
features:
  total: 4
  completed: 2

  list:
    - id: "01"
      name: foundation
      status: completed
    - id: "02"
      name: auth
      status: completed
    - id: "03"
      name: billing
      status: in_progress
    - id: "04"
      name: repairs
      status: pending

# Progress (computed from features.total / features.completed)
progress:
  percentage: 50

# Status
status: active                  # pending | active | paused | completed | failed | cancelled
started_at: 2026-02-04T15:00:00Z
completed_at: null
```

## Release Lifecycle

```
┌─────────────┐
│   pending   │  ← Release created with /release new
└──────┬──────┘     Intake directory created
       │            Can capture: /intake capture
       │
       │ /release start [id]
       ↓
┌─────────────┐
│   active    │  ← Research runs, features auto-created
└──────┬──────┘     Can still capture intake
       │            Work on features
       │
       │ /release end [id]
       ↓
┌─────────────┐
│  completed  │  ← Output specs generated
└─────────────┘     Intake locked, archived

> See Extended Release Statuses below for additional states: paused, failed, cancelled.
```

## Parallel Releases

Multiple releases can be in pending or active status simultaneously:

```
Timeline:  ──────────────────────────────────────────────────>

2026-02-04-mvp:      [=== pending ===][======= active =======][done]
2026-02-10-mobile:              [== pending ==][=== active ===]
2026-02-15-billing:                      [=== pending ===][...]
```

- Releases are **completely independent**
- No ordering constraints or dependencies
- Each has its own intake, features, and output
- State tracks all releases + one "focused" release
- **Codebase conflicts**: Parallel active releases modifying the same codebase can cause conflicts. Conflicts are handled at commit time by the user.

## Release Creation Flow

```
/release new mvp
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Generate release ID                                         │
│     - ID: 2026-02-04-mvp (date + slug)                          │
└──────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Create release structure                                    │
│     - releases/2026-02-04-mvp/release.yaml                      │
│     - releases/2026-02-04-mvp/intake/mvp-v1/ (empty)            │
│     - releases/2026-02-04-mvp/features/ (empty)                 │
└──────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Update state.yaml                                           │
│     - Add to releases array                                     │
│     - Set as focused release                                    │
└─────────────────────────────────────────────────────────────────┘

User can now: /intake capture figma, /intake capture notion, etc.
```

## Release Start Flow

```
/release start [id]            # If no id, uses focused release
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Explore codebase                                            │
│     - Spawn research-{profile.research} agent via orchestrator  │
│     - Read actual types, components, API                        │
│     - Understand what exists                                    │
│     - Identify patterns and architecture                        │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  2. Read intake for context                                     │
│     - If UI work → Figma designs                                │
│     - If new feature → requirements docs                        │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. Define goal and success criteria                            │
│     - What are we building?                                     │
│     - How do we know it's done?                                 │
│     - User approves                                             │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. Auto-create features from research                          │
│     - Use research agent output to define goals and             │
│       auto-create features                                      │
│     - Features created automatically based on research          │
│     - Each feature gets directory in releases/id/features/      │
│     - User reviews feature breakdown                            │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  5. Create requirements.md                                      │
│     - Detailed requirements                                     │
│     - Traced to features                                        │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  6. Update status (only after ALL steps complete)                │
│     - release.yaml: status → active                             │
│     - state.yaml: release status → active                       │
└─────────────────────────────────────────────────────────────────┘
```

## Release Completion Flow

```
/release end [id]
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Check feature status                                        │
│     - List all features                                         │
│     - Identify incomplete features                              │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  2. Handle incomplete features (ask user per feature)           │
│                                                                 │
│     For each incomplete feature:                                │
│     ┌─────────────────────────────────────────────────────────┐ │
│     │ Feature "03-billing" is in_progress                     │ │
│     │                                                         │ │
│     │ What would you like to do?                              │ │
│     │ [1] Complete now - mark as done                         │ │
│     │ [2] Detach - move to standalone features                │ │
│     │ [3] Archive incomplete - keep in release as-is          │ │
│     └─────────────────────────────────────────────────────────┘ │
│                                                                 │
│     - Complete: Mark feature as completed                       │
│     - Detach: Move to features/ standalone directory            │
│       (retains read-only reference to archived release intake)  │
│     - Archive: Keep in release, mark release as completed       │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. Lock intake                                                 │
│     - Mark intake as locked                                     │
│     - No more captures for this release                         │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. Generate output specs from codebase                         │
│     - output/schema.md (actual DB state)                        │
│     - output/api.md (actual endpoints)                          │
│     - output/architecture.md (system overview)                  │
│                                                                 │
│     These are for VISIBILITY, not for other releases            │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  5. Archive release                                             │
│     - Update release.yaml: status → completed                   │
│     - Update state.yaml: remove from active                     │
│     - Optionally move to archive/ directory                     │
└─────────────────────────────────────────────────────────────────┘
```

## Commands

```bash
# Creation
/release new <slug>              # Create pending release + intake
/release start [id]              # Start release (research + auto-create features)

# Viewing
/release status                  # Show all releases (focused, active, pending)
/release status <id>             # Show specific release status

# Focus
/release focus <id>              # Set focused release for other commands

# Management
/release end [id]                # Complete release (handles incomplete features)
/release pause [id]              # Pause active release (saves state, stops execution)
/release resume [id]             # Resume paused release (re-validates intake changes)
/release cancel [id]             # Cancel release (archives state, detaches incomplete features)
/release recover <id>            # Recover failed release (rebuilds state from files)

# List
/release list                    # List all releases with status
```

## Focus Mechanism

When multiple releases exist, one is marked as "focused":

```yaml
# state.yaml
focus:
  release: "2026-02-04-mvp"      # Focused release

releases:
  - id: "2026-02-04-mvp"
    status: active
    # ...
  - id: "2026-02-10-mobile"
    status: active
    # ...
```

Commands use focused release by default:
- `/release start` → starts focused release
- `/intake capture figma` → captures to focused release
- `/feature start auth` → creates feature in focused release

Explicitly specify release to override:
- `/release start 2026-02-10-mobile`
- `/intake capture figma --release 2026-02-10-mobile`

## Rules

1. **Parallel releases allowed** — multiple pending/active releases
2. **Each release is independent** — no dependencies between releases
3. **Intake scoped to release** — created on /release new
4. **Features nested in release** — releases/id/features/
5. **Auto-create features** — research creates features automatically
6. **Explore codebase** on /release start — understand reality
7. **Intake stays open** during pending and active
8. **Intake locked** when release ends
9. **Handle incomplete features** — ask user per feature on /release end
10. **Output specs are documentation** — for visibility only
11. **User approves** — goals, features, completion

## Extended Release Statuses

Beyond the core lifecycle (`pending` -> `active` -> `completed`), releases support additional states:

| Status | Meaning | Transitions From | Transitions To |
|--------|---------|------------------|----------------|
| `pending` | Created, intake open | (initial) | `active`, `cancelled` |
| `active` | Work in progress | `pending`, `paused` | `completed`, `paused`, `failed` |
| `paused` | Temporarily on hold | `active` | `active`, `cancelled` |
| `completed` | All features handled | `active` | (terminal) |
| `failed` | Unrecoverable error | `active` | `cancelled` |
| `cancelled` | User abandoned | `pending`, `paused`, `failed` | (terminal) |

### State Transition Rules

```
pending ──start──> active ──end──> completed
   │                 │ ↑
   │              pause/resume
   │                 │ ↓
   │               paused
   │                 │
   └───cancel────────┴──> cancelled
                     │
              (on error)
                     ↓
                   failed ──cancel──> cancelled
```

### Pause/Resume Behavior

- **Pause**: All feature execution stops, state saved, intake can be updated
- **Resume**: Continues from where it left off, re-validates intake changes
- **Cancel**: Archives current state, detaches incomplete features to standalone

## Validation Rules

### Start Requirements

| Field | Required | Validation |
|-------|----------|------------|
| `goal` | Yes | Non-empty string |
| `intake` | No | Release can start without intake |
| `status` | Yes | Must be `pending` |

### Completion Requirements

| Condition | Required | Action if Not Met |
|-----------|----------|-------------------|
| All features handled | Yes | Per-feature decision: complete/detach/archive |
| Output specs generated | Configurable | Skip with `--skip-output` |
| No features in `in_progress` | Yes | Must complete or pause first |

### Intake Capture Policy

| Release Status | Capture Allowed | Side Effects |
|----------------|-----------------|--------------|
| `pending` | Yes | None |
| `active` (no features executing) | Yes | None |
| `active` (features executing) | Yes, with warning | Features may use outdated intake |
| `paused` | Yes | Reason for pausing may include intake updates |
| `completed` | No (locked) | — |
| `cancelled` | No (locked) | — |

## Error Handling

| Failure | Status Change | Recovery |
|---------|---------------|----------|
| `/release start` fails mid-research | Stays `pending` | Retry `/release start` |
| Feature auto-creation fails | Stays `pending` | Retry or manually create features. On partial failure: features already created remain intact, user prompted to retry remaining or manually complete. Status updated to `active` only after ALL steps complete. |
| All features blocked | Stays `active` | User intervention required |
| Intake capture fails during active release | No change | Retry capture, features use previous intake |
| State corruption | Mark `failed` | `/release recover <id>` rebuilds from files |

### Recovery Command

```
/release recover <id>
```

Rebuilds release state from:
1. Release directory structure
2. Feature YAML files
3. Intake manifest
4. Git history (for completion status)

## Release Templates

> **Note:** Template settings (`pipeline`, `profile`) are resolved from config at runtime and are not stored in `release.yaml`.

### Standard Release (default)

Full pipeline: research → features → execute → verify

```yaml
template: standard
pipeline: feature-full
profile: balanced
auto_create_features: true
```

### Hotfix Release

Minimal pipeline for urgent fixes:

```yaml
template: hotfix
pipeline: feature-quick
profile: budget
auto_create_features: false    # User defines single feature
max_features: 1
skip_output: true
```

### Refactor Release

Research-heavy with strict verification:

```yaml
template: refactor
pipeline: feature-full
profile: quality
auto_create_features: true
require_tests: true
verification_mode: strict
```
