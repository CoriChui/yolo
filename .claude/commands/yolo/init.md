---
name: yolo:init
description: Initialize YOLO in current project
argument-hint: ""
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
---

<objective>
Initialize YOLO framework in the current project. Creates `workspace/` structure and initial state.
</objective>

<execution_context>
Read `.claude/yolo/workflows/init.md` for the workflow.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>
Follow `.claude/yolo/workflows/init.md`.
</process>
