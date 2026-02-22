---
name: yolo:status
description: Show overall project status
argument-hint: ""
allowed-tools:
  - Read
  - Glob
  - Grep
---

<objective>
Display overall project status including releases, current feature, and suggested next action.
</objective>

<execution_context>
Read `.claude/yolo/workflows/status.md` for the workflow.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>
Read `.planning/state.yaml` and follow `.claude/yolo/workflows/status.md`.
</process>
