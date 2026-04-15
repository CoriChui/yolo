---
name: yolo:status
description: Use when you need orientation after a context reset, want to know which features are in progress, or suspect the state is stuck. Reconciles all feature files against git evidence.
argument-hint: ""
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
---

<objective>
Display overall project status by reconciling all feature files against git evidence.
Reports each feature's derived step, drift status, and suggests next actions.
Note: Write/Edit are needed for --fix reconciliation (crash recovery corrections).
</objective>

<context>
Arguments: $ARGUMENTS
</context>

<process>

1. **Discover feature files:** `ls .planning/features/*.md 2>/dev/null` (exclude `done/` subdirectory)
2. **For each feature file:**
   - Read the `goal:` and `branch:` from frontmatter
   - Run: `bash scripts/yolo-cli/reconcile.sh {feature_file} --repo .`
   - Parse the "Current Step" line from output
   - Note any drift items
3. **Also check done features:** `ls .planning/features/done/*.md 2>/dev/null`
4. **Display summary table:**
   ```
   YOLO v2 Status
   ══════════════════════════════════════
   Active Features:
     {slug}  step: {step}  branch: {branch}  drift: {count}
     ...
   Completed Features: {count}
   ```
5. **If $ARGUMENTS contains "--fix":** re-run reconcile with `--fix` on all features with drift
6. **Suggest next action** based on the active feature's step:
   - `think` → "Run `/yolo:start` to continue planning"
   - `plan` → "Plan exists but no tasks started — run `/yolo:start` to begin execution"
   - `do` → "Run `/yolo:start` to resume executing remaining tasks"
   - `do-fix` → "Verification failed — run `/yolo:start` to fix and re-check"
   - `check` → "All tasks done — run `/yolo:start` to verify"
   - `ship` → "Verified — run `/yolo:start` to ship"
   - `done` → "Feature is complete"

</process>
