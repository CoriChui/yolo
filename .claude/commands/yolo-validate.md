---
description: Run the YOLO change-validation suite — evaluate (4 layers), surface prioritized improvements, optionally apply fixes, then iterate to green. Maintainer tooling; explicit-invoke only.
argument-hint: "[--quick] [--fix] [--auto] [target]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Task
---

You are running the YOLO change-validation loop documented in `docs/validation/README.md`.
Goal: determine whether the current state of the YOLO framework (skills + conventions +
templates + docs) is correct and genuinely helpful, surface concrete improvements, and —
when authorized — apply them and re-validate until green. This is a closed loop:
**evaluate → synthesize → gate → act → iterate → report.**

Arguments: `$ARGUMENTS`
- (none) → full evaluate + report, then STOP for confirmation before any fix.
- `--quick` → Layer 1 only (objective git harness). No agents, no fixes. Fast sanity check.
- `--fix` → after presenting findings, apply the agreed fixes, then iterate.
- `--auto` → no confirmation gate; apply high-confidence fixes and iterate autonomously, but
  STILL stop for anything touching landing/merge semantics, destructive changes, or
  low-confidence judgment calls.
- a `target` (branch name, `diff`, or path) → scope to that change. Default = working tree vs `HEAD`.

## Cost & gating
Layer 1 is free and objective. Layers 2-4 spawn subagents (billed). Honor YOLO's own
cheap-vs-billed contract (`.claude/yolo/conventions.md`): evaluation runs, but STOP before
acting unless `--fix`/`--auto`. Beware **correlated error** — do not let one agent both
propose and bless a change; use the adversarial/swapped-order methods the suite prescribes.

## Phase 1 — Evaluate (skip 2-4 if `--quick`)
1. **Layer 1 — objective, AI-free.** Run `bash docs/validation/git-acceptance/run.sh`. A red
   here is a hard failure; capture which case failed. No opinion required.
2. **Layer 2 — adversarial red-team.** Spawn a subagent with a hostile stance ("guilty until
   proven innocent") over the target diff: find git/gh commands that won't run, internal
   contradictions, config keys cited-but-undefined (cross-check `templates/config.yaml`),
   and logic holes in the status derivation. It MUST reproduce findings with real `git`/`gh`,
   not speculate. Pattern: `docs/validation/adversarial/`.
3. **Layer 3 — behavioral.** For each scenario in `docs/validation/behavioral/scenarios.md`
   (plus any new decision point the target introduces), spawn a subagent that reads ONLY the
   relevant `SKILL.md` + `conventions.md` and reports the decision the instructions yield;
   PASS/FAIL vs expected. Flag instructions ambiguous enough to be misread.
4. **Layer 4 — blind A/B.** For each user-facing doc changed in the target (`README.md`,
   `conventions.md`, `getting-started.md`), extract OLD (`git show HEAD:<file>`) vs NEW
   (working tree), write both to neutral filenames in the scratchpad, and present them
   unlabeled as Variant A/B to **two** judge subagents with the A/B order **swapped** between
   them. Score on the rubric in `docs/validation/ab-judge/rubric.md`. Agreement across the
   swap is the signal; a split means investigate. Keep the answer key yourself; judges must
   not know which variant is the revision.

## Phase 2 — Synthesize
Merge all findings into ONE prioritized list: severity (high/med/low), `file:line`, the
problem, the concrete fix. Separate **objective failures** (Layer 1 red, broken commands)
from **judgment improvements**. Explicitly state what is solid — what the adversarial agent
tried hardest to break and could NOT.

## Phase 3 — Gate
Present the list. Unless `--fix`/`--auto`, STOP and ask which fixes to apply.

## Phase 4 — Act
Apply the authorized fixes. For EVERY confirmed git-level finding, also add a regression
case to `docs/validation/git-acceptance/run.sh` so it can never silently return. Keep
`conventions.md` and the skills that cite it in sync (conventions is the source of truth).

## Phase 5 — Iterate
Re-run Layer 1 (always) and re-run any failed Layer 3 scenarios. Repeat Act → Iterate until
**Layer 1 is green AND no high-severity finding remains**, or **3 iterations** are reached —
then report what is left rather than looping forever.

## Phase 6 — Report
Summarize: layers run, pass/fail counts, findings by severity, fixes applied, regression
cases added, final harness state, and any residual items. Recommend dogfooding one real
feature end-to-end as the final human check. Do NOT commit unless the user asks.
