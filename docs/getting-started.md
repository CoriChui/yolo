# Getting Started with YOLO

## What It Is

YOLO is a coding framework for Claude Code that enforces quality through deterministic shell scripts and git-evidenced state. It manages features through a loop: **think → plan → do → check → ship**.

Two killer features no other framework has:
1. **Shell script sensors** — test integrity checks, plan validation, commit verification
2. **Git-evidenced reconciliation** — workflow state derived from commit history, not YAML files

## Setup

```
/yolo:init
```

This creates the `.planning/` directory structure and verifies hooks are configured.

## Start a Feature

```
/yolo:start "add user authentication"
```

The orchestrator will:
1. **Think** — read the codebase, confirm approach with you
2. **Plan** — write a task breakdown, validate it (2-12 tasks, TDD coverage, descriptions)
3. **Do** — execute each task with TDD (write failing test → implement → verify)
4. **Check** — run full test suite, verify criteria
5. **Ship** — merge to main

### With External Context

Have a Figma design or spec doc? Pass it in:

```
/yolo:start "add payment flow" --context designs/payment.md
/yolo:start "add auth" --context https://docs.example.com/api
```

Multiple context files work:

```
/yolo:start "add dashboard" --context designs/dash.md --context api-spec.yaml
```

### With Research Agent

For complex features, spawn an Opus research agent to explore the codebase first:

```
/yolo:start "refactor auth system" --context spec.md --research
```

### Quick Mode

For trivial fixes:

```
/yolo:start "fix typo in README" --just-do-it
```

## Resume After Context Reset

```
/yolo:start
```

No arguments = resume. Reads `.planning/.focus` to find the current feature, runs `reconcile.sh` to derive the step from git history, and picks up where it left off.

## Other Commands

```
/yolo:status          — show all features and their derived steps
/yolo:debug new "bug" — start a systematic debug session
/yolo:decide "question" — design decision with Architect/Pragmatist/Critic debate
/yolo:help            — list all commands
```

## What Happens Under the Hood

Each task commit uses `[task-N]` prefixes:
```
[task-1] implement user model
[task-2] add auth middleware
[task-3] wire login endpoint
```

Shell scripts enforce quality at every step:
- **commit.sh** — detects deleted tests, skip markers, test count decrease (warns, doesn't block)
- **validate-plan.sh** — rejects plans with no tests, vague descriptions, structural issues
- **reconcile.sh** — compares plan checkboxes against git commits, fixes drift
- **verify-commit.sh** — compares claimed vs actual file changes

State lives in three places:
- `.planning/.focus` — current feature slug (one line)
- `.planning/features/{slug}.md` — feature goal, plan, criteria, verification
- Git commits with `[task-N]` prefixes — the canonical record of work

On crash or `/clear`, `reconcile.sh` rebuilds state from git alone.

## Directory Structure

```
.planning/
  .focus                    ← current feature (one line)
  features/
    {slug}.md               ← active features
    done/                   ← shipped features
  decisions/                ← design decision records
  debug-sessions/           ← debug session state

.claude/
  commands/yolo/
    start.md                ← /yolo:start command
    status.md               ← /yolo:status command
    debug.md                ← /yolo:debug command
    decide.md               ← /yolo:decide command
    init.md                 ← /yolo:init command
    help.md                 ← /yolo:help command
  yolo/
    loop.md                 ← the orchestrator (the brain)
    agents/
      execute.md            ← TDD task execution
      check.md              ← verification with evidence
      research.md           ← codebase + context exploration
      debug.md              ← root cause analysis
      decide.md             ← design decisions
    workflows/
      status.md             ← status reconciliation
      debug.md              ← debug session lifecycle
    reference/
      agent-guidelines.md   ← extended agent guidance (not loaded into context)
      scripts.md            ← standalone script documentation

scripts/yolo-cli/
    commit.sh               ← commit with test integrity sensors
    validate-plan.sh        ← plan quality checks
    reconcile.sh            ← git-evidenced state reconciliation
    verify-commit.sh        ← post-commit file verification
    run-tests.sh            ← test/lint runner
    hook-pre-bash.sh        ← blocks destructive git ops
    hook-post-write.sh      ← advisory test file notes
    lib.sh                  ← shared utilities
    test-*.sh               ← 243 tests for the framework itself
```

## Using Shell Scripts Standalone

Every script works without the full YOLO workflow:

```bash
# Commit with test integrity checks
bash scripts/yolo-cli/commit.sh task 1 "add feature" --stage

# Validate any markdown plan
bash scripts/yolo-cli/validate-plan.sh my-plan.md

# Reconcile a feature file against git
bash scripts/yolo-cli/reconcile.sh .planning/features/my-feature.md --apply

# Get JSON output for programmatic use
bash scripts/yolo-cli/commit.sh task 1 "msg" --stage --json
```

See `scripts/yolo-cli/README.md` or `.claude/yolo/reference/scripts.md` for full docs.
