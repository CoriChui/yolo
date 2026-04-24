---
name: yolo:release
description: Create and manage releases (major feature sets)
argument-hint: "[new|start|run|status|end] [args] [--from] [--prompt]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Task
  - Skill
  - ToolSearch
  - WebSearch
  - WebFetch
---

<objective>
Manage releases — the top-level work containers.

**Subcommands:**
- `/yolo:release new <slug>` — Create pending release + intake
- `/yolo:release start [id] [--prompt "<text>"]` — Research codebase, define goal, create features
- `/yolo:release run [id] [--from <feature-id>]` — Run all features sequentially through full pipeline
- `/yolo:release status [id]` — Show release progress
- `/yolo:release end [id]` — Complete release, lock intake
</objective>

<execution_context>
Read `.claude/yolo/workflows/release.md` for the workflow. Read `.planning/state.yaml` first.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>

## Parse Subcommand

- `new <slug>` → Create pending release
- `start [id] [--prompt "<text>"]` → Start pending release (research + features)
- `run [id] [--from <id>]` → Run all features sequentially
- `status [id]` → Show release state (default if empty)
- `end [id]` → Complete active release
- **else** → Error: "Unknown subcommand '{arg}'. Run `/yolo:help` for usage."

Read `.claude/yolo/workflows/release.md` and follow the matching subcommand section.

</process>
