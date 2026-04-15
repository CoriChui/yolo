---
name: yolo:init
description: Use when YOLO has never been set up in this project, or when `.planning/` is missing/corrupt and needs repair. Creates state.yaml, config.yaml, and the releases/decisions scaffolding.
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
