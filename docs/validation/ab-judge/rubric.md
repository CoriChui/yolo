# Blind A/B judge — method + rubric

For user-facing prose changes (README, conventions, getting-started) where "better" is a
judgment, not a git fact. Absolute 1-10 scores from a single judge are noise; a forced
comparison between two variants is far more reliable.

## Method

1. Extract the two variants. Since edits are often uncommitted, OLD = `git show HEAD:<file>`,
   NEW = the working tree. Write both to neutral filenames (`variant-A`, `variant-B`).
2. **Randomize and record the mapping** in a manifest the judges never see.
3. Spawn ≥2 judge agents. **Swap the A/B order between judges** so position bias cancels:
   if judge-1 sees A=OLD/B=NEW, judge-2 sees A=NEW/B=OLD. Prefer a different model than the
   one that authored the change (breaks correlated error).
4. Tell judges they do NOT know which variant is the revision. Force a winner per document.
5. Have judges consult the ACTUAL tree so "accuracy" is grounded (a variant that promises
   commands/files that don't exist must score low).
6. **Agreement across swapped positions on the same underlying file = real signal.** A split
   means position bias or a genuine toss-up — investigate.

## Rubric (score each variant 1-10, justify with quotes)

| Dimension | Question |
|---|---|
| Accuracy | Does it describe the system that actually exists? Check every referenced command/file/dir against the tree. |
| New-user task success | Could a newcomer follow only this doc to set up + ship one feature? Where do they get stuck? |
| Mental-model clarity | Are git-as-truth, derived status, skills-as-acts, cheap-vs-billed conveyed? |
| Completeness | Config reference, glossary, getting-started path, where to look next. |

## 2026-06-27 result

| Document | Judge-1 (order A) | Judge-2 (swapped) | Verdict |
|---|---|---|---|
| README | NEW (acc 9 vs 2) | NEW (acc 9 vs 2) | **NEW wins**, unanimous across swap |
| conventions | NEW (compl 9 vs 3) | NEW (compl 9 vs 4) | **NEW wins**, unanimous across swap |

Both judges, independently and with order swapped, picked the NEW variants decisively — the
OLD README makes fictional claims (deleted slash commands + scripts), the OLD conventions
lacks the durable-done layer. Acted-on weakness both judges named: the README lacked a
worked example → a 4-5 line example transcript was added.
