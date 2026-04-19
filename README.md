# YOLO — You Only Live Once

An autonomous, feature-aware workflow framework for Claude Code.

## How It Works

No action commands. Feature lifecycle is driven by:
- **Git state** — branch `feature/<slug>` defines the active feature; commit trailers record phase
- **Plan scope gates** — every Edit/Write/Bash is checked against the plan's declared file scope
- **Shell script sensors** — test integrity, plan validation, commit verification, reconciliation

## Commands

| Command | Description |
|---------|-------------|
| `/yolo:status` | Show all features and their git-derived steps |
| `/yolo:help` | List commands and explain the autonomous model |

## Quick Start

1. Copy `.claude/` and `scripts/yolo-cli/` to your project
2. Create `.planning/` directory: `mkdir -p .planning/features .planning/decisions`
3. Describe what you want to build — Claude reads the branch and drives the loop

See `docs/getting-started.md` for the full guide.

## Shell Scripts (standalone)

```bash
bash scripts/yolo-cli/validate-plan.sh plan.md         # Plan quality gates
bash scripts/yolo-cli/commit.sh task 1 "msg" --stage    # Prefixed + trailered commits
bash scripts/yolo-cli/reconcile.sh feature.md --apply   # Git-evidenced reconciliation
```
