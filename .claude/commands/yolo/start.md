---
name: yolo:start
description: Start or resume a feature — enters the adaptive loop (think → plan → do → check → ship)
argument-hint: '"description" [--just-do-it]'
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Task
  - ToolSearch
  - Skill
  - WebSearch
  - WebFetch
---

<objective>
Start a new feature or resume an existing one through the YOLO v2 adaptive loop.

**Usage:**
- `/yolo:start "add dark mode support"` — new feature, full loop
- `/yolo:start --just-do-it "fix null pointer in auth.ts"` — quick confirmation only
- `/yolo:start` — resume current feature (if one exists)
</objective>

<execution_context>
Read `.claude/yolo/v2/loop.md` for the orchestrator instructions. Follow them exactly.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>

## Parse Arguments

- Extract description from arguments (quoted string after the command)
- Check for `--just-do-it` flag
- If no arguments: check `.planning/features/` for an in-progress feature to resume

## Execute

1. Read `.claude/yolo/v2/loop.md`
2. Follow the loop orchestrator instructions:
   - If description provided: start new feature
   - If no description but existing feature found: resume it
   - If `--just-do-it`: think step is quick confirmation only

</process>
