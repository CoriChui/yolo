# YOLO Specification

## Core Concepts

```
Codebase (truth)  +  Intake (auxiliary)  →  Release  →  Features  →  Output
```

- **Codebase**: Actual code — primary source of truth
- **Intake**: Optional external materials (Figma, GDocs, DB schemas, etc.) — release-scoped, stored as `.md` digests
- **Release**: Container for a body of work — explores codebase, auto-creates features from research
- **Feature**: Atomic work unit — goes through research → plan → execute → verify pipeline
- **Output**: Documentation of what was built (visibility only)

## File Structure

```
.planning/
├── config.yaml                           # Settings
├── state.yaml                            # Project state
├── decisions/                            # Design decisions from /decide
│   └── {slug}.md
└── releases/
    └── {YYYY-MM-DD-slug}/                # Release directory
        ├── release.yaml                  # Goal, status, feature list
        ├── requirements.md               # What we're building
        ├── research.md                   # Release-level codebase research
        ├── intake/                       # Release-scoped intake
        │   └── {slug}-v{N}/
        │       ├── manifest.yaml
        │       ├── summary.yaml          # Content hints, entities, priority domains
        │       ├── conflicts.yaml        # Cross-source conflict resolution (if multiple sources)
        │       └── {source}/             # .md digest files per source
        │           └── requirements.yaml # Extracted requirements (REQ-001, ...)
        ├── features/                     # Release-scoped features
        │   └── {NN-slug}/
        │       ├── feature.yaml
        │       ├── plan.md               # Created during /feature plan
        │       ├── verification.md       # Created during /feature verify
        │       └── summary.md            # Created during /feature complete

.claude/
├── commands/yolo/                            # Slash command entry points
│   ├── init.md
│   ├── release.md
│   ├── feature.md
│   ├── intake.md
│   ├── status.md
│   ├── decide.md
│   └── help.md
└── yolo/
    ├── spec.md                               # This file
    ├── agents/                               # Agent prompts (1 file per role)
    │   ├── research.md
    │   ├── plan.md
    │   ├── execute.md
    │   ├── verify.md
    │   ├── feature-breakdown.md
    │   └── decide.md
    └── workflows/                            # Workflow definitions
        ├── init.md
        ├── release.md
        ├── feature.md
        ├── intake.md
        └── status.md
# Note: /yolo:decide and /yolo:help are lightweight commands with no workflow file — implemented directly in command files.
```

## Release Lifecycle

```
pending  →  active  →  completed
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `pending` | Created, intake open | `/yolo:release new <slug>` |
| `active` | Research done, features created, work in progress | `/yolo:release start` |
| `completed` | All features handled, intake locked | `/yolo:release end` |

### Release Flow

1. **`/yolo:release new <slug>`** — create release directory, initial intake, set as focused
2. *(optional)* `/yolo:intake capture <source>` — capture external materials
3. **`/yolo:release start`** — spawn research agent → spawn feature-breakdown agent → create features → set active
4. Work on features (`/yolo:feature start`, etc.)
5. **`/yolo:release end`** — complete or remove incomplete features, lock intake

### release.yaml

```yaml
id: "2026-02-04-mvp"              # YYYY-MM-DD-slug
slug: "mvp"
title: "MVP — Basic Rental System"      # Empty at creation (/release new), populated during /release start goal approval
created_at: 2026-02-04T15:00:00Z
updated_at: 2026-02-04T15:00:00Z

goal: |
  Working moped rental management system.

success_criteria:
  - "Operator can create a rental contract"

intake:
  current: "mvp-v1"
  locked: false

features:
  total: 4
  completed: 2
  list:
    - id: "01"
      name: foundation
      status: completed
    - id: "02"
      name: auth
      status: in_progress

status: active                    # pending | active | completed
started_at: 2026-02-04T15:00:00Z
completed_at: null
```

## Feature Lifecycle

```
pending → researching → planning* → in_progress ↔ verifying → completed
                ↑             |
                └─────────────┘ (plan rejected → pending)

* planning is skipped when resuming with an existing plan.md.
* plan rejection resets status to pending; verify blocker failure resets to in_progress.
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `pending` | In roadmap, not started | Release creation |
| `researching` | Research agent exploring codebase | `/yolo:feature start` |
| `planning` | Plan agent creating tasks | Research completes |
| `in_progress` | Execute agent working on tasks | Plan approved |
| `verifying` | Verify agent checking criteria | All tasks done |
| `completed` | All criteria met | Verification passed |

### Feature Pipeline

```
/yolo:feature start <id> [--prompt "<text>"]
    ↓
Phase 1: Setup — create git worktree (branch: feature/{id}), set status: researching
    ↓
Phase 2: Plan — research agent (opus) → plan agent (opus) → tasks[]
    ↓
Phase 3: Execute — TeamCreate with up to 4 execute agents (sonnet) as parallel teammates
    ↓
Phase 4: Verify-fix loop (max 3 iterations):
  run type/lint/test checks → if fail, spawn execute agent to fix
    ↓
Phase 5: Verify — verify agent (haiku) → passed, results[], issues[]
    ↓
Phase 6: Complete — merge worktree, summary.md
```

### Git Strategy

- **Worktrees:** Each feature gets its own git worktree at `../.${REPO_NAME}-worktrees/${feature_id}`
- **Branches:** `feature/{feature_id}` (e.g., `feature/02-auth`)
- **Merge:** `--no-ff` merge back to main branch on completion
- **Cleanup:** Worktree removed and branch deleted after successful merge; preserved on failure for manual fix

### feature.yaml

```yaml
id: "02"
name: auth
title: "Authentication and Authorization"
release: "2026-02-04-mvp"
depends_on: ["01-foundation"]

goal: |
  Implement authentication via Supabase Auth.

success_criteria:
  - "User can login via email/password"
  - "Session persists between reloads"

estimated_tasks: 5
services_touched: ["services/backend"]
scope:
  directories: ["services/backend/src/modules/auth/"]
  patterns: ["**/*.auth.*"]       # Optional glob patterns for file matching

domain_entities: []               # Mapped from research agent's `domain_model` output by feature-breakdown agent during /release start
business_rules: []                # Populated by feature-breakdown agent during /release start

status: in_progress               # See lifecycle above
created_at: 2026-02-05T10:00:00Z
started_at: 2026-02-05T14:00:00Z
completed_at: null
updated_at: 2026-02-05T14:00:00Z

tasks:
  total: 5
  completed: 3
  current: "Implement password reset"
```

### Dependency Enforcement

- Feature CANNOT start if any `depends_on` feature is not `completed`
- Dependency eligibility is checked at pipeline start (Phase 1 preconditions) — no separate unblock mechanism

## Intake

Intake is **optional auxiliary context** — release-scoped, stored as `.md` digest files only.

### Sources (26)

- **MCP**: figma, notion, linear, jira, confluence, slack, notebooklm
- **WebFetch**: gdocs, swagger, graphql, website
- **CLI**: github, db
- **Local**: openapi, postman, protobuf, graphql-schema, pdf, csv, sql, har, docker, terraform, envfile
- **Interactive**: manual, notes

### Digest Format

All intake files are raw content wrapped in fenced code blocks:
````markdown
# src/models/user.ts

```ts
{raw file content}
```
````

### manifest.yaml

```yaml
version: "mvp-v1"
type: major                       # major | patch
created_at: 2026-02-03T15:00:00Z
release: "2026-02-04-mvp"

sources:
  - name: figma
    captured_at: 2026-02-03T15:00:00Z
    files: 42
    source_category: mcp

stats:
  total_files: 50
  sources: 3
```

### summary.yaml

```yaml
entities:
  - name: "User"
    domain: "auth"
    mentions: 12
  - name: "Contract"
    domain: "billing"
    mentions: 8

priority_domains:
  - "auth"
  - "billing"

content_hints:
  - "Multiple references to dual-currency amounts (UZS + USD)"
  - "Recurring theme: lease-to-own contract lifecycle"
```

### requirements.yaml

```yaml
requirements:
  - id: REQ-001
    text: "Operator can create a rental contract"
    type: functional              # functional | business_rule | constraint | adjustment | decision
                                  # functional: user-facing feature requirement
                                  # business_rule: enforcement rule or invariant
                                  # constraint: technical or operational limitation
                                  # adjustment: scope or priority change from stakeholders
                                  # decision: architectural or design choice
    domain: "contracts"
    confidence: 0.9               # 0.0–1.0
    source_ref: "sheet-kontrol-platezhey, row 12"
  - id: REQ-002
    text: "All amounts stored as dual currency (UZS + USD)"
    type: business_rule
    domain: "billing"
    confidence: 1.0
    source_ref: "research-business-rules, section 3"
```

### Limits

| Constraint | Limit |
|------------|-------|
| Max files per version | 200 |
| Max total size | 100 MB |
| Max versions per release | 10 |

## State Management

`state.yaml` is the single point of project state. Read first in every workflow.

```yaml
updated_at: 2026-02-10T14:30:00Z

focus:
  release: "2026-02-04-mvp"
  feature: "03-billing"

releases:
  - id: "2026-02-04-mvp"
    slug: "mvp"
    status: active
    intake:
      current: "mvp-v1"
      locked: false
    progress:
      features_total: 4
      features_completed: 2
      percentage: 50

session:
  last_action: "Completed task: Set up billing service"  # Updated by workflows after each operation
  resume: |                                               # Updated by /intake capture and /feature start workflows
    Working on Feature 03: Billing.
    Next task: implement payment acceptance.
```

### Agent Access Rules

Agents are **stateless** — they MUST NOT read or write `state.yaml`, `feature.yaml`, `plan.md`, or any `.planning/` files directly. Workflows pass relevant state as agent input and update state after agents return. This is enforced by convention via agent prompts (agents declare "No state access" constraints), not by technical file-access restrictions.

### Research Output Fields

Research agent produces these fields consumed by downstream agents and workflows:

- **`integration_map`**: Service/module integration points discovered during codebase exploration. Maps connections between services, shared dependencies, and API boundaries. Passed through to feature-breakdown and plan agents.
- **`open_questions`**: Questions discovered during research that may block planning. Each question has a `blocking: true|false` flag. Blocking questions are presented to the user for resolution before feature breakdown proceeds. After resolution, passed to feature-breakdown agent as `resolved_questions`.

### plan.md Schema

Each task in plan.md uses a `### Task N:` markdown section with YAML fields:

```yaml
id: setup-auth-middleware        # kebab-case descriptive ID
title: "Set up auth middleware"
description: |
  What this task accomplishes.
files:
  - "src/middleware/auth.ts"
depends_on: []                   # Task IDs this task requires
verification: "Auth middleware responds to requests"
constraints:
  - "Must use existing JWT library"
integration: "Connects to user service"   # optional — single integration point from integration_map
```

## Agents

| Agent | Model | Tools | Purpose |
|-------|-------|-------|---------|
| research | opus | Read, Glob, Grep, WebSearch, WebFetch (read-only) | Explore codebase, analyze intake, gather context |
| plan | opus | Read, Glob, Grep (read-only) | Break goal into executable tasks with dependencies |
| execute | sonnet | Read, Write, Edit, Glob, Grep, Bash | Implement a single task (the only agent that writes code) |
| verify | haiku | Read, Glob, Grep, Bash (read-only) | Verify work meets success criteria |
| feature-breakdown | opus | Read, Glob, Grep (read-only) | Break release goal into ordered features |
| decide | opus | Read, Glob, Grep (read-only) | Design decisions via multi-perspective debate |

Agent files: `.claude/yolo/agents/{name}.md`

## Commands

### Release Commands

| Command | Description |
|---------|-------------|
| `/yolo:release new <slug>` | Create pending release + intake |
| `/yolo:release start [id] [--prompt "<text>"]` | Research + auto-create features → active |
| `/yolo:release end [id]` | Complete or remove incomplete features, lock intake |
| `/yolo:release status [id]` | Show release progress |
| `/yolo:release run [id] [--from <feature-id>]` | Run all features sequentially |

### Feature Commands

| Command | Description |
|---------|-------------|
| `/yolo:feature start <id> [--prompt "<text>"]` | Full pipeline: research → plan → execute → verify-fix → verify → complete |
| `/yolo:feature plan [--amend]` | Create or amend plan.md with tasks |
| `/yolo:feature verify` | Check success criteria |
| `/yolo:feature complete` | Finalize feature, create summary |
| `/yolo:feature status` | Show feature progress |

### Intake Commands

| Command | Description |
|---------|-------------|
| `/yolo:intake capture <source> [url] [--raw] [--release <id>] [--prompt "<text>"]` | Capture from source as .md digest (`--raw`: copy as-is) |
| `/yolo:intake add <path> [--as <name>] [--release <id>] [--prompt "<text>"]` | Add local files as .md digests |
| `/yolo:intake list` | List intake versions |
| `/yolo:intake status` | Show current version and stats |

### General Commands

| Command | Description |
|---------|-------------|
| `/yolo:init` | Initialize YOLO in current project (creates `.planning/` with `state.yaml`, `config.yaml`, `decisions/`, `releases/`) |
| `/yolo:status` | Overall project status |
| `/yolo:decide` | Design decision via multi-perspective debate |
| `/yolo:help` | Show available commands |

## Configuration

`.planning/config.yaml`:

```yaml
project:
  name: "my-project"
  type: "node"

agents:
  research: opus
  plan: opus
  execute: sonnet
  verify: haiku
  feature-breakdown: opus
  decide: opus

limits:
  max_tasks_per_feature: 5
  max_features_per_release: 12
  estimated_tasks_range: [2, 8]
intake:
  max_files: 200
```

## Conventions

- **Release IDs**: `YYYY-MM-DD-slug` (e.g., `2026-02-04-mvp`)
- **Feature IDs (release)**: `NN-slug` (e.g., `02-auth`)
- **Intake versions**: `{slug}-v{N}` for major (e.g., `mvp-v1`), `{slug}-v{N}.{patch}` for patch (e.g., `mvp-v1.1`)
- **Task IDs (in plan)**: descriptive kebab-case (e.g., `setup-auth-middleware`)
- **Slugs**: lowercase alphanumeric + hyphens
- **Timestamps**: ISO 8601 UTC
