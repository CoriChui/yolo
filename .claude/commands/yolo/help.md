---
name: yolo:help
description: Show available YOLO commands and usage guide
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
YOLO — You Only Live Once
═════════════════════════

Setup:
  /yolo:init                   Initialize YOLO in project
  /yolo:status                 Show project status

Releases:
  /yolo:release new <slug>     Create pending release + intake
  /yolo:release start [id] [--prompt]  Start release (research + features)
  /yolo:release run [id] [--from <id>]  Run all features sequentially
  /yolo:release status [id]    Show release state
  /yolo:release end [id]       Complete release

Features:
  /yolo:feature start <id> [--prompt]  Full pipeline (research → plan → execute → hook gate → verify → complete)
  /yolo:feature add <name> [--prompt]  Add new feature to active release
  /yolo:feature plan [--amend] [--prompt]  Create or amend execution plan
  /yolo:feature verify [--force]      Check success criteria (auto-completes on pass; --force bypasses hook_gate_failed guard). Calling on in_progress skips hook gate; accepts verify_failed for re-verification
  /yolo:feature complete              Finalize feature, create summary (requires passed verify; normally auto-called)
  /yolo:feature status [id]           Show feature progress

Intake (auxiliary context per release):
  /yolo:intake capture <source> [url] [--raw] [--release <id>] [--prompt]  Capture from 26 sources
  /yolo:intake add <path> [--as <name>] [--release <id>] [--prompt]      Add local files as .md digests
  /yolo:intake list [-r <id>]  List intake versions
  /yolo:intake status [-r <id>] Show current version and stats

Other:
  /yolo:decide [question]      Design decision with multi-perspective analysis
  /yolo:help [command]         This help

QUICK START
───────────
  /yolo:init
  /yolo:release new mvp
  /yolo:intake capture figma
  /yolo:release start
  /yolo:feature start 01
```

## With Argument — Command Details

Read the command file for the specified command and display its objective and subcommands.

</process>
