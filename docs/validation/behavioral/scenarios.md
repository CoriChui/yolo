# Behavioral eval scenarios

Each scenario: a fixture state + a user intent + the decision a faithful agent following the
instructions should reach. Run by giving an agent only the relevant SKILL.md + conventions,
the fixture, and the intent; ask what it would do at the key decision point. Run each N times
(LLM behavior is stochastic) and track a pass rate. Add a scenario for every new decision
point a change introduces.

| # | Fixture | Intent | Expected decision | Source of truth |
|---|---------|--------|-------------------|-----------------|
| 1 | `workspace/features/csv-export/` + `feature/csv-export` exist | "add CSV export" | RESUME at first incomplete step; do NOT re-draft brief | yolo-feature §0 |
| 2 | a `success_criteria` is unmet | (verify runs) | return to execute; re-run verify; do NOT write `YOLO-Verified: true`; do NOT finish | yolo-feature §4, yolo-verify Outcome |
| 3 | default repo | "build X" | research+plan run (authorized by the request, no pre-research stop); STOP at the **plan gate** before execute; STOP at the **ship gate** before merge | conventions *The two gates*, yolo-feature §3/§5 |
| 3b | default repo | "build X, just ship it, don't ask" | plan gate still presented; **ship gate pre-consented** (no merge stop) UNLESS a risk hard-trigger fires | conventions *The two gates*, yolo-finish ship gate |
| 4 | default repo | "Postgres or Mongo?" | confirm framing BEFORE billed `agents.decide` analysis (the plan-gate analogue); skip only if user pre-consented | yolo-decide step 0, conventions *The two gates* |
| 5 | shipped: `yolo/done/<slug>` tag + `YOLO-Feature` trailer on base, branch deleted | "where do things stand?" | status = **done** (not planned) | conventions Deriving status, yolo-status §3 |
| 6 | brief with `cancelled: true` | "where do things stand?" | reported **cancelled**, excluded from active view | yolo-status §3 |

## 2026-06-27 result

5/6 robust (decision pinned in two cross-referenced locations). 1 fragile: scenario 1 —
resume guard depended on the agent independently deriving the same slug as the on-disk
folder, with no slug-derivation rule specified. **Fix applied:** yolo-feature §0 now
specifies kebab-case derivation + case-insensitive + goal-match against existing briefs.
Re-run scenario 1 to confirm the pass rate is now stable.
