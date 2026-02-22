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
  /yolo:feature start <id> [--prompt]  Full pipeline (research → plan → execute → verify-fix → verify → complete)
  /yolo:feature plan [--amend]        Create or amend execution plan
  /yolo:feature verify                Check success criteria
  /yolo:feature complete              Mark feature done
  /yolo:feature status [id]           Show feature progress

Intake (auxiliary context per release):
  /yolo:intake capture <source> [url] [--raw]  Capture from 26 sources
  /yolo:intake add <path> [--as <name>]       Add local files as .md digests
  /yolo:intake list            List intake versions
  /yolo:intake status          Show current version and stats

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
