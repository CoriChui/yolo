# YOLO — You Only Live Once

An autonomous, feature-aware workflow framework for Claude Code.

## How It Works

No action commands. Feature lifecycle is driven by:
- **Git state** — branch `feature/<slug>` defines the active feature; commit trailers record phase
- **Plan scope gates** — every Edit/Write/Bash is checked against the plan's declared file scope
- **Node.js scripts** — test integrity, plan validation, commit verification, reconciliation

## Commands

| Command | Description |
|---------|-------------|
| `/yolo:status` | Show all features and their git-derived steps |
| `/yolo:debug` | Systematic debugging with persistent state |
| `/yolo:help` | List commands and explain the autonomous model |

## Quick Start

1. Copy `.claude/` to your project root
2. Create `workspace/` directory: `mkdir -p workspace/features/done workspace/decisions workspace/debug-sessions`
3. Describe what you want to build — Claude reads the branch and drives the loop

See `.claude/yolo/getting-started.md` for the full guide.

## Scripts (standalone)

```bash
node .claude/yolo/scripts/validate-plan.js plan.md         # Plan quality gates
node .claude/yolo/scripts/commit.js task 1 "msg" --stage    # Prefixed + trailered commits
node .claude/yolo/scripts/reconcile.js feature.md --apply   # Git-evidenced reconciliation
```
