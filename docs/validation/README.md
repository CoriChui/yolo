# YOLO change-validation suite

A layered way to answer "are these changes actually helpful?" for a **prompt/skill
framework** (where most changes are instructions an LLM follows, not code with unit tests).
The layers run from most-objective to most-subjective. The guiding principle: **the most
trustworthy signal is the one that does not route through an LLM's judgment** — so push as
much as possible down to layer 1, and treat the LLM layers as corroboration, not proof.

Beware **correlated error**: the model that proposes a change shares the blind spots that
would make it bless the change. Independence (different framing, swapped order, adversarial
stance, mechanical ground truth) is what makes a green result mean something.

## Running it: `/yolo-validate`

The whole loop is packaged as the `/yolo-validate` slash command
(`.claude/commands/yolo-validate.md`) — **evaluate → synthesize → gate → act → iterate →
report**. It is maintainer tooling, explicit-invoke only (never auto-triggers).

```
/yolo-validate            # full evaluate + report, STOP before any fix
/yolo-validate --quick    # Layer 1 only (objective harness), no agents
/yolo-validate --fix      # apply agreed fixes, then re-validate to green
/yolo-validate --auto     # autonomous fix+iterate (still stops for risky/landing changes)
```

The command answers "is this change helpful?" end-to-end: it does NOT just evaluate — it
surfaces prioritized improvements, applies the authorized ones (adding a regression case for
every git-level fix), and iterates until Layer 1 is green and no high-severity finding
remains. The gate before "act" mirrors YOLO's own cheap-vs-billed contract.

## Layer 1 — Git acceptance harness (objective, AI-free)  ✅ 26/26

`git-acceptance/run.sh` — builds throwaway repos, runs the EXACT git commands the
conventions specify, asserts the classification. Where a fix changed a rule, the case
asserts the OLD rule was wrong (red) and the NEW rule is right (green) — genuine red→green
proof. Covers the durable done-marker (F1/F2), the empty-branch false-positive regression
(F4), three-dot diff (F3), task dedup (F5), base detection (F6), worktree order (F7), the
verified-then-reworked tip-vs-range regression (F8), the verified-trailer-without-a-
committed-verification.md regression (F9), and the PR-body done-trailer-placement regression
(F10 — a trailer with prose after it silently fails `%(trailers:…)`, so it must be the
message's final standalone paragraph).

```sh
bash docs/validation/git-acceptance/run.sh   # exit 0 = all green
```

This is the keystone: it validates the high-severity fixes without any LLM in the loop.

## Layer 2 — Adversarial red-team (independent, hostile)

Spawn a fresh agent told *nothing was approved*, tasked to BREAK the new version: git
commands that won't run, contradictions the edits introduced, config keys cited but
undefined, logic holes. This is what catches regressions created *by the fix itself*. The
2026-06-27 run found 5 real defects in the first round of edits (invalid `git merge
--trailer`, `git fetch` refspec into a checked-out branch, `gh pr merge --sha` →
`--match-head-commit`, the FF-can't-carry-trailer contradiction, and the `git branch
--merged` empty-branch false-positive). All fixed and re-proven in layer 1. See
`adversarial/findings-2026-06-27.md`.

## Layer 3 — Behavioral eval (does the instruction drive the right decision?)

`behavioral/scenarios.md` — fixture states + user intents + the expected decision at each
gate. An agent reads only the relevant SKILL.md + conventions (as the executing agent
would) and reports the decision it yields. Because LLM behavior is stochastic, run each
scenario N times and track a pass *rate*; a single green run proves nothing. The 2026-06-27
run scored 5/6 robust, 1 fragile (resume-guard slug derivation — since tightened).

## Layer 4 — Blind A/B judge panel (for subjective quality)

`ab-judge/rubric.md` — for prose changes (README, conventions), absolute scores are noise;
comparison isn't. Extract old + new (old = `git show HEAD:<file>`), present them as
unlabeled Variant A/B to ≥2 judge agents **with the order swapped between judges** to cancel
position bias, ideally a different model than wrote the change. Agreement across swapped
positions = real signal. The 2026-06-27 run: both judges, swapped, picked the NEW README
and NEW conventions decisively (accuracy 9 vs 2).

## The discipline under all of it

Define the success metric *before* measuring, per change. "Helpful" is undefined until you
name the observable that would prove it. A fix that can't be turned into an assertion or a
judged comparison is a fix to be suspicious of.

| Change | Metric | Layer |
|---|---|---|
| Durable done-marker (F1/F2) | shipped+deleted feature derives `done` | 1 |
| Three-dot diff (F3) | base advance doesn't inflate the diff | 1 |
| Task dedup (F5) | one task over N commits counts once | 1 |
| Base detection (F6) | resolves non-main/master defaults | 1 |
| Worktree order (F7) | cleanup doesn't error | 1 |
| No new broken commands | every git/gh command runs as written | 2 |
| Gating / resume / verify-loop | instructions yield the right decision | 3 |
| README / conventions clarity | new-user task success, accuracy | 4 |

## Re-running after future changes

1. `bash git-acceptance/run.sh` (must stay green; add a case for each new rule).
2. Re-run the adversarial agent on the diff.
3. Re-run the behavioral scenarios (add scenarios for new decision points).
4. Re-run the blind A/B panel on any reworded user-facing doc.
5. Dogfood: run one real feature end-to-end through the changed skills.
