---
name: yolo:help
description: Use when the user wants to list YOLO commands, learn what YOLO can do, or get details on a specific command.
argument-hint: "[command]"
allowed-tools:
  - Read
---

<objective>
Display help for YOLO commands. Without arguments: show overview. With argument: show command details.
</objective>

<execution_context>
Self-contained command — no workflow or agent file. Read-only.
</execution_context>

<process>

## No Arguments — Overview

```
YOLO — autonomous, feature-aware workflow framework
═══════════════════════════════════════════════════

How it works
────────────
YOLO has no action commands. Feature lifecycle is driven by:

  • git state    — branch `feature/<slug>` defines the active feature;
                   commit trailers (YOLO-Feature, YOLO-Phase) record phase
  • .planning/   — human-authored feature specs, decisions, lessons
  • PreToolUse   — Edit/Write/Bash writes are gated against the plan's
                   file scope; out-of-scope writes are blocked (exit 2)
  • PostToolUse  — `git status` delta is checked after every bash call;
                   any out-of-scope change produced by the command is
                   reported (revert via YOLO_POST_BASH_REVERT=1)
  • StatusLine   — shows `yolo: <slug> · <phase>` when a feature is active

Starting or resuming work
─────────────────────────
Just describe what you want. Claude reads the branch, checks the plan,
and drives the loop (think → plan → do → check → ship). You never type a
slash command to begin work.

Informational commands
──────────────────────
  /yolo:status      Show the active feature, phase, and any drift
                    against git evidence. Use after context resets or
                    when you suspect stuck state.

  /yolo:help [cmd]  Show this overview, or details for a specific
                    command.

Escape hatches
──────────────
  YOLO_BYPASS=1               Skip pre-hook scope gate for one shell
  YOLO_POST_BASH_REVERT=1     Enable auto-revert of out-of-scope writes
  YOLO_NO_PHASE_CACHE=1       Bypass the status-line phase cache

Audit
─────
  .planning/.audit.log        Every gate block and bypass is recorded
                              here (tab-separated: ts, event, hook,
                              feature, target, extra)

Extending a plan's scope
────────────────────────
If the gate blocks a legitimate edit, add the path to a task's
`files:` annotation in the feature.md and the hook will let it through.
```

## With Argument — Command Details

Read the command file for the specified command and display its objective and subcommands.

</process>
