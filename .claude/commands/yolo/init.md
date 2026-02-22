---
name: yolo:init
description: Initialize YOLO in current project
argument-hint: ""
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - AskUserQuestion
---

<objective>
Initialize YOLO framework in the current project. Creates `.planning/` structure and initial state.
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
