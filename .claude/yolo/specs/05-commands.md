# YOLO Commands

## Overview

All commands start with `/` and can have arguments.

> **Note:** Commands are invoked as `/yolo:<command>` (e.g., `/yolo:feature start`). In this spec, the `/yolo:` prefix is omitted for brevity.

```
/command [subcommand] [arguments] [--flags]
```

Commands operate on the **focused release** by default. Use `--release <id>` to override.

---

## Release Commands

### /release new

Create new pending release.

```bash
/release new <slug>

# Example
/release new mvp

# Flow:
# 1. Generates ID: 2026-02-04-mvp (date + slug)
# 2. Creates releases/2026-02-04-mvp/ structure
# 3. Creates release.yaml with PENDING status
# 4. Creates intake directory with mvp-v1
# 5. Sets as focused release
# 6. Suggests /intake capture or /release start
```

### /release start

Start a pending release (research + auto-create features).

```bash
/release start                    # Start focused release
/release start 2026-02-04-mvp     # Start specific release

# Flow:
# 1. Explores codebase
# 2. Reads intake (if captured)
# 3. Defines goal and success criteria
# 4. Auto-creates features from research
# 5. Creates requirements.md
# 6. Sets release status to ACTIVE
```

### /release status

Show release status.

```bash
/release status                   # All releases overview
/release status 2026-02-04-mvp    # Specific release details

# Output:
# RELEASES
# ────────
# ★ 2026-02-04-mvp (active) [FOCUSED]
#   Progress: ████████░░░░░░░░░░░░ 50% (2/4 features)
#   Intake: mvp-v1.1 (open)
#
# ○ 2026-02-10-mobile (pending)
#   Progress: not started
#   Intake: mobile-v1 (open)
```

### /release focus

Set focused release for other commands.

```bash
/release focus <id>

# Example
/release focus 2026-02-10-mobile

# After this, commands operate on mobile release by default:
# - /release start → starts mobile
# - /intake capture figma → captures to mobile
# - /feature start 01 → creates feature in mobile
```

### /release list

List all releases.

```bash
/release list

# Output:
# RELEASES
# ────────
# ID                     Status    Features  Intake
# 2026-02-04-mvp         active    2/4       mvp-v1.1 (open)
# 2026-02-10-mobile      pending   0/0       mobile-v1 (open)
# 2026-01-15-pilot       completed 5/5       pilot-v2 (locked)
```

### /release end

Complete a release.

```bash
/release end                      # End focused release
/release end 2026-02-04-mvp       # End specific release

# Flow:
# 1. Checks feature status
# 2. For each incomplete feature:
#    - [Complete] Mark as done
#    - [Detach] Move to standalone
#    - [Archive] Keep as-is
# 3. Locks intake (no more captures)
# 4. Generates output specs from codebase:
#    - output/schema.md
#    - output/api.md
#    - output/architecture.md
# 5. Archives release
```

### /release requirements

Show requirements. Reads `requirements.md` directly. No dedicated workflow needed.

```bash
/release requirements                     # Focused release
/release requirements 2026-02-04-mvp      # Specific release

# Output: Contents of requirements.md
```

---

## Feature Commands

### /feature new

Create new standalone feature.

```bash
/feature new <slug>

# Example
/feature new dark-mode

# Flow:
# 1. Creates features/dark-mode/ directory
# 2. Creates feature.yaml with release: null
# 3. Status: pending
```

### /feature start

Start feature (→ planning).

```bash
# Release feature (uses focused release)
/feature start <id>
/feature start 03-billing

# Release feature (specific release)
/feature start <id> --release <release-id>
/feature start 03-billing --release 2026-02-04-mvp

# Standalone feature
/feature start dark-mode

# Flow:
# 1. Sets feature.status = planning
# 2. Sets as current feature in state.yaml
# 3. Suggests /research or /feature plan
```

### /feature plan

Create feature plan.

```bash
/feature plan

# Flow:
# 1. Explores codebase
# 2. Reads research (if exists)
# 3. Creates plan.md with tasks
# 4. Sets feature.status = in_progress
```

### /feature execute

Execute current feature.

```bash
/feature execute

# Interactive mode:
# - Shows current task
# - Executes
# - Marks as done
# - Moves to next
```

### /feature verify

Check success criteria.

```bash
/feature verify

# Flow:
# 1. Reads success_criteria from feature.yaml
# 2. Checks each criterion
# 3. Creates verification.md
# 4. If all OK → suggests /feature complete
```

### /feature complete

Complete feature.

```bash
/feature complete

# Flow:
# 1. Checks all tasks done
# 2. Checks verification passed
# 3. Creates summary.md
# 4. Updates state.yaml
# 5. Commits changes
```

### /feature attach

Attach standalone feature to a release.

```bash
/feature attach <feature> <release>

# Example
/feature attach dark-mode 2026-02-04-mvp

# Flow:
# 1. Move features/dark-mode/ → releases/2026-02-04-mvp/features/04-dark-mode/
# 2. Assign sequential ID (04) within release
# 3. Update feature.yaml: release → "2026-02-04-mvp"
# 4. Update release.yaml: add to features list
# 5. Update state.yaml: standalone_features
# 6. Commit changes
```

### /feature detach

Detach feature from release to standalone.

```bash
/feature detach <feature-id> <release>

# Example
/feature detach 02-auth 2026-02-04-mvp

# Flow:
# 1. Move releases/2026-02-04-mvp/features/02-auth/ → features/auth/
# 2. Update feature.yaml: release → null
# 3. Update release.yaml: remove from features list
# 4. Update state.yaml: standalone_features
# 5. Commit changes
```

### /feature status

Current feature status.

```bash
/feature status

# Output:
# FEATURE: 03-billing (in progress)
# ───────────────────────────────
# Release: 2026-02-04-mvp
# Goal: Implement billing system
#
# Tasks: ████░░░░░░ 33% (2/6)
#   ✅ Set up billing service
#   ✅ Create transaction model
#   🔄 Implement payment acceptance (current)
#   ⏳ Daily charges
#   ⏳ Auto-penalties
#   ⏳ Display balance
```

### /feature list

List features.

```bash
# All features (release + standalone)
/feature list

# Features in specific release
/feature list --release 2026-02-04-mvp

# Standalone features only
/feature list --standalone

# Output:
# FEATURES
# ────────
# Release: 2026-02-04-mvp
#   ✅ 01-foundation  (completed)
#   ✅ 02-auth        (completed)
#   🔄 03-billing     (in progress)
#   ⏳ 04-repairs     (pending)
#
# Standalone:
#   ⏳ dark-mode      (pending)
#   ⏳ export-csv     (pending)
```

---

## Intake Commands

All intake commands operate on the **focused release** by default.

### /intake capture

Capture data from source into release's intake as .md digests.

Supports 26+ source types across 4 categories:
- **MCP:** figma, notion, linear, jira, confluence, slack, miro
- **WebFetch:** gdocs, swagger, graphql, website
- **CLI:** github, db
- **Local:** openapi, postman, protobuf, graphql-schema, pdf, csv, sql, har, docker, terraform, envfile
- **Interactive:** manual, notes

```bash
# Capture for focused release
/intake capture [source]
/intake capture figma
/intake capture gdocs
/intake capture db
/intake capture swagger <url>

# Capture for specific release
/intake capture figma --release 2026-02-10-mobile

# Result: Creates .md digests in releases/<release>/intake/<slug>-v{N}/
```

### /intake add

Add local files or projects as .md digests (never copies raw source files).

```bash
/intake add <path>
/intake add <path> --release 2026-02-04-mvp
/intake add ./src/backend --as backend

# Result: Creates .md digest files in intake (file-tree.md, stack.md, types.md, etc.)
```

### /intake status

Show current version and statistics.

```bash
# Focused release intake
/intake status

# Specific release intake
/intake status --release 2026-02-04-mvp

# Output:
# INTAKE STATUS (2026-02-04-mvp)
# ─────────────────────────────
# Version: mvp-v1.1
# Created: 2026-02-10
# Locked: no
#
# Sources:
#   figma/: 3 .md files
#   gdocs/: 1 .md file
#   notes/: 2 .md files
```

### /intake diff

Compare two versions within a release.

```bash
/intake diff mvp-v1 mvp-v1.1
```

### /intake list

List all versions for a release.

```bash
# Focused release
/intake list

# Specific release
/intake list --release 2026-02-04-mvp

# Output:
# mvp-v1      2026-02-03  major  figma+notion
# mvp-v1.1    2026-02-10  patch  +notes
```

---

## Research Commands

> **Note:** Research is invoked as part of `/feature plan` (which spawns the research agent), not as a standalone command. The syntax below is for reference only.

### /research

Conduct research.

```bash
/research [topic]                 # Standard research
/research --deep [topic]          # Deep research

# Example
/research "Supabase Auth 2FA"
```

**Result:** Creates research files in current feature or release.

---

## Task Commands

> **Note:** Task commands are operations within the `/feature execute` workflow context, not standalone routed commands. They require an active feature execution session.
>
> Context: within active feature execution.

### /task next

Show next task.

```bash
/task next

# Output:
# NEXT TASK
# ─────────
# Feature: 03-billing (2026-02-04-mvp)
# Task: Implement payment acceptance
#
# Context:
#   - Billing service already set up
#   - Transaction model ready
```

### /task done

Mark current task as completed.

```bash
/task done

# Updates plan.md and state.yaml
```

### /task list

List tasks for current feature.

```bash
/task list
```

---

## Ad-hoc Commands

### /do

Execute small tasks with YOLO guarantees (atomic commits, tracking).

```bash
/do [description]

# Examples
/do "Fix login validation"
/do "Add error handling to API"
/do                              # Interactive mode
```

**When to use:**
- Task is clear and doesn't need research
- Changes are localized (1-3 files)
- No architectural impact

**When NOT to use:**
- More than 5 subtasks → create a feature
- Needs research → `/research` + feature
- Architectural changes → feature

**Flow:**
1. Explores codebase
2. Creates plan (1-5 tasks)
3. Executes with atomic commits
4. Updates DO.yaml

**Result:** Creates `.planning/do/NNN-slug/` with plan.md and summary.md.

> **Note:** The canonical directory is `.planning/do/`. If `index.yaml` references `.planning/quick/`, it should be updated to match.

### /do list

Show active and recent tasks.

```bash
/do list

# Output:
# AD-HOC TASKS (/do)
# ──────────────────
#
# Active (2):
#   #003  Add rate limiting       in_progress  2/3 tasks
#   #002  Fix validation          blocked      1/2 tasks
#
# Recent (3):
#   #001  Setup logging           completed    2026-02-01
```

### /do continue [id]

Continue working on a task.

```bash
/do continue 003
```

### /do complete [id]

Mark task as complete.

```bash
/do complete 003
```

### /do cancel [id]

Cancel a task.

```bash
/do cancel 002
```

---

## Debug Commands

> **Note:** `debug.md` handles subcommand routing internally (list, continue, resolve, abandon). `debug-resume.md` needs to be created for resume functionality.

### /debug

Systematic debugging with persistent state across context resets.

```bash
/debug [issue]

# Examples
/debug "API returns 500 on login"
/debug "App crashes when clicking submit"
/debug                              # Resume existing session
```

**Flow:**
1. Gather symptoms (expected, actual, errors, reproduction, timeline)
2. Form hypothesis
3. Test hypothesis (read code, run commands, check logs)
4. If disproved → eliminate, form new hypothesis
5. If confirmed → document root cause, apply fix
6. Verify fix

**Result:** Creates `.planning/debug/{slug}/session.yaml`

### /debug list

Show active and resolved sessions.

```bash
/debug list

# Output:
# DEBUG SESSIONS (/debug)
# ───────────────────────
#
# Active (2):
#   auth-token-expired    investigating   "Redis TTL config"
#   api-timeout           gathering       —
#
# Recent Resolved (3):
#   login-crash           2026-02-02      "Null user object"
```

### /debug continue [id]

Continue investigating a session.

```bash
/debug continue auth-token-expired
```

### /debug resolve [id]

Mark session as resolved.

```bash
/debug resolve auth-token-expired
```

### /debug abandon [id]

Abandon a session without resolution.

```bash
/debug abandon api-timeout
```

---

## Sync Commands

> **Note:** The single `sync` workflow handles subcommand routing internally via argument parsing. Individual subcommands (setup, pull, status, link, refresh) are not separately routed.

### /sync setup [tracker]

Configure external tracker integration.

```bash
/sync setup                       # Auto-detect from git remote
/sync setup github                # Explicit GitHub
/sync setup gitlab                # Explicit GitLab
/sync setup linear                # Explicit Linear
```

**Supported trackers:**
- `github` — GitHub Issues (via `gh` CLI)
- `gitlab` — GitLab Issues (via `glab` CLI)
- `linear` — Linear (via API)
- `jira` — Jira (via API)
- `notion` — Notion (via API)

**Result:** Creates `.planning/sync/config.yaml` and `sync.yaml`

### /sync pull [filter]

Import issues from tracker. **Asks which release to assign features to.**

```bash
/sync pull                        # All open issues
/sync pull --label=bug            # Filter by label
/sync pull GH#123                 # Specific issue
/sync pull GH#123 --as=feature    # Force mapping type
```

**Import flow:**
1. Fetch issues from tracker
2. Auto-map type (bug → /do, feature → feature, epic → release)
3. **Ask user: "Which release to assign to?"**
   - [2026-02-04-mvp] Assign to mvp
   - [2026-02-10-mobile] Assign to mobile
   - [Standalone] Create standalone feature
   - [Skip] Don't import
4. Create YOLO item in appropriate location

**Type auto-mapping:**
- `epic`, `initiative` → Release suggestion
- `feature`, `story` → Feature
- `bug`, `task` → /do task

### /sync status

Show sync state and drift detection.

```bash
/sync status

# Output:
# SYNC STATUS
# ───────────
# Tracker: github (owner/repo)
# Linked: 5 items
# Pending: 2 issues
# Drift: 1 item (GH#123 closed externally)
```

### /sync link <external> <yolo>

Manually link external issue to YOLO item.

```bash
/sync link GH#150 /do/003-validation
```

### /sync refresh [id]

Re-import issue to get latest comments/status.

```bash
/sync refresh GH#123
```

---

## General Commands

### /status

Overall project status.

```bash
/status                           # Brief
/status --full                    # Detailed
/status --releases                # Focus on releases

# Output: See 04-state.md for output format
```

### /init

Initialize YOLO in project.

```bash
/init

# Flow:
# 1. Creates .planning/ structure
# 2. Creates state.yaml (schema v2)
# 3. Suggests /release new or /intake capture
```

### /help

Show help.

```bash
/help                             # General help
/help intake                      # Intake help
/help release                     # Release help
/help feature                     # Feature help
```

---

## Profiles

Profiles control which agent implementations are used for each phase.

### Available Profiles

| Profile | Research | Plan | Execute | Verify | Decide | Best For |
|---------|----------|------|---------|--------|--------|----------|
| `quality` | thorough (opus) | detailed (opus) | standard (sonnet) | strict (sonnet) | conversation (opus) | Critical features |
| `balanced` | thorough (opus) | detailed (opus) | standard (sonnet) | basic (haiku) | conversation (opus) | Default, everyday |
| `budget` | quick (haiku) | minimal (sonnet) | standard (sonnet) | basic (haiku) | skip | Quick tasks |
| `guided` | interactive (opus) | detailed (opus) | standard (sonnet) | strict (sonnet) | conversation (opus) | Complex/ambiguous goals |

> **Footnote:** Model names shown are informational — determined by the implementation variant's configuration, not the profile directly.

### Usage

```
/feature start <goal> --profile quality
/feature start <goal> --profile budget
/release start --profile guided
```

Default profile: `balanced` (configurable in `.planning/state.yaml`)

### Profile Behavior

- **quality**: Maximum quality, higher token cost. Strict verification catches all issues.
- **balanced**: Good balance of quality and cost. Basic verification for speed.
- **budget**: Fastest and cheapest. Skips design decisions. Quick research.
- **guided**: Interactive research asks user 1-3 clarifying questions during exploration.

---

## Global Flags

These flags work with all commands:

| Flag | Short | Description |
|------|-------|-------------|
| `--release <id>` | `-r` | Override focused release |
| `--profile <name>` | `-p` | Select execution profile |
| `--dry-run` | `-n` | Preview without executing |
| `--verbose` | `-v` | Detailed output |
| `--force` | `-f` | Skip confirmations and safety checks |

### Dry-Run Mode

```
/feature plan --dry-run

Preview:
  Workflow: feature-plan.md
  Profile: balanced
  Agents to spawn:
    1. research-thorough (opus, ~2000 tokens)
    2. plan-detailed (opus, ~1500 tokens)
  Estimated cost: ~$0.08

  No changes made.
```

---

## Additional Commands

> **Status: Planned** — these commands are not yet implemented.

### Feature Management

```
/feature delete <id>              # Remove feature permanently (with confirmation)
/feature drop <id> [--reason]     # Mark feature as dropped (preserved in history)
/feature resume                   # Resume last active feature
/feature pause                    # Save state and pause current feature
/feature reopen <id>              # Return completed feature to in_progress
/feature unblock <id>             # Manually unblock a blocked feature
/feature show <id>                # Show detailed feature info
```

### Release Management

```
/release pause                    # Pause active release
/release resume                   # Resume paused release
/release cancel <id>              # Cancel and archive release
/release recover <id>             # Rebuild state from files
```

### Intake Management

```
/intake lock                      # Manually lock intake
/intake unlock                    # Manually unlock intake
/intake prune                     # Remove intermediate versions
/intake refresh-digest            # Regenerate digest files
```

### Task Management

```
/task skip [--reason]             # Skip current task
/task retry                       # Retry failed task
/task add "description"           # Add task to current feature plan
```

---

## Command Routing

Commands flow through layers:

```
User Command
    ↓
index.yaml (route to workflow)
    ↓
Workflow (.md file)
    ↓ reads state, prepares context
Pipeline (.yaml file)
    ↓ defines agent sequence
Agent Orchestrator
    ↓ spawns agents
Generated Agent (.md file)
    ↓ executes task
Workflow (receives output)
    ↓ updates state
User (sees result)
```

### Routing Table

> **Note:** All commands listed here should be registered in `index.yaml`. If any are missing from `index.yaml`, they must be added for the routing to function.

#### Feature Commands

| Command | Workflow | Pipeline | Notes |
|---------|----------|----------|-------|
| `/feature new` | `feature-new.md` | — | Creates feature directory and feature.yaml |
| `/feature start` | `feature-start.md` | — | State setup only (sets status, updates state.yaml; no pipeline) |
| `/feature plan` | `feature-plan.md` | — | Spawns research + plan agents |
| `/feature execute` | `feature-execute.md` | `feature-full.yaml` | Spawns execute + verify agents |
| `/feature verify` | `feature-verify.md` | — | Spawns verify agent |
| `/feature attach` | `feature-attach.md` | — | Moves standalone feature into a release |
| `/feature detach` | `feature-detach.md` | — | Moves release feature to standalone |
| `/feature complete` | `feature-complete.md` | — | Checks tasks/verification, creates summary |
| `/feature status` | (inline, reads state.yaml) | — | Displays current feature progress |

#### Release Commands

| Command | Workflow | Pipeline | Notes |
|---------|----------|----------|-------|
| `/release new` | `release-new.md` | — | Creates release directory structure |
| `/release start` | `release-start.md` | — | Research (codebase exploration), auto-creates features |
| `/release status` | (inline, reads state.yaml) | — | Shows release progress overview |
| `/release end` | `release-end.md` | — | Completes release, locks intake, generates output |
| `/release focus` | `release-focus.md` | — | Sets focused release in state.yaml |
| `/release list` | (inline, reads state.yaml) | — | Lists all releases with status |
| `/release requirements` | — | — | Reads requirements.md directly. No dedicated workflow needed. |

#### Intake Commands

| Command | Workflow | Pipeline | Notes |
|---------|----------|----------|-------|
| `/intake capture` | `intake-capture.md` | — | Captures from 26+ sources as .md digests |
| `/intake add` | `intake-add.md` | — | Adds local files/projects as .md digests |
| `/intake list` | (inline, reads intake directory) | — | Lists intake versions |
| `/intake diff` | `intake-diff.md` | — | Compares two intake versions |
| `/intake status` | (inline, reads intake directory) | — | Shows current version and statistics |

#### Other Commands

| Command | Workflow | Pipeline | Notes |
|---------|----------|----------|-------|
| `/sync` | `sync.md` | — | Single workflow handles subcommand routing internally via argument parsing |
| `/debug` | `debug.md` | `debug.yaml` | Handles subcommand routing internally (list, continue, resolve, abandon) |
| `/do` | `do.md` | — | execute-standard agent |
| `/decide` | — | `design-decision.yaml` | decide-conversation agent |
| `/status` | (inline, reads state.yaml) | — | Overall project status |
| `/help` | (inline) | — | Shows help text |
| `/init` | `init.md` | — | Creates .planning/ structure and state.yaml |

---

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| `NO_FOCUSED_RELEASE` | No release focused | `/release focus <id>` or `/release new <name>` |
| `FEATURE_NOT_FOUND` | Invalid feature ID | Check `/feature list` for valid IDs |
| `RELEASE_NOT_FOUND` | Invalid release ID | Check `/release list` for valid IDs |
| `INTAKE_LOCKED` | Intake locked (release completed) | Cannot modify, use different release |
| `DEPENDENCY_UNMET` | Feature depends on incomplete feature | Complete dependency or `--force` |
| `STATE_LOCKED` | Another workflow is running | Wait or check for stale lock |
| `INVALID_TRANSITION` | Status transition not allowed | Check `07-statuses.md` for valid transitions |

### Error Output Format

```
Error: DEPENDENCY_UNMET

Feature '03-billing' depends on:
  ✅ 01-foundation (completed)
  ❌ 02-auth (in_progress)

Options:
  1. Wait for 02-auth to complete
  2. Run with --force to override
  3. Run /feature detach 03-billing to work standalone
```
