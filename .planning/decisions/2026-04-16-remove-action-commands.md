# Decision: Remove action slash commands

**Date:** 2026-04-16
**Status:** Implemented

## Context

Before gate-hardening, YOLO exposed nine slash commands: init, start, release,
intake, feature, decide, status, debug, help. Six of these were action
commands — they told Claude to DO something (start a feature, create a release,
open an intake session, etc.). The remaining three were informational.

After the `git-as-truth` and `gate-hardening` features shipped, action commands
became redundant:

- Active feature is derivable from branch name (`feature/<slug>`).
- Current phase is derivable from the latest commit's `YOLO-Phase` trailer.
- PreToolUse hooks enforce plan scope on every Edit/Write/Bash.
- PostToolUse Bash hook checks the diff delta against plan scope.
- Status line shows `yolo: <slug> · <phase>` continuously.

There is nothing a user types `/yolo:start` for that Claude cannot infer from
reading the branch and the plan. Keeping the commands around invited two
failure modes:

1. **User forgets to run them** — the original problem that motivated the
   autonomous design in the first place.
2. **Surface-area drift** — each command had its own file in
   `.claude/commands/yolo/` that could diverge from the autonomous path.

## Decision

Delete `init`, `start`, `release`, `intake`, `feature`, and `decide` slash
commands. Keep only the informational ones:

- `/yolo:status` — observability (run reconcile, show drift, list features).
- `/yolo:help` — lists remaining commands and explains the autonomous model.

`/yolo:debug` was already absent at the time of this decision; not reinstated.

## What the autonomous replacement is

| Removed command     | How it happens now |
|---------------------|--------------------|
| `/yolo:init`        | `.planning/` directory is created manually or by a per-project setup script. YOLO simply requires the directory; no state.yaml or config.yaml is maintained. |
| `/yolo:start`       | User describes intent in chat; Claude reads the branch, detects the active feature from `feature/<slug>`, and drives the loop. |
| `/yolo:release`     | Not reinstated. Release-level orchestration was a v1 concept that the v2 redesign dropped. |
| `/yolo:intake`      | Context is pulled on-demand via the existing tools (WebFetch, MCP servers). No formal intake workflow. |
| `/yolo:feature`     | Features are created by writing `.planning/features/<slug>/feature.md` on a `feature/<slug>` branch; the hooks pick up scope automatically. |
| `/yolo:decide`      | Decision docs are authored directly into `.planning/decisions/YYYY-MM-DD-<slug>.md`. No wrapper command needed. |

## What to do when users ask for the removed commands

- If they type `/yolo:start`, Claude responds: *"No longer a command. Describe
  what you want to build; I'll read the branch and drive the loop."*
- If they ask about release orchestration or intake, explain that the v3 design
  consolidated those into a single-feature loop and point them at the decision
  record `2026-04-13-v3-redesign.md`.

## Trade-offs

- **Lost:** A muscle-memory entry point for users who prefer explicit commands.
- **Gained:** Smaller surface area, no divergence between "what the command
  does" and "what the autonomous path does," clearer mental model that YOLO is
  about enforcement, not orchestration.
