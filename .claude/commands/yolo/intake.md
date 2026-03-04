---
name: yolo:intake
description: Capture and manage auxiliary intake materials from 26 source types
argument-hint: "[capture|add|list|status] [args] [--raw|--as|--release|--prompt]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - ToolSearch
  - WebFetch
---

<objective>
Manage auxiliary intake materials from external sources.

**Subcommands:**
- `/yolo:intake capture <source> [url] [--raw] [--release <id>] [--prompt "<text>"]` — Capture from 26 sources (MCP, WebFetch, CLI, local). `--raw`: copy content as-is without processing.
- `/yolo:intake add <path> [--as <name>] [--release <id>] [--prompt "<text>"]` — Add local files/projects as .md digests
- `/yolo:intake list [--release <id>]` — List intake versions
- `/yolo:intake status [--release <id>]` — Show current version and stats

Intake operates on the **focused release** by default. Use `--release <id>` to override.
Intake requires a pending or active release.
</objective>

<execution_context>
Read `.claude/yolo/workflows/intake.md` for the workflow. Read `.planning/state.yaml` first.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>

## Parse Subcommand

- `capture <source>` → Capture from source
- `add <path>` → Add local files as .md digests
- `list` → List all versions
- `status` → Show current version and stats
- Empty → Show status
- **else** → Error: "Unknown subcommand '{arg}'. Run `/yolo:help` for usage."

Parse flags:
- `--raw` → Copy content as-is without processing
- `--release <id>` or `-r` → Override focused release
- `--as <name>` → Name for the intake source (for `add` subcommand)
- `--prompt "<text>"` → Custom instructions for capture/extraction

Read `.claude/yolo/workflows/intake.md` and follow the matching subcommand section.

</process>
