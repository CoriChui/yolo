# YOLO — You Only Live Once

## Overview

YOLO is a development workflow where releases explore the codebase, use auxiliary inputs, and produce documented outputs. Multiple releases can run in parallel, each independent of the others.

## Key Concept

```
Codebase + Docs + Intake (auxiliary)  →  Release  →  Features  →  Output Specs
                                                  ↘
                                              Standalone Features
```

- **Codebase**: Actual code, types, components — primary source of truth
- **Intake**: Auxiliary materials from 26+ sources (Figma, GDocs, DB, Swagger, etc.) — scoped to each release, stored as .md digests only
- **Release**: Explores reality, defines work, executes features (multiple can run in parallel)
- **Features**: Can belong to a release OR exist standalone
- **Output Specs**: Documentation of what was built — for visibility

## Core Principles

1. **Codebase is truth** — always explore actual code
2. **Intake is auxiliary** — optional context, scoped to release
3. **Releases are independent** — no dependencies between releases, can run in parallel
4. **Features are flexible** — can belong to release or be standalone
5. **Output specs are documentation** — what was built, for visibility
6. **User always approves** — Claude proposes, human decides

## System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                     REALITY (source of truth)                   │
│  Codebase: src/, supabase/, actual types and components         │
│  Docs: existing documentation                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓ explored by
┌─────────────────────────────────────────────────────────────────┐
│                      RELEASE LAYER (parallel)                   │
│  Multiple independent releases can run simultaneously           │
│  releases/2026-02-04-mvp/                                       │
│  releases/2026-02-10-mobile/                                    │
│                                                                 │
│  Each release has:                                              │
│    - Own intake/ directory (scoped auxiliary materials)         │
│    - Own features/ directory (release-specific features)        │
│    - Own requirements and output specs                          │
└─────────────────────────────────────────────────────────────────┘
                    ↓ executes                    ↓ can pull from
┌─────────────────────────────────────────────────────────────────┐
│                       FEATURE LAYER                             │
│                                                                 │
│  Release Features (nested):                                     │
│    releases/2026-02-04-mvp/features/01-auth/                    │
│                                                                 │
│  Standalone Features (independent):                             │
│    features/dark-mode/                                          │
│    features/export-csv/                                         │
│                                                                 │
│  Features can attach/detach from releases                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓ produces
┌─────────────────────────────────────────────────────────────────┐
│                    OUTPUT SPECS (visibility)                    │
│  Documentation of what was built                                │
│  releases/2026-02-04-mvp/output/                                │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                        STATE LAYER                              │
│  Tracks all active releases + current focus                     │
│  .planning/state.yaml (schema v2)                               │
│  Key sections: focus, releases[], standalone_features,          │
│                feature, session                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Release Flow

```
/release new mvp
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Create release (PENDING)                                    │
│     - Generate ID: 2026-02-04-mvp                               │
│     - Create releases/2026-02-04-mvp/                           │
│     - Create release.yaml                                       │
│     - Create intake directory (mvp-v1)                          │
│     - Intake is OPEN for capture                                │
└─────────────────────────────────────────────────────────────────┘
           │
           │ /intake capture figma, /intake capture gdocs, /intake add ./project
           │
           ▼
/release start [id]
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Explore codebase                                            │
│     - Spawns research agent (profile-based)                     │
│     - Read actual types, components, API                        │
│     - Understand current state                                  │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. Read intake (if relevant)                                   │
│     - Figma designs for UI work                                 │
│     - GDocs/Sheets for requirements                             │
│     - DB schema, Swagger specs, etc.                            │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. Define goal and auto-create features                        │
│     - Spawns plan agent (profile-based)                         │
│     - Based on actual codebase state                            │
│     - Features created automatically from research              │
│     - User approves                                             │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  5. Execute features                                            │
│     - Each feature explores codebase as needed                  │
│     - Build functionality                                       │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  5a. Verify features                                            │
│     - Spawns verify agent (profile-based)                       │
│     - Check each feature against verification criteria          │
│     - On failure: classify → fix / retry / escalate             │
└─────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  6. Complete release                                            │
│     - Ask user about each incomplete feature                    │
│     - Generate output specs                                     │
│     - Archive release                                           │
└─────────────────────────────────────────────────────────────────┘
```

## Identification

### Release IDs

Format: `YYYY-MM-DD-slug`

Examples:
- `2026-02-04-mvp`
- `2026-02-10-mobile-app`
- `2026-03-15-billing-integration`

The date is when the release was created. The slug is user-provided.

### Intake Versions

Intake versions are scoped to their release and use the release slug as prefix:

| Version | Type | Example |
|---------|------|---------|
| `{slug}-v1` | major | `mvp-v1` (initial capture) |
| `{slug}-v1.1` | patch | `mvp-v1.1` (additional material) |
| `{slug}-v2` | major | `mvp-v2` (major re-capture) |

Each version is a **full snapshot**. No deltas.

### Feature IDs

Release features are numbered sequentially within the release:
- `releases/2026-02-04-mvp/features/01-auth/`
- `releases/2026-02-04-mvp/features/02-billing/`

Standalone features use slug only:
- `features/dark-mode/`
- `features/export-csv/`

## File Structure

> **Note:** `.planning/` is runtime data (state, releases, features, intake). `.claude/yolo/` is the system definition (specs, workflows, agent contracts, orchestration). See [HYBRID-AGENT-ARCHITECTURE.md](../HYBRID-AGENT-ARCHITECTURE.md) for the full `.claude/yolo/` system structure.

> **Note:** The `intake/` directory shown below is release-scoped on disk at `.planning/releases/<release>/intake/<version>/`. References to `.planning/intake/` in `index.yaml` are a legacy path and should not be used.

```
.planning/
├── state.yaml                         # All releases + focused context
├── config.yaml                        # Settings
│
├── releases/
│   ├── 2026-02-04-mvp/                # Release directory
│   │   ├── release.yaml               # Goal, status, feature list
│   │   ├── requirements.md            # What we're building
│   │   │
│   │   ├── intake/                    # Release-scoped intake (.md digests only)
│   │   │   ├── mvp-v1/
│   │   │   │   ├── manifest.yaml
│   │   │   │   ├── figma/            # .md digest files per source
│   │   │   │   └── gdocs/
│   │   │   └── mvp-v1.1/
│   │   │
│   │   ├── features/                  # Release-scoped features
│   │   │   ├── 01-auth/
│   │   │   │   ├── feature.yaml
│   │   │   │   ├── research/
│   │   │   │   ├── plan.md
│   │   │   │   └── summary.md
│   │   │   └── 02-billing/
│   │   │
│   │   └── output/                    # Generated after completion
│   │       ├── schema.md
│   │       ├── api.md
│   │       └── architecture.md
│   │
│   └── 2026-02-10-mobile/             # Another parallel release
│       ├── release.yaml
│       ├── intake/
│       ├── features/
│       └── output/
│
├── features/                          # Standalone features (no release)
│   ├── dark-mode/
│   │   ├── feature.yaml
│   │   ├── plan.md
│   │   └── summary.md
│   └── export-csv/
│
├── do/                                # Ad-hoc tasks
├── debug/                             # Debug sessions
└── archive/                           # Completed releases
```

## Parallel Releases

Multiple releases can be active simultaneously:

```
Timeline:  ────────────────────────────────────────────────>

2026-02-04-mvp:      [========= active =========][completed]
2026-02-10-mobile:         [======== active ========]
2026-02-20-billing:              [===== active =====]
```

- Releases are **completely independent**
- No dependencies or ordering constraints
- Each has its own intake, features, and output
- State tracks all active + one "focused" release

## Feature Flexibility

Features can:
- **Belong to a release**: Created during `/release start`, nested in release directory
- **Be standalone**: Created via `/feature start` without a release
- **Attach to a release**: Standalone feature joins a release
- **Detach from a release**: Release feature becomes standalone

```
/feature attach dark-mode 2026-02-04-mvp    # Standalone → Release
/feature detach 01-auth 2026-02-04-mvp      # Release → Standalone
```

> **Note:** Attach and detach operations involve both physical file movement (between `.planning/features/` and `.planning/releases/<release>/features/`) and corresponding updates to `.planning/state.yaml`.

## Related Specifications

- [01-intake.md](./01-intake.md) — Intake Layer (release-scoped auxiliary materials)
- [02-releases.md](./02-releases.md) — Release Layer (parallel releases)
- [03-features.md](./03-features.md) — Feature Layer (release + standalone)
- [04-state.md](./04-state.md) — State Management (hybrid tracking)
- [05-commands.md](./05-commands.md) — Commands
- [06-schemas.md](./06-schemas.md) — YAML Schemas
- [07-statuses.md](./07-statuses.md) — Status Definitions
- [HYBRID-AGENT-ARCHITECTURE.md](../HYBRID-AGENT-ARCHITECTURE.md) — Agent Architecture & Orchestration
- [WORKFLOW-MIGRATION-PLAN.md](../WORKFLOW-MIGRATION-PLAN.md) — Workflow Migration Plan

## Agent Orchestration

The YOLO system uses a multi-agent architecture where workflows coordinate stateless agents:

- **Workflows** (this spec) coordinate and manage state via `.planning/state.yaml`
- **Agents** are spawned by workflows via the Task tool to do actual work
- Agents are **stateless** — they receive all context as input and return structured output
- Agent spawning goes through the central orchestrator (`orchestration/agent-orchestrator.md`)

### Agent Types

| Agent | Contract | Purpose |
|-------|----------|---------|
| research-* | research | Explore codebase, analyze intake, gather context |
| plan-* | plan | Break goals into executable tasks |
| execute-* | execute | Implement a single task |
| verify-* | verify | Verify work meets criteria |
| decide-* | decide | Make design decisions via multi-perspective debate |

### Agent Variants (Profiles)

| Profile | Research | Plan | Execute | Verify | Decide |
|---------|----------|------|---------|--------|--------|
| quality | thorough (opus) | detailed (opus) | standard (sonnet) | strict (sonnet) | conversation (opus) |
| balanced | thorough (opus) | detailed (opus) | standard (sonnet) | basic (haiku) | conversation (opus) |
| budget | quick (haiku) | minimal (sonnet) | standard (sonnet) | basic (haiku) | skip |
| guided | interactive (opus) | detailed (opus) | standard (sonnet) | strict (sonnet) | conversation (opus) |

> **Note:** Model names in parentheses (opus, sonnet, haiku) are informational only. The actual model used is determined by the implementation variant and Task tool capabilities, not by the profile directly.

See `HYBRID-AGENT-ARCHITECTURE.md` for full details.

## Task Layer (within Features)

Features decompose into **tasks** via the plan agent contract:

- Tasks are **atomic units of work** (touch 1-3 files max)
- Tasks have **dependencies** and an **execution order**
- Each task is executed by a single `execute-*` agent
- Tasks include **verification criteria** checked by `verify-*` agent

### Task Lifecycle

```
Feature Goal
    ↓ (research agent)
Research Findings
    ↓ (plan agent)
Task List [task-1, task-2, task-3]
    ↓ (execute agent, per task)
Code Changes
    ↓ (verify agent)
Verification Result
```

### Task Schema (from plan contract output)

```yaml
tasks:
  - id: "task-1"
    title: "Create user model"
    description: "..."
    files: ["src/models/user.ts", "src/types.ts"]
    depends_on: []
    verification: "User model exports correct interface"
    intake_ref: "requirement from intake"
```

## Error Handling

| Failure | Recovery | Trigger |
|---------|----------|---------|
| Research agent fails | Retry with narrower scope, or ask user | `on-execution-failed` |
| Plan agent fails | Retry, or user provides manual plan | `on-execution-failed` |
| Execute agent fails | Classify error → fix agent or retry | `on-execution-failed` |
| Verification fails | Classify → fixable (fix agent) / blocked (pause) / design (decide agent) | `on-verification-failed` |
| Context pressure | Checkpoint progress, spawn fresh agent | `on-context-pressure` |
| Release blocked | Pause, notify user, ask for guidance | Manual |

See `orchestration/triggers/` for trigger definitions.

## Cross-References

| Concept | Detailed Spec | Agent Contract | Workflow |
|---------|---------------|----------------|----------|
| Intake materials (26+ sources) | `01-intake.md` | research.yaml (intake input) | `intake-capture.md`, `intake-add.md` |
| Release lifecycle | `02-releases.md` | — | `release-new.md`, `release-start.md` |
| Feature execution | `03-features.md` | plan.yaml, execute.yaml | `feature-start.md`, `feature-execute.md` |
| State tracking | `04-state.md` | — (workflows only) | All workflows |
| Commands | `05-commands.md` | — | Routed via `index.yaml` |
| Schemas | `06-schemas.md` | Contract schemas | — |
| Statuses | `07-statuses.md` | — | State transitions |
| Feature planning | `03-features.md` | plan.yaml | `feature-plan.md` |
| Feature verification | `03-features.md` | verify.yaml | `feature-verify.md` |
| Feature attach | `03-features.md` | — | `feature-attach.md` |
| Feature detach | `03-features.md` | — | `feature-detach.md` |
| Agent orchestration | `HYBRID-AGENT-ARCHITECTURE.md` | All contracts | `agent-orchestrator.md` |
