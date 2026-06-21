---
name: yolo-decide
description: Use when facing a design or architecture decision that benefits from multiple perspectives before committing. Produces a decision record under workspace/decisions/. Triggers on "help me decide X vs Y", "which approach", "should we use A or B".
---

# yolo-decide

Reach a defensible decision via multi-perspective analysis, and record it.

## Procedure
1. State the decision and the options crisply.
2. Argue each option from several lenses — at minimum correctness/risk, simplicity/maintainability, and pragmatism/cost. Surface the strongest case FOR and AGAINST each.
3. Recommend one option, with explicit rationale, the alternatives considered, dissents (minority concerns worth recording), and revisit triggers (conditions that should reopen this).
4. Write `workspace/decisions/<slug>.md` with: decision, rationale, approach, alternatives_considered, dissents, revisit_triggers, confidence. Confirm before overwriting an existing slug.
5. Commit (`chore: decision <slug>`).

## Constraints
- Read-only with respect to code; the only file you write is the decision record.
- No status field; decisions are standalone records.
