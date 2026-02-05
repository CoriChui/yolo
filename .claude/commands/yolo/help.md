---
name: yolo:help
description: Show available YOLO commands and usage guide
argument-hint: "[command]"
allowed-tools:
  - Read
---

<objective>
Display help for YOLO (You Only Live Once) commands.

Without arguments: Show all commands overview.
With argument: Show detailed help for specific command.
</objective>

<process>

## No Arguments — Overview

Display:

```
YOLO — You Only Live Once
═════════════════════════

A simplified development workflow where codebase is the source of truth.
Multiple releases can run in parallel. Commands operate on the focused release.

COMMANDS
────────

Setup:
  /yolo:init                   Initialize YOLO in project
  /yolo:status                 Show overall project status
  /yolo:status --full          Detailed status with all sections
  /yolo:status --releases      Focus on releases only

Releases (parallel work containers):
  /yolo:release new <slug>     Create pending release + intake
  /yolo:release start [id]     Start release (research + features)
  /yolo:release status [id]    Show release state
  /yolo:release end [id]       Complete release
  /yolo:release focus <id>     Set focused release
  /yolo:release list           List all releases
  /yolo:release requirements   Show requirements

Features (release-scoped or standalone):
  /yolo:feature new <slug>     Create standalone feature
  /yolo:feature start <id>     Start feature
  /yolo:feature plan           Create execution plan
  /yolo:feature execute        Execute tasks
  /yolo:feature verify         Check success criteria
  /yolo:feature complete       Complete feature
  /yolo:feature attach <f> <r> Attach standalone to release
  /yolo:feature detach <f> <r> Detach from release
  /yolo:feature list           List all features
  /yolo:feature status         Current feature details

Intake (auxiliary context per release):
  /yolo:intake capture [src]   Capture from 26+ sources (MCP, WebFetch, CLI, local)
  /yolo:intake add <path>      Add local files/projects as .md digests
  /yolo:intake diff <v1> <v2>  Compare two versions
  /yolo:intake status          Show current intake
  /yolo:intake list            List all versions

Ad-hoc Tasks:
  /yolo:do [desc]              Start new task
  /yolo:do list                Show active tasks
  /yolo:do continue [id]       Continue task
  /yolo:do complete [id]       Complete task
  /yolo:do cancel [id]         Cancel task

Debugging:
  /yolo:debug [issue]          Start debug session
  /yolo:debug list             Show sessions
  /yolo:debug continue [id]    Continue session
  /yolo:debug resolve [id]     Resolve session
  /yolo:debug abandon [id]     Abandon session

External Sync:
  /yolo:sync setup [tracker]   Configure tracker
  /yolo:sync pull [filter]     Import issues
  /yolo:sync status            Show sync state
  /yolo:sync link <ext> <yolo> Manual linking
  /yolo:sync refresh [id]      Re-import issue

Agents:
  /yolo:sync-agents            Regenerate agents from sources
  /yolo:sync-agents --check    Show agent status
  /yolo:sync-agents --validate Regenerate + validate

Help:
  /yolo:help                   This help
  /yolo:help [command]         Command details

PROFILES
────────

Profiles control agent quality/speed tradeoffs:

  quality    — Thorough research (opus), strict verification. Critical features.
  balanced   — Good quality, reasonable cost. Default.
  budget     — Fast and cheap. Quick tasks, /do.
  guided     — Interactive research asks user questions. Complex goals.

Usage: /yolo:release start --profile quality
       /yolo:feature start auth --profile guided

GLOBAL FLAGS
────────────

  --release <id>  (-r)  Override focused release
  --profile <name> (-p)  Select execution profile
  --dry-run (-n)         Preview without executing
  --verbose (-v)         Detailed output
  --force (-f)           Skip confirmations

QUICK START
───────────

1. Initialize project:
   /yolo:init

2. Start a release with intake:
   /yolo:release new mvp
   /yolo:intake capture figma
   /yolo:intake capture gdocs
   /yolo:intake capture db
   /yolo:intake add ./src/backend --as backend
   /yolo:release start
   /yolo:feature start 01-auth
   /yolo:feature plan
   /yolo:feature execute

3. Create a second release in parallel:
   /yolo:release new mobile
   /yolo:release focus mvp          ← switch back to mvp

4. Standalone feature (no release):
   /yolo:feature new dark-mode
   /yolo:feature start dark-mode

5. Small task (no release needed):
   /yolo:do "fix login validation"

6. Bug to investigate:
   /yolo:debug "API returns 500"

7. Use a specific profile:
   /yolo:feature start auth --profile quality

STATE MACHINE
─────────────

Releases run in parallel, each with independent state:

                    /release new
                         │
                         ▼
                ┌─────────────────┐
                │ RELEASE PENDING │ ← intake open, capture allowed
                └────────┬────────┘
                         │ /release start
                         ▼
                ┌─────────────────┐
          ┌─────│ RELEASE ACTIVE  │ ← intake open, work on features
          │     └────────┬────────┘
          │              │ /release end
     pause/fail         ▼
          │     ┌─────────────────┐
          │     │RELEASE COMPLETED│ ← intake locked, archived
          │     └─────────────────┘
          ▼
   ┌──────────────┐
   │ PAUSED/FAILED│ ← can resume or cancel
   │  /CANCELLED  │
   └──────────────┘

Use /release focus <id> to switch between parallel releases.

Standalone features exist outside releases:
  /feature new <slug>       ← create standalone
  /feature attach <f> <r>   ← move into a release
  /feature detach <f> <r>   ← move out of release

DOCUMENTATION
─────────────

Workflows: .claude/yolo/workflows/
Templates: .claude/yolo/templates/
Agents:    .claude/yolo/agents/generated/
Profiles:  .claude/yolo/profiles/
Specs:     .claude/yolo/specs/
```

---

## With Argument — Command Details

**If $ARGUMENTS is `release`:**

```
/yolo:release — Release Management
══════════════════════════════════

Manage releases — top-level work containers with intake.
Multiple releases can run in parallel.

USAGE
─────
  /yolo:release new <slug>     Create pending release
  /yolo:release start [id]     Start release (runs research)
  /yolo:release status [id]    Show release state
  /yolo:release end [id]       Complete release
  /yolo:release focus <id>     Set focused release
  /yolo:release list           List all releases
  /yolo:release requirements   Show requirements

FLOW
────
  /release new mvp          ← pending + intake created, set as focused
  /intake capture figma     ← gather materials (26+ source types)
  /release start            ← research, define features (uses agents)
  /feature start 01-auth    ← work on features
  /feature complete
  /release end              ← done, intake locked

  /release new mobile       ← second parallel release
  /release focus mvp        ← switch focus back

KEY POINTS
──────────
  • Multiple releases can run in parallel
  • Use /release focus <id> to switch between releases
  • Each release has its own intake version
  • Intake locked when release ends
  • Use --profile to control agent quality for /release start
```

**If $ARGUMENTS is `feature`:**

```
/yolo:feature — Feature Management
══════════════════════════════════

Manage features — release-scoped or standalone work units.

USAGE
─────
  /yolo:feature new <slug>       Create standalone feature
  /yolo:feature start <id>       Start feature by ID
  /yolo:feature plan             Create execution plan
  /yolo:feature execute          Execute planned tasks
  /yolo:feature verify           Check success criteria
  /yolo:feature complete         Mark feature done
  /yolo:feature attach <f> <r>   Attach standalone to release
  /yolo:feature detach <f> <r>   Detach from release
  /yolo:feature list             List all features
  /yolo:feature status           Current feature details

FLOW (release-scoped)
─────────────────────
  /feature start 01-auth    ← begin work in focused release
  /feature plan             ← detailed plan (uses agents)
  /feature execute          ← implement (uses agents)
  /feature verify           ← check criteria (uses agents)
  /feature complete         ← done

FLOW (standalone)
─────────────────
  /feature new dark-mode    ← create standalone
  /feature start dark-mode  ← work on it
  /feature attach dark-mode 2026-02-04-mvp  ← attach to release

KEY POINTS
──────────
  • Features can be release-scoped OR standalone
  • Standalone features created with /feature new
  • /feature attach and /feature detach move between modes
  • Plan before execute, verify before complete
  • Use --release <id> to specify release explicitly
  • Use --standalone flag with /feature list to filter
  • Agent delegation used for plan/execute/verify phases
```

**If $ARGUMENTS is `intake`:**

```
/yolo:intake — Intake Management
════════════════════════════════

Capture auxiliary materials from 26+ source types.
Intake is per-release — each release has its own intake.
All output is .md digest files only — no raw source files.

USAGE
─────
  /yolo:intake capture [src]     Capture from source
  /yolo:intake add <path>        Add local files/projects as .md digests
  /yolo:intake diff <v1> <v2>    Compare two versions
  /yolo:intake status            Show current intake
  /yolo:intake list              List all versions

REQUIRES RELEASE
────────────────
  Intake capture is BLOCKED without a pending or active release.
  Uses focused release by default. Override with --release <id>.

  /release new mvp           ← creates intake mvp-v1
  /intake capture figma      ← capture from Figma MCP
  /intake capture gdocs      ← capture Google Sheets via WebFetch
  /intake capture db         ← capture DB schema via CLI
  /intake add ./src/backend  ← add project as .md digests
  /release end               ← intake locked

SOURCES (26+ types)
───────────────────
  MCP:        figma, notion, linear, jira, confluence, slack, miro
  WebFetch:   gdocs, swagger, graphql, website
  CLI:        github, db
  Local:      openapi, postman, protobuf, graphql-schema, pdf, csv,
              sql, har, docker, terraform, envfile
  Interactive: manual, notes
```

**If $ARGUMENTS is `do`:**

```
/yolo:do — Ad-hoc Task Execution
════════════════════════════════

Execute small tasks with tracking and atomic commits.
Uses budget profile by default for speed.

USAGE
─────
  /yolo:do [description]       Start and execute new task
  /yolo:do list                Show active and recent tasks
  /yolo:do continue [id]       Continue working on task
  /yolo:do complete [id]       Mark task complete
  /yolo:do cancel [id]         Cancel task

EXAMPLES
────────
  /yolo:do "fix login validation"
  /yolo:do "add error handling to API"
  /yolo:do list
  /yolo:do continue 003
  /yolo:do complete 003
  /yolo:do "add caching" --profile quality

WHEN TO USE
───────────
  ✓ Task is clear, no research needed
  ✓ Changes are localized (1-3 files)
  ✓ No architectural impact
  ✓ Doesn't need a full release

WHEN NOT TO USE
───────────────
  ✗ More than 5 subtasks → use release/feature
  ✗ Needs research → /yolo:debug or release
  ✗ Architectural changes → release
```

**If $ARGUMENTS is `debug`:**

```
/yolo:debug — Systematic Debugging
══════════════════════════════════

Debug issues using scientific method with persistent state.
Can use agents for research and fix application.

USAGE
─────
  /yolo:debug [issue]          Start new session
  /yolo:debug list             Show all sessions
  /yolo:debug continue [id]    Continue session
  /yolo:debug resolve [id]     Mark resolved
  /yolo:debug abandon [id]     Abandon session

EXAMPLES
────────
  /yolo:debug "login fails after 1 minute"
  /yolo:debug "API returns 500 on POST"
  /yolo:debug list
  /yolo:debug continue auth-timeout
  /yolo:debug "complex issue" --profile quality

THE PROCESS
───────────
  1. Gather symptoms (expected, actual, errors)
  2. Form hypothesis
  3. Test hypothesis (can delegate to agents)
  4. If disproved → eliminate, new hypothesis
  5. If confirmed → document root cause
  6. Apply and verify fix

KEY FEATURE: PERSISTENCE
────────────────────────
  Session file survives /clear.
  - Eliminated section prevents re-investigating
  - Evidence section preserves findings
  - Current Focus shows where to resume
```

**If $ARGUMENTS is `sync`:**

```
/yolo:sync — External Tracker Sync
═══════════════════════════════════

Import issues from external trackers into YOLO workflow.
Currently only GitHub adapter is fully implemented.

USAGE
─────
  /yolo:sync setup [tracker]     Configure tracker
  /yolo:sync pull [filter]       Import issues
  /yolo:sync status              Show sync state
  /yolo:sync link <ext> <yolo>   Manual linking
  /yolo:sync refresh [id]        Re-import issue

SUPPORTED TRACKERS
──────────────────
  github   GitHub Issues (via gh CLI)  ← currently implemented
  gitlab   GitLab Issues (via glab CLI)
  linear   Linear (via API)
  jira     Jira (via API)
  notion   Notion (via API)

TYPE MAPPING
────────────
  epic, initiative → Release suggestion
  feature, story   → Feature
  bug, task, chore → /do task

FLOW
────
  /sync setup github         ← detect repo, authenticate
  /sync pull                 ← import open issues
  /sync pull --label=bug     ← filter by label
  /sync status               ← check for drift
  /sync link GH#150 /do/003  ← manual link
  /sync refresh GH#123       ← re-import latest
```

</process>

<success_criteria>
- [ ] Shows appropriate help based on arguments
- [ ] All commands from 05-commands.md represented
- [ ] Examples are clear and copy-pasteable
- [ ] State machine shows parallel releases
- [ ] Profiles section documented
- [ ] Sync command detailed
</success_criteria>
