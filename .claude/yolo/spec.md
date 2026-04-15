# YOLO Specification

> **DEPRECATED (v1):** This is the v1 specification. YOLO v2 is defined in
> `docs/specs/2026-04-10-yolo-v2-design.md` and implemented in `.claude/yolo/v2/`.
> This file is kept for reference only — do not use it for new development.

## Core Concepts

```
Codebase (truth)  +  Intake (auxiliary)  →  Release  →  Features  →  Output
```

- **Codebase**: Actual code — primary source of truth
- **Intake**: Optional external materials (Figma, GDocs, DB schemas, etc.) — release-scoped, stored as `.md` digests
- **Release**: Container for a body of work — explores codebase, auto-creates features from research
- **Feature**: Atomic work unit — goes through research → plan → execute → review → verify pipeline
- **Output**: Documentation of what was built (visibility only)

## File Structure

```
.planning/
├── config.yaml                           # Settings
├── state.yaml                            # Project state
├── decisions/                            # Design decisions from /decide
│   └── {slug}.md
├── debug-sessions/                       # Debug sessions from /debug (independent of releases)
│   └── {YYYY-MM-DD-slug}/                # Session directory
│       ├── session.yaml                  # Session metadata (status, phase, hypothesis, fix_commit — schema below)
│       ├── reproducer.md                 # Reproduction steps (Phase 1)
│       ├── investigation.md              # Evidence chain (Phase 2)
│       ├── hypothesis.md                 # Hypothesis + failing test plan (Phase 3)
│       └── fix.md                        # Fix description + verification evidence (Phase 4/5)
└── releases/
    └── {YYYY-MM-DD-slug}/                # Release directory
        ├── release.yaml                  # Goal, status, feature list
        ├── requirements.md               # What we're building (optional, human-readable summary)
        ├── research.md                   # Release-level codebase research
        ├── research-output.yaml          # Structured research output for crash recovery (created during /release start step 5; optional)
        ├── intake/                       # Release-scoped intake
        │   └── {slug}-v{N}/
        │       ├── manifest.yaml
        │       ├── summary.yaml          # Content hints, entities, priority domains (optional, human-readable)
        │       ├── conflicts.yaml        # Cross-source conflict resolution (if multiple sources; see schema below)
        │       └── {source}/             # .md digest files per source
        │           └── requirements.yaml # Extracted requirements (REQ-001, ...)
        ├── features/                     # Release-scoped features
        │   └── {NN-slug}/
        │       ├── feature.yaml
        │       ├── research.md           # Created during /feature plan (feature-level research, when release research.md doesn't cover the feature)
        │       ├── research-output.yaml  # Created during /feature plan (structured research output for crash recovery; optional)
        │       ├── plan.md               # Created during /feature plan
        │       ├── verification.md       # Created during /feature verify
        │       └── summary.md            # Created during /feature complete

.claude/
├── settings.json                                # Tool permissions (allow/deny lists)
├── commands/yolo/                            # Slash command entry points
│   ├── init.md
│   ├── release.md
│   ├── feature.md
│   ├── intake.md
│   ├── status.md
│   ├── decide.md
│   ├── debug.md
│   └── help.md
└── yolo/
    ├── spec.md                               # This file
    ├── agents/                               # Agent prompts (1 file per role)
    │   ├── research.md
    │   ├── plan.md
    │   ├── execute.md
    │   ├── verify.md
    │   ├── feature-breakdown.md
    │   ├── decide.md
    │   └── debug.md
    └── workflows/                            # Workflow definitions
        ├── init.md
        ├── release.md
        ├── feature.md
        ├── intake.md
        ├── status.md
        └── debug.md
# Note: /yolo:help is a lightweight command with no workflow file. /yolo:decide also has no workflow file — its multi-step process (agent spawn, state.yaml updates) is defined directly in the command file. /yolo:debug is a standard command-with-workflow-and-agent triple; debug sessions are independent of releases and persisted under `.planning/debug-sessions/{id}/`.
# Ephemeral runtime artifacts (not tracked in git): .task-locks/ (in worktrees, for crash-safe task assignment), .capture-in-progress (advisory lock for intake captures)
```

## Release Lifecycle

```
pending  →  active  →  completed
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `pending` | Created, intake open | `/yolo:release new <slug>` |
| `active` | Research done, features created, work in progress | `/yolo:release start` |
| `completed` | All features handled, intake locked (terminal — no `/release reopen`; manual recovery: set `release.yaml` `status: active`, `completed_at: null` and update matching `releases[]` entry in `state.yaml`, then run `/yolo:status` to verify) | `/yolo:release end` |

### Release Flow

1. **`/yolo:release new <slug>`** — create release directory, initial intake, set as focused. Also runs recovery checks: forward scan for untracked release directories (validates `release.yaml` fields and checks for expected subdirectories — `intake/`, `features/`), reverse scan for orphaned state.yaml entries, duplicate ID detection.
2. *(optional)* `/yolo:intake capture <source>` — capture external materials
3. **`/yolo:release start`** — spawn research agent → verify research claims → save research.md + research-output.yaml → define goal (user approval) → resolve blocking open questions → validate max_features (cap at 99 for two-digit IDs) → spawn feature-breakdown agent → validate features (user approval) → TOCTOU guard on release status → create features with post-creation validation → write requirements.md → set active → update state.yaml → git commit
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
    - "01-foundation"
    - "02-auth"

status: active                    # pending | active | completed
started_at: 2026-02-04T15:00:00Z
completed_at: null
```

## Feature Lifecycle

```
pending → researching → planning* → in_progress → verifying → completed
   ↑  \       |    ↑          |          ↓    ↑         ↓    ↑
   ↑   \      |    ↑          |   hook_gate_failed  verify_failed
   ↑    \     |    ↑          |     ↓ (resume)          ↓ (resume)
   ↑     \    |    ↑          |     └→ Phase 4 ←────────┘→ in_progress
   ↑      +---+----+----------+--- plan.md exists: skip to in_progress
   └────────────────────────┘  plan rejected: reset to pending

* planning is skipped when resuming with an existing plan.md (researching → in_progress shortcut). If plan.md exists and status is `planning`, user re-approval is required before advancing. If plan.md exists and status is `pending`, user is warned of the inconsistency and can approve the existing plan (skips directly to in_progress, bypassing researching) or delete and re-plan. This pending → in_progress shortcut can occur when plan.md was manually placed, or when a prior plan rejection cleanup failed to delete plan.md.
* **Stuck `planning` recovery:** If a feature is stuck in `planning` without `plan.md` (plan agent crashed), run `/yolo:feature start <id>` which detects the `planning` status, checks for `plan.md`, and re-runs the plan agent. `/yolo:status` also flags features in `planning` without `plan.md` as likely crashed (see status.md reconciliation step 2).
* pending → planning is reachable via /feature plan override (skips research with user confirmation).
* plan rejection resets status to pending (not researching), resets `research_skipped` to false, `started_at` to null, `previous_failure` to null, `research_retry_count` to 0, `verify_retry_count` to 0, `lint_commands` to `[]`, `test_commands` to `[]`, `tasks.total` and `tasks.completed` to 0, `completed_ids` to `[]`, and `tasks.current` to null. Also deletes `plan.md`, `features/{id}/research.md` (if exists), and cleans up worktree (`git worktree remove`) and branch (`git branch -d`) if they exist.
* hook_gate_failed: pre-commit hooks could not be resolved. Re-run /feature start to resume from Phase 4, or /feature verify --force to bypass hook_gate_failed status guard. Status stays `hook_gate_failed` on resume — Phase 4 handles the transition to `verifying` (on success) or back to `hook_gate_failed` (on failure). This is intentionally asymmetric with `verify_failed` resume (hook_gate_failed keeps status unchanged to let Phase 4 manage transitions; verify_failed sets status to in_progress before re-entering Phase 4). After 2+ repeated hook_gate_failed retries, `/feature start` suggests using `/feature verify --force` to bypass or manual intervention.
* verify_failed: success criteria not met. Re-run /feature start to resume from Phase 4 (fixes need re-validation). Returns to in_progress on resume (previous_failure preserved for diagnostics). Also reachable directly via /feature verify (bypasses Phase 4 hook gate with user confirmation). After 3+ repeated verify failures, `/feature start` suggests manual intervention, using `/feature verify --force` to bypass, or resetting feature to pending and re-planning.
* All resume paths validate worktree existence before proceeding — if worktree is missing, offer to recreate from branch or reset to pending.
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| `pending` | In roadmap, not started | Release creation |
| `researching` | Research agent exploring codebase | `/yolo:feature start` |
| `planning` | Plan agent creating tasks | Research completes (also reachable from `pending` via `/feature plan` override — skips research with user confirmation) |
| `in_progress` | Execute agent working on tasks | Plan approved |
| `verifying` | Verify agent checking criteria | All tasks done |
| `hook_gate_failed` | Pre-commit hooks could not be resolved | Phase 4 failure (also valid entry status for Phase 4 retry via `/feature start`) |
| `verify_failed` | Success criteria not met | Phase 5 failure |
| `completed` | All criteria met | Verification passed |

### Feature Pipeline

```
/yolo:feature start <id> [--force] [--prompt "<text>"]
    ↓
Phase 1: Setup — create git worktree (branch: feature/{id}), store branch_point commit hash, run baseline tests, set status: researching
    ↓
Phase 2: Plan — [optional] research agent (model from config; agent spawn skipped if release research.md or feature-level features/{id}/research.md exists — existing research output is reused as plan agent input, or if `research_skipped` is true; when skipped, research.md content is passed as the plan agent's `context` input and `domain_entities`/`business_rules`/`integration_map` are populated from feature.yaml; feature-level research persisted to features/{id}/research.md; if research returns `open_questions` with `blocking: true`, present each to user for resolution before proceeding; resolved questions passed to plan agent as `resolved_questions` input) → plan agent (model from config) → tasks[]
    ↓
Phase 3: Execute — Validate `config.yaml` `limits.max_teammates` >= 1 (error if missing or <= 0). If remaining_tasks == 0 after crash recovery (all tasks already completed), skip Phase 3 entirely and proceed directly to Phase 3b (review). TeamCreate with execute agents (from config) as parallel teammates (count: min(remaining_tasks, config.yaml `limits.max_teammates`)); each agent receives the full task definition from plan.md (id, title, description, files, constraints, integration, intake_ref) plus domain context from CLAUDE.md files (discovery: walk up from each directory in `scope.directories` to the repository root, collecting all CLAUDE.md files found at each level, deduplicated by path; if `scope.directories` is empty, fall back to repository root `CLAUDE.md` only — this refers to `{repo_root}/CLAUDE.md`) → commit_message per task. After all tasks complete, set `tasks.current: null` in feature.yaml
    ↓
Phase 3b: Review — two-stage review of implementation: (1) spec compliance review checks changes against success_criteria for gaps and scope creep, (2) code quality review checks diff for patterns, bugs, security, and readability. Issues loop back to execute agent for fixes. During /release run, only error-severity issues block.
    ↓
Phase 4: Hook gate — single commit with hooks enabled; if hooks fail, spawn execute agent to fix (agent has implicit turn limit from Task tool — if agent exhausts its turn limit without success, the Task tool returns with a failure result and the workflow proceeds to set `status: hook_gate_failed`). Accepts entry from `in_progress`, `hook_gate_failed`, or `verify_failed` statuses. Feature status remains unchanged during hook gate attempt; transitions to `verifying` on success or `hook_gate_failed` on failure
    ↓
Phase 5: Verify — verify agent (model from config) with criteria, files (determined via `branch_point` for accurate diff), business_rules, lint_commands, test_commands → passed, results[], issues[], rule_results[] (if business_rules provided) (type_check_results is agent-internal, not consumed by workflows — must NOT be persisted to verification.md). Evidence iron law: every pass/fail claim must be backed by fresh command output — no claims without evidence.
    ↓
Phase 6: Complete — present completion options (merge locally, create PR, keep branch, discard); auto-merges during /release run. Creates summary.md.

Note: Model names in the agent table below are config defaults from config.yaml `agents.*`. Workflows use config-driven model selection — always read config.yaml to get the actual model for each agent.
```

### Git Strategy

- **Worktrees:** Each feature gets its own git worktree at `../.${REPO_NAME}-worktrees/${feature_id}` (where `feature_id` is the full `NN-slug` format, e.g., `02-auth`)
- **Branches:** `feature/{feature_id}` (e.g., `feature/02-auth`) — `feature_id` uses the full `NN-slug` format
- **Dual-commit model (Phase 3):** Code changes are committed in the worktree with `--no-verify`; state/feature YAML changes are committed in the main tree as separate metadata commits. Phase 4 hook gate validates the full codebase.
- **Phase 4 hook gate:** Operates in the worktree — the commit attempt (with hooks enabled) is made against the worktree's full codebase, not the main tree.
- **Merge:** `--no-ff --no-verify` merge back to main branch on completion (Phase 4 hook gate already validated the full codebase). Merge commit message: `"merge: feature/{feature_id}"`
- **Task locks:** `.task-locks/` directory in worktree tracks assigned tasks for crash-safe duplicate detection. Lock files are created before task assignment and deleted after completion is recorded in `completed_ids`. On resume, tasks with lock files but no completion record are auto-recovered by running `git diff --name-only` in the worktree and comparing against the task's `files` list from plan.md to detect code changes.
- **Cleanup:** Worktree removed and branch deleted after successful merge or plan rejection; preserved on pipeline failure for manual fix

### feature.yaml

```yaml
id: "02"                              # Numeric ID (two-digit, zero-padded). Used in compound form "NN-slug" (e.g., "02-auth") for depends_on, features.list entries, and directory names.
name: auth
title: "Authentication and Authorization"  # Derived from name (kebab-to-title-case) or first line of goal for /feature add; provided by feature-breakdown agent for /release start
release: "2026-02-04-mvp"
depends_on: ["01-foundation"]

goal: |
  Implement authentication via Supabase Auth.

success_criteria:
  - "User can login via email/password"
  - "Session persists between reloads"

services_touched: ["services/backend"]     # Populated by feature-breakdown agent during /release start, or inferred from scope.directories during /feature add
scope:
  directories: ["services/backend/src/modules/auth/"]
  patterns: []                    # Populated by feature-breakdown agent during /release start; not currently consumed by downstream workflows (reserved for future consumption)

domain_entities: []               # Mapped from research agent's `domain_model` output by feature-breakdown agent during /release start
business_rules: []                # Populated by feature-breakdown agent during /release start. Structured objects with `rule`, `enforcement`, `applies_to` fields (e.g., [{rule: "All amounts dual currency", enforcement: "validation layer", applies_to: "billing"}]).
integration_map: []               # Optional — populated by feature-breakdown agent during /release start from release-level research. Empty for features added via /feature add.
research_skipped: false           # Set to true when /feature plan is used on a pending feature (bypassing research with user confirmation)
lint_commands: []                 # Discovered during Phase 2 planning (e.g., ["eslint --no-fix", "tsc --noEmit"]). Persisted for Phase 5 verify agent. Empty if not discovered.
test_commands: []                 # Discovered during Phase 2 planning (e.g., ["npm test", "pytest"]). Persisted for Phase 5 verify agent. Empty if not discovered.
branch_point: "abc123def"         # Commit hash at worktree creation — used for accurate diffs in Phase 5 and /feature verify (null before worktree creation)
previous_failure: null            # Previous failure status preserved for diagnostics (hook_gate_failed/verify_failed) — set on resume from failure states
baseline_failures: null           # Count of pre-existing test failures from Phase 1 baseline run. Null before Phase 1 runs or when baseline tests all passed. Integer count when user accepted pre-existing failures and chose to proceed. Referenced by Phase 5 verify agent to exclude pre-existing failures from the regression count.

status: in_progress               # See lifecycle above
created_at: 2026-02-05T10:00:00Z
started_at: 2026-02-05T14:00:00Z
completed_at: null
updated_at: 2026-02-05T14:00:00Z
bypass_reason: null                # Optional — set to "force-complete via /release end" when force-completed, or "completed with hook gate bypassed via /feature verify --force" when hook gate was bypassed. Semantics: (1) If set, the feature may have unvalidated code or unmerged changes. (2) Dependent features receive a mandatory merge verification check (`git merge-base --is-ancestor`) — if the bypassed feature's branch is not on main, the dependent cannot start without `--force`. (3) `/release run` logs features with bypass_reason set before running dependents.
run_failure_count: 0               # Tracks retry count during /release run — incremented on each pipeline failure, read on resume via --from, reset to 0 on success or new run without --from
research_retry_count: 0            # Tracks consecutive resumes from `researching` status — incremented on each resume, reset to 0 on successful transition or feature completion
verify_retry_count: 0              # Tracks consecutive verify failures — incremented on each resume from `verify_failed`, reset to 0 on successful verification or feature completion

tasks:
  total: 5
  completed: 3
  completed_ids: ["setup-auth-middleware", "implement-login", "add-session-management"]  # tracks completed task IDs for duplicate detection
  current: "Implement password reset"   # null when no task is active, string when in progress
```

### Dependency Enforcement

- Feature CANNOT start if any `depends_on` feature is not `completed`
- Dependency eligibility is checked at pipeline start (Phase 1 preconditions) — no separate unblock mechanism
- Features in `hook_gate_failed` or `verify_failed` status intentionally block dependent features (they are not `completed`). To unblock: fix and complete the feature, or force-complete via `/release end`
- Features with `bypass_reason` set (force-completed or hook gate bypassed): dependents receive a mandatory merge verification check — the workflow verifies the dependency's branch is an ancestor of main via `git merge-base --is-ancestor`. If not merged, the dependent cannot start without `--force`

## Debug Session Lifecycle

Debug sessions are independent of releases and features. A session enforces: reproducer → root cause → failing test → fix → verification. Sessions persist at `.planning/debug-sessions/{id}/` and survive `/clear`.

```
reproduce → investigate → hypothesize → fix → verify → (resolved | abandoned)
    ↑             ↓                      ↓         ↑
    │             └── (low confidence) ──┘         │
    │                                              │
    └── (test still fails — re-investigate) ───────┘
```

### Session Status vs Phase

Debug uses two orthogonal state dimensions in `session.yaml`:

- **`status`**: coarse-grained lifecycle (`investigating | hypothesizing | fixing | verifying | resolved | abandoned`). `resolved` and `abandoned` are terminal — sessions cannot be reopened.
- **`phase`**: fine-grained workflow step (`reproduce | investigate | hypothesize | fix | verify`). The resume dispatch reads `phase` to re-enter the workflow at the right step.

| Status | Meaning | Trigger |
|--------|---------|---------|
| `investigating` | Reproducer captured, debug agent tracing root cause | `/yolo:debug new` after reproducer confirmed |
| `hypothesizing` | Root cause identified, failing test being written | Phase 2 completes with high/medium confidence |
| `fixing` | Failing test in place, implementing minimal fix | Phase 3 failing test is in place |
| `verifying` | Fix applied, re-running reproducer + suite | Phase 4 green |
| `resolved` | Reproducer no longer reproduces, full suite green | Phase 5 gate passed |
| `abandoned` | Closed without a fix (with documented reason) | `/yolo:debug end --status abandoned` |

### Iron Laws

1. **No fix without a reproducer.** If the reproducer cannot be confirmed, the session stays in `reproducer_status: unknown` and does not advance past Phase 1.
2. **No fix without a failing test.** Phase 3 writes a test that MUST fail for the hypothesized reason before Phase 4 is allowed.
3. **No resolution without fresh evidence.** Phase 5 requires running the reproducer and the full suite in the current response — "tests were green in Phase 4" does not count if Phase 4 was a prior session.
4. **Debug agent is read-only.** It investigates and proposes; it never writes code. Fixes are applied by the orchestrator or a fresh execute agent in Phase 4.

### session.yaml

```yaml
id: "2026-04-08-auth-redirect"     # {YYYY-MM-DD}-{slug}
symptom: "Login redirects loop after OAuth callback"
status: investigating              # investigating | hypothesizing | fixing | verifying | resolved | abandoned
phase: reproduce                   # reproduce | investigate | hypothesize | fix | verify
created_at: 2026-04-08T10:00:00Z
updated_at: 2026-04-08T10:00:00Z
reproducer_status: confirmed       # confirmed | unknown | flaky
scope:
  directories: []                  # populated by Phase 2 debug agent
  related_files: []                # populated by Phase 2 debug agent
current_hypothesis: null           # one-line hypothesis from Phase 2
confidence: null                   # high | medium | low (from Phase 2 output)
root_cause: null                   # one-line root cause from Phase 2
fix_commit: null                   # SHA once fix is committed
fix_branch: null                   # debug worktree branch if used ("debug/{id}")
session:
  last_action: "Debug session created"
  resume: "Run /yolo:debug resume {id} to continue"
```

> **Note:** Debug sessions do not use `state.yaml` for status tracking, but workflows should update `state.yaml` `session.last_action`, `session.resume`, and `updated_at` at each phase transition so `/yolo:status` can surface active debug work for orientation. Debug sessions are otherwise independent — they can run concurrently with `/release run` or an active feature pipeline without touching release/feature state.

## Intake

Intake is **optional auxiliary context** — release-scoped, stored as `.md` digest files only.

### Sources (26)

- **MCP**: figma, notion, linear, jira, confluence, slack, notebooklm
- **WebFetch**: gdocs (includes Google Sheets via gviz CSV export), swagger, graphql, website
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
release: "2026-02-04-mvp"
created_at: 2026-02-03T15:00:00Z
type: major                       # major | patch

sources:
  - name: figma
    captured_at: 2026-02-03T15:00:00Z
    files: 42
    source_category: mcp          # mcp | webfetch | cli | local | interactive

stats:
  total_files: 50
  sources: 3
```

### summary.yaml

```yaml
created_at: 2026-02-03T15:00:00Z
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
    status: active                  # active | superseded
  - id: REQ-002
    text: "All amounts stored as dual currency (UZS + USD)"
    type: business_rule
    domain: "billing"
    confidence: 1.0
    source_ref: "research-business-rules, section 3"
```

### conflicts.yaml

```yaml
conflicts:
  - id: CONF-001
    sources: ["figma-designs", "gdocs-spec"]
    field: "user_role_names"
    description: "Figma uses 'Operator/Admin', GDocs uses 'Manager/SuperAdmin'"
    resolution: "Use Figma naming (Operator/Admin) — closer to domain language"
    resolved_by: "user"
    resolved_at: 2026-02-04T16:00:00Z
```

### Limits

| Constraint | Limit |
|------------|-------|
| Max files per version | 200 |
| Max total size | 100 MB |
| Max versions per release | 10 |

### Concurrency

The intake workflow uses an advisory lock file `.planning/releases/{id}/intake/.capture-in-progress` (containing timestamp and source name) to detect concurrent captures. Created at capture start, checked for staleness (> 30 min = likely crash), and cleaned up after completion.

## State Management

`state.yaml` is the project state index — it provides quick-lookup session and release data. Read first in every workflow and command that accesses `.planning/` state (except init, which creates it). For **mutating** operations, state.yaml is required — error if missing. For **read-only** commands (`/feature status`, `/release status`), fall back to reading authoritative YAML files directly if state.yaml is unavailable. `/status` performs crash-recovery reconciliation (writes corrections to state.yaml) but falls back to read-only mode if state.yaml is missing.

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
    progress:                           # cache — maps from release.yaml: features.total → features_total, features.completed → features_completed
      features_total: 4
      features_completed: 2
      percentage: 50                   # computed: features_total > 0 ? (features_completed / features_total) * 100 : 0 — recomputed by /feature complete, /feature add, /release start, and /release end
    completed_at: null                 # cache — maps from release.yaml: completed_at. Set by /release end when release is completed. Null while active/pending.

session:
  run_active: false                                       # true while /release run is executing; prevents concurrent runs
  run_started_at: null                                    # ISO 8601 timestamp when run_active was set; used for staleness check (>2h = likely crash)
  last_action: "Completed task: Set up billing service"  # Updated by workflows after each operation
  resume: |                                               # Updated by /intake capture and /feature start workflows
    Working on Feature 03: Billing.                       # Free-text context for UX
    Next task: implement payment acceptance.
```

> **Note:** `release.yaml` and `feature.yaml` are the authoritative sources for release/feature status. The `releases[]` entries in `state.yaml` are an index/cache for quick lookup — workflows should read the authoritative YAML files when precise status is needed.

### Agent Access Rules

Agents are **stateless** — they MUST NOT read or write `state.yaml`, `feature.yaml`, `plan.md`, or any `.planning/` files directly. Workflows pass relevant state as agent input and update state after agents return. This is enforced by convention via agent prompts (agents declare "No state access" constraints), not by technical file-access restrictions. Exception: reading `CLAUDE.md` files for domain context is allowed (these are project instructions, not workflow state).

### Research Output Fields

Research agent produces these fields consumed by downstream agents and workflows:

- **`findings`**: Markdown summary of all research findings — architecture, patterns, notable code.
- **`relevant_files`**: List of key file paths discovered during exploration.
- **`patterns`**: Coding conventions and patterns observed in the codebase.
- **`intake_insights`**: Per-source insights from intake materials (if intake provided).
- **`gaps`**: Requirements from intake not yet addressed in codebase.
- **`concerns`**: Inconsistencies, technical debt, or risks discovered.
- **`suggestions`**: Recommended approaches or improvements.
- **`domain_model`**: Domain entities with states, relationships, and home services.
- **`business_rules`**: Business rules with source, enforcement mechanism, and applicability.
- **`integration_map`**: Service/module integration points discovered during codebase exploration. Maps connections between services, shared dependencies, and API boundaries. Passed through to feature-breakdown agent during `/release start`, which propagates relevant integration points to each feature's `integration_map` field. In `/feature plan`, always passed from `feature.yaml` as a structured input to the plan agent. Will be a populated array for features created via `/release start` and an empty array for `/feature add` features or when the research agent did not populate it.
- **`open_questions`**: Questions discovered during research that may block planning. Each question has a `blocking: true|false` flag. Blocking questions are presented to the user for resolution before feature breakdown proceeds. After resolution, passed to feature-breakdown agent as `resolved_questions`. Schema: same structure as `open_questions` with an added `resolution: string` field per question recording the user's answer. Note: `resolution` is added by the orchestrator after user input, not by the research agent.

### Feature-Breakdown Output Fields

Feature-breakdown agent produces these fields consumed by the release workflow:

- **`features[]`**: Array of feature definitions with id, name, title, goal, success_criteria, scope, depends_on, services_touched, domain_entities (optional), business_rules (optional — required as input to the agent in `/release start` flow, may be empty array).
- **`dependency_graph`**: Visualization of feature dependency relationships for validation and user review.
- **`risks`**: Identified risks across the feature set (e.g., shared dependencies, tight coupling).
- **`assumptions`**: Assumptions made during feature breakdown (e.g., about codebase capabilities, existing infrastructure).
- **`coverage`**: Mapping of intake requirements to features that address them — used for gap analysis during user review.

> **Field Mappings (Research → Feature-Breakdown):** These mappings apply only to the `/release start` flow (step 8). See Feature Pipeline summary above for the `/feature plan` context-passing behavior. Mappings: `findings` → `codebase_findings` (rename), `open_questions` → `resolved_questions` (rename, after user resolution). All other fields pass through unchanged. See `/release start` workflow step 8 for the full mapping table.

### plan.md Schema

plan.md stores the plan agent's structured YAML output directly:

```yaml
tasks:
  - id: setup-auth-middleware        # kebab-case descriptive ID
    title: "Set up auth middleware"
    description: |
      What this task accomplishes.
    files:
      - "src/middleware/auth.ts"
    depends_on: []                   # Task IDs this task requires
    verification: "Auth middleware responds to requests"
    constraints:                      # optional — business rules for this task
      - "Must use existing JWT library"
    integration: "Connects to user service"   # optional — single integration point from integration_map
    intake_ref: "requirement"                # optional — traces back to intake requirement

execution_order: ["setup-auth-middleware", "implement-login"]  # advisory — workflows use blockedBy from TaskCreate
risks:
  - "Risk description"
assumptions:
  - "Assumption description"
coverage:                          # informational — not validated by workflows
  - requirement_id: "REQ-001"
    text: "Requirement text"
    covered_by: ["task-id-1"]
```

The plan agent also produces top-level output fields beyond per-task definitions:
- **`execution_order`**: Ordered list of task IDs respecting dependencies (advisory — workflows use `blockedBy` from TaskCreate for ordering)
- **`risks`**: Identified implementation risks
- **`assumptions`**: Assumptions made during planning
- **`coverage`**: Mapping of intake requirements to tasks that address them (informational — not validated by workflows):
  ```yaml
  coverage:
    - requirement_id: "REQ-001"
      text: "Operator can create a rental contract"
      covered_by: ["setup-contract-model", "implement-contract-api"]
    - requirement_id: "REQ-002"
      text: "All amounts stored as dual currency"
      covered_by: []               # empty = gap, flagged in risks
  ```

## Agents

| Agent | Model | Tools | Purpose |
|-------|-------|-------|---------|
| research | opus | Read, Glob, Grep, WebSearch†, WebFetch† | Explore codebase, analyze intake, gather context (read-only agent) |
| plan | opus | Read, Glob, Grep (read-only) | Break goal into executable tasks with dependencies |
| execute | sonnet | Read, Write, Edit, Glob, Grep, Bash (+ SendMessage, TaskUpdate, TaskList, TaskGet via TeamCreate in Phase 3) | Implement a single task (the only agent that writes code) |
| verify | haiku | Read, Glob, Grep, Bash (non-mutating commands only) | Verify work meets success criteria |
| feature-breakdown | opus | Read, Glob, Grep (read-only) | Break release goal into ordered features |
| decide | opus | Read, Glob, Grep (read-only) | Design decisions via multi-perspective debate |
| debug | opus | Read, Glob, Grep, Bash (non-mutating only), WebSearch†, WebFetch† | Trace root cause via evidence chain; propose failing test + fix scope (read-only investigator — never writes code) |

> † WebSearch and WebFetch are deferred tools — the orchestrator must use ToolSearch to load them before spawning the research agent.
>
> Note: Execute agents also receive team coordination tools (SendMessage, TaskUpdate, TaskList, TaskGet) when spawned via TeamCreate in Phase 3.

Agent files: `.claude/yolo/agents/{name}.md`

> **Orchestrator vs Agent Tool Scoping:** The agent table above lists tools available to each agent when spawned as a subagent. The orchestrator (the workflow runner, i.e., the slash command handler) has access to a broader set of tools declared in the command's `allowed-tools` frontmatter. For example, `/yolo:feature` declares TeamCreate, TaskCreate, etc. — these are orchestrator tools used to coordinate agents, not tools available to the agents themselves. Agents see the tools listed in their row above, plus any additional tools provided through the spawning mechanism (e.g., TeamCreate provides team coordination tools to execute agents in Phase 3).

### Team Orchestration Tools

The `/yolo:feature start` workflow (Phase 3) uses team tools to coordinate parallel execution:

| Tool | Purpose |
|------|---------|
| `TeamCreate` | Create an agent team for parallel task execution |
| `TaskCreate` | Create shared task list entries from plan.md tasks |
| `TaskUpdate` | Update task status, assign owners, manage dependencies |
| `TaskList` | Monitor task progress across all teammates |
| `TaskGet` | Read full task details including description and blockers |
| `SendMessage` | Communicate with teammates (assign work, handle failures, shutdown) |
| `TeamDelete` | Remove team and task directories after execution completes |

These tools are declared in the `/yolo:feature` command's `allowed-tools`. TeamCreate and TaskCreate are used only by the orchestrator (lead). Task-level tools (TaskUpdate, TaskList, TaskGet, SendMessage) are also available to spawned execute agents for team coordination.

### Release Run Delegation

The `/yolo:release run` workflow uses the `Skill` tool to invoke `/yolo:feature start` for each feature sequentially. `Skill` is a built-in tool available in all commands — no `ToolSearch` loading is required. `Skill` is declared in the `/yolo:release` command's `allowed-tools`.

> **Tool Permission Layering:** Command-level `allowed-tools` (declared in frontmatter) are additive to project-level `settings.json` `permissions.allow`. A tool must be listed in at least one of these to run without user prompts. Team orchestration tools and `TeamDelete` should be in `settings.json` for automated `/release run` flows. `ToolSearch` is used by `/yolo:intake` (MCP tool discovery and WebFetch loading for WebFetch-category sources), `/yolo:feature` (loading deferred tools for research agent spawning), and `/yolo:release` (loading deferred tools for research agent spawning and Skill tool loading for `/release run`). Note: `settings.json` pre-approves all commonly used tools globally for seamless automation — command-level `allowed-tools` declarations serve as documentation of which tools each command or its delegated subcommands may need, not as a restriction mechanism. Read-only agent constraints (research, plan, verify, decide, feature-breakdown) are enforced by convention via agent prompts since Claude Code does not offer a read-only subagent_type.

> **Shortcut Transitions:** Beyond the main lifecycle flow, the following shortcuts exist:
> 1. `researching → in_progress` — when `plan.md` already exists (planning is skipped)
> 2. `pending → in_progress` — when `plan.md` exists and user confirms (bypasses researching, with warning)
> 3. `pending → planning` — via `/feature plan` override (skips research with user confirmation)

## Commands

### Release Commands

| Command | Description |
|---------|-------------|
| `/yolo:release new <slug>` | Create pending release + intake |
| `/yolo:release start [id] [--prompt "<text>"]` | Research + auto-create features → active |
| `/yolo:release end [id]` | Complete or remove incomplete features, lock intake |
| `/yolo:release status [id]` | Show release progress |
| `/yolo:release run [id] [--from <feature-id>]` | Run all features sequentially (delegates each feature to `/yolo:feature start` via Skill tool) |

### Feature Commands

| Command | Description |
|---------|-------------|
| `/yolo:feature start <id> [--force] [--prompt "<text>"]` | Full pipeline: research → plan → execute → review → hook gate → verify → complete (`--force` bypasses missing dependency checks) |
| `/yolo:feature add <name> [--prompt "<goal>"]` | Add new feature to active release |
| `/yolo:feature plan [--amend] [--force] [--prompt "<text>"]` | Create or amend plan.md with tasks (`--force` overrides researching recency check) |
| `/yolo:feature verify [--force]` | Check success criteria (auto-completes on pass; `--force` bypasses `hook_gate_failed` status guard; calling on `in_progress` features skips Phase 4 hook gate; also accepts `verify_failed` status for re-verification) |
| `/yolo:feature complete` | Finalize feature, create summary (override — normally auto-called by verify) |
| `/yolo:feature status` | Show feature progress |

### Intake Commands

| Command | Description |
|---------|-------------|
| `/yolo:intake capture <source> [url] [--raw] [--release <id>] [--prompt "<text>"]` | Capture from source as .md digest (`--raw`: copy as-is) |
| `/yolo:intake add <path> [--as <name>] [--release <id>] [--prompt "<text>"]` | Add local files as .md digests |
| `/yolo:intake list` | List intake versions |
| `/yolo:intake status` | Show current version and stats |

### Debug Commands

Debug sessions are standalone — they do not belong to a release and do not block the feature pipeline. Sessions survive `/clear` via `.planning/debug-sessions/{id}/`. Iron law: no fix without a reproducer and a failing test.

| Command | Description |
|---------|-------------|
| `/yolo:debug new <symptom> [--prompt "<context>"]` | Start a new debug session (enforces reproducer → root cause → failing test → fix → verification) |
| `/yolo:debug resume [id]` | Resume an existing session (auto-picks if only one active) |
| `/yolo:debug list` | List all debug sessions (active + closed) |
| `/yolo:debug end <id> [--status resolved\|abandoned]` | Close a session |

### General Commands

| Command | Description |
|---------|-------------|
| `/yolo:init` | Initialize YOLO in current project (creates `.planning/` with `state.yaml`, `config.yaml`, `decisions/`, `releases/`) |
| `/yolo:status` | Overall project status |
| `/yolo:decide` | Design decision via multi-perspective debate (saves to `.planning/decisions/{slug}.md`; updates `session.last_action`, `session.resume`, `updated_at`) |
| `/yolo:help` | Show available commands |

## Configuration

`.planning/config.yaml`:

```yaml
project:
  name: "my-project"
  type: "auto"              # auto-detected from project config

agents:
  research: opus
  plan: opus
  execute: sonnet
  verify: haiku
  feature-breakdown: opus
  decide: opus
  debug: opus

limits:
  max_tasks_per_feature: 5
  max_features_per_release: 12
  max_teammates: 4

intake:
  max_files: 200
```

## Conventions

- **Release IDs**: `YYYY-MM-DD-slug` (e.g., `2026-02-04-mvp`)
- **Feature IDs (release)**: `NN-slug` (e.g., `02-auth`)
- **Intake versions**: `{slug}-v{N}` for major (e.g., `mvp-v1`), `{slug}-v{N}.{patch}` for patch (e.g., `mvp-v1.1`) — currently only `v1` is created by `/release new`; multi-version intake is future functionality
- **Task IDs (in plan)**: descriptive kebab-case (e.g., `setup-auth-middleware`)
- **Slugs**: lowercase alphanumeric + hyphens
- **Timestamps**: ISO 8601 UTC
