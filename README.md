# YOLO — You Only Live Once

A simplified development workflow framework for Claude Code.

## Commands

| Command | Description |
|---------|-------------|
| `/yolo:do [desc]` | Execute small ad-hoc tasks with tracking |
| `/yolo:debug [issue]` | Systematic debugging with persistent state |
| `/yolo:sync [action]` | Import issues from external trackers |
| `/yolo:help` | Show available commands |

## Installation

1. Copy the `.claude/` directory to your project root
2. Run `/yolo:init` to initialize the framework

## Quick Start

```bash
# Small task
/yolo:do "fix login validation"

# Debug an issue
/yolo:debug "API returns 500"

# Import from GitHub
/yolo:sync setup github
/yolo:sync pull --label=bug
```

## Features

- **Atomic commits** — Each change is tracked and committed properly
- **Persistent state** — Debug sessions survive `/clear`
- **External sync** — Import from GitHub, GitLab, Linear, Jira
- **Auto-mapping** — epic→release, feature→feature, bug→/do task
