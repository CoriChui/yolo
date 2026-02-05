---
name: yolo:status
description: Show overall project status
argument-hint: "[--full|--releases]"
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
---

<objective>
Display overall project status including all releases, current feature, profile, and recent activity.
</objective>

<execution_context>
@./.claude/yolo/workflows/status.md
</execution_context>

<context>
Arguments: $ARGUMENTS

```bash
cat .planning/state.yaml 2>/dev/null
```
</context>

<process>

## Load State

Read `.planning/state.yaml` and extract:
- Focus (current release, current feature)
- All releases with progress
- Standalone features
- Current profile
- Recent activity

## Parse Flags

- `--full` → Detailed view with all sections
- `--releases` → Focus on releases only

## Display Status

### Brief (default)

```
═══════════════════════════════════════════════════════════════
YOLO STATUS
═══════════════════════════════════════════════════════════════

Releases:
  ★ 2026-02-04-mvp (active) [FOCUSED]
    Progress: ████████░░░░ 50% (2/4 features)
  ○ 2026-02-10-mobile (pending)
    Progress: not started

Profile: balanced

Feature: 03-billing (in_progress)
Tasks: ████░░░░░░ 33% (2/6 tasks)

Standalone: 2 features (0 active)

Last: Completed "Set up billing service"

───────────────────────────────────────────────────────────────
COMMANDS:
  /yolo:feature execute    Continue current feature
  /yolo:release focus ...  Switch release context
  /yolo:do list            Show ad-hoc tasks
  /yolo:debug list         Show debug sessions
═══════════════════════════════════════════════════════════════
```

### Full (--full)

Include:
- All releases with feature breakdowns
- Standalone features list
- Active /do tasks
- Active debug sessions
- Active profile and agent configuration
- Recent commits
- Session resume context

### Releases (--releases)

Show only release information:
- All releases with status and progress
- Feature counts per release
- Intake status per release

</process>

<error_handling>

**No state.yaml:**
```
No YOLO project found.

Initialize with:
  /yolo:init

Or start quick task:
  /yolo:do "description"
```

</error_handling>
