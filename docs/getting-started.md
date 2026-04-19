# Getting Started with YOLO

## What It Is

YOLO is an autonomous, feature-aware workflow framework for Claude Code. It enforces quality through deterministic shell scripts, git-evidenced state, and tool-layer scope gates. Features flow through a loop: **think → plan → do → check → ship**.

Three things no other framework has:
1. **PreToolUse scope gates** — every Edit/Write/Bash is checked against the plan's declared file scope; out-of-scope writes are blocked.
2. **Git as sole source of truth** — active feature = branch name (`feature/<slug>`); current phase = latest commit's `YOLO-Phase` trailer; no separate state files.
3. **Shell script sensors** — test integrity checks, plan validation, commit verification, reconciliation.

## Setup

Create the `.planning/` directory structure:

```
mkdir -p .planning/features .planning/decisions
```

YOLO requires `jq` on your PATH and the hooks wired in `.claude/settings.json` (already present in this repo).

## Working on a Feature

No slash commands needed. Just describe what you want:

> "Let's add user authentication."

Claude will:
1. Read the current git branch and `.planning/` state
2. Create a feature branch (`feature/user-auth`) and plan file (`.planning/features/user-auth/feature.md`)
3. Drive the think → plan → do → check → ship loop
4. Each task commit carries `YOLO-Feature` and `YOLO-Phase` trailers

The **PreToolUse gate** enforces the plan's file scope — Claude can only edit files declared in the plan's `files:` annotations. To extend scope, add paths to the plan.

## Resume After Context Reset

Just say what you want to continue. Claude reads the branch name (`feature/<slug>`), finds the feature file, runs `reconcile.sh` to derive the current phase from git history, and picks up where you left off.

## Commands

Only informational commands exist — no action commands:

```
/yolo:status    — show all features and their derived steps
/yolo:help      — list commands and explain the autonomous model
```

## Escape Hatches

```
YOLO_BYPASS=1              — skip scope gate for one hook invocation
YOLO_POST_BASH_REVERT=1   — enable auto-revert of out-of-scope bash writes
YOLO_NO_PHASE_CACHE=1     — bypass status-line phase cache
```

## Shell Script Toolbox

Each script works standalone without YOLO setup:

```bash
# Validate any markdown plan
bash scripts/yolo-cli/validate-plan.sh my-plan.md

# Reconcile a feature file against git
bash scripts/yolo-cli/reconcile.sh .planning/features/my-feature.md --apply

# Commit with prefix + trailers
bash scripts/yolo-cli/commit.sh task 1 "implement auth" --stage

# Get JSON output for programmatic use
bash scripts/yolo-cli/commit.sh task 1 "msg" --stage --json
```

## Directory Structure

```
.planning/
  features/
    {slug}/feature.md     ← active features (spec + plan)
    done/                 ← shipped features
  decisions/              ← design decision records
  .audit.log              ← every gate block/bypass recorded

.claude/
  commands/yolo/
    status.md             ← /yolo:status command
    help.md               ← /yolo:help command
  yolo/
    loop.md               ← orchestrator (think/plan/do/check/ship)
    agents/               ← research, execute, check agents
    reference/            ← agent guidelines, script docs
  settings.json           ← hook wiring, permissions, status line

scripts/yolo-cli/
  lib.sh                  ← shared helpers (get_active_feature, is_path_in_scope, etc.)
  commit.sh               ← prefix-enforced git commit with trailers
  reconcile.sh            ← git-evidenced plan reconciliation
  validate-plan.sh        ← plan quality gates
  verify-commit.sh        ← post-commit file verification
  hook-pre-bash.sh        ← PreToolUse: destructive ops + write-redirection gate
  hook-pre-write.sh       ← PreToolUse: Edit/Write scope gate
  hook-post-bash.sh       ← PostToolUse: delta-based diff enforcement
  active-feature.sh       ← status line: prints slug + phase
```
