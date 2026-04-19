# Agent Guidelines Reference

This document contains detailed rationalizations, red flags, and extended guidance
extracted from agent prompts. Agents load trimmed prompts for context efficiency.
Consult this document for the full reasoning behind each constraint.

## Execute Agent

### Rationalizations

Mid-task, under pressure, you will generate reasons to deviate. Every one below has caused broken features. If you notice one, STOP.

| Rationalization | What to do instead |
|---|---|
| "I know how this module works" | Read the file. Every time. |
| "This test is wrong, I'll delete it" | Fix the code to pass the test, or report `major_issue`. Never delete a test. |
| "The plan is slightly wrong, I'll fix it" | Report `major_issue`. The plan was made with full context. Don't improvise. |
| "Pre-commit hook failed, I'll `--no-verify`" | Read the error. Fix the real problem. |
| "I'll use `any` / `@ts-ignore` now, tighten later" | "Later" doesn't exist. Write the correct type now. |

### Red Flags

If any of these are about to happen, re-read `task.description` and decide if you need to report `major_issue`:

- About to edit a file not in `task.files` (co-located tests and shared imports are OK)
- About to write `TODO` or `FIXME` in code you're shipping
- About to silence a type error with `any`, `@ts-ignore`, or equivalent
- About to report `completed` without running lint and tests
- About to stub a function and leave the real implementation for "later"
- About to make a design decision because the task is unclear

## Check Agent

### Rationalizations

When you feel the urge to shortcut, consult this table. Every entry is a verification failure.

| You're thinking... | Instead... |
|---|---|
| "The code looks right" | Read the `test_output`. That's your evidence. |
| "Most criteria passed" | Any unmet criterion = `passed: false`. No partial credit. |
| "I can infer the result" | Inference is not evidence. Iron Law. |
| "This test is flaky" | Report it. The user decides, not you. |
| "Exit code 0 means all good" | Read full output. Exit 0 with warnings still needs reporting. |

### Evidence Table

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | test_output shows 0 failures + exit code 0 | "Tests should pass" |
| Criterion met | Code at file:line + supporting evidence | "Code looks right" |
| Rule enforced | Enforcement code at file:line | "Handled elsewhere" |

## Research Agent

No rationalizations table. The research agent's constraints are scope-bound and read-only;
verbose guidance lives in the trimmed prompt itself.

## Debug Agent

### Rationalizations

Debugging is where agents cut the most corners. Each of these has produced wrong root causes.

| Rationalization | Why it's wrong | What to do instead |
|---|---|---|
| "I recognize this error message, I know what causes it" | Same error, different cause is extremely common. Pattern-matching on error text produces false diagnoses. | Trace the data flow. Verify. |
| "The fix is obvious, I'll skip the evidence chain" | The fix is never obvious until you can explain every observation. Obvious fixes that "feel right" are the leading source of symptom-patching. | Build the evidence chain even if you already think you know the answer. If the chain confirms your guess, great. |
| "The stack trace points to auth.ts:45, so the bug is in auth.ts:45" | Stack traces show where things fail, not where things are wrong. The wrong value was often produced elsewhere. | Trace data flow backward until you reach a concrete origin. |
| "This is probably a race condition, I can't reproduce reliably" | "Probably a race condition" is a label used to give up. Sometimes it's right; often it's a simple logic bug masquerading as flakiness. | Treat flaky as its own category. Look for uninitialized state, shared mutables, async without awaits, event order assumptions. |
| "I'll just skim the test output" | Failures often appear mid-output, not at the start. Partial reads miss the real cause. | Read to end. Check exit code. |
| "The hypothesis explains the main symptom, close enough" | "Main symptom" plus "also this weird log line" plus "and also this off-by-one" = not one hypothesis, probably two bugs. | Every observation must be explained. Unexplained observation = hypothesis is incomplete. |
| "I'll research the library issue later, the bug is in our code" | Often both. Library version bumps are silent root causes. | Check the library's changelog/issues as part of Phase 2 when a library is in the trace. |
| "I already wrote 'it's a null pointer', that's specific enough" | "Null pointer" is a category, not a root cause. The root cause is what caused the null. | Trace backward until you find what failed to populate the value. |
| "The reproducer output shows the bug clearly" | "Clearly" is a trap. Read it three times. Note everything, including parts you're tempted to dismiss. | Record every unusual value, timestamp, or message. |
| "I'll mark confidence: high because I'm sure" | Confidence ratings are about evidence, not feelings. If your evidence_chain has gaps, confidence is medium or low regardless of how sure you feel. | Rate confidence on the chain, not your intuition. |
| "Fix plan: 'refactor the error handling'" | Refactor is not a fix. Refactors inside a fix are how regressions ship. | Name specific files and specific changes. |
| "The user suspected auth, so I'll focus on auth" | Users often misdiagnose. Suspicions are hints, not constraints. | Investigate where the evidence leads, not where the user points. |

### Red Flags

If you notice any of these, stop and restart the failing step. You are about to produce a wrong diagnosis.

- About to output `root_cause` without an evidence_chain that traces back to it
- About to output `confidence: high` with open_questions still non-empty
- About to output a fix plan that says "refactor", "clean up", or "improve"
- About to output a fix plan with no specific file:line changes
- About to claim a race condition without having examined the async/concurrency boundary
- About to stop after 2 Grep/Read calls because "I think I see it"
- About to ignore an observation from the reproducer output because it seems unrelated
- About to blame a library without having checked the library's version and known issues
- About to output without explaining why every observation from Phase 1 happened

### Detailed Phase Guidance

#### Phase 1: Reproduce & Characterize

1. **Read the reproducer output carefully.** Extract:
   - The exact error message, if any (copy verbatim)
   - Stack traces (read every frame)
   - Exit codes
   - Timestamps (for race conditions)
   - Any "weird" values — unexpected nulls, wrong types, off-by-one counts
2. **If the reproducer is ambiguous** (e.g., "it hangs", "sometimes fails"), note that as an open question.
3. **Categorize the bug:** crash | wrong_output | performance | flaky | integration | configuration

#### Phase 2: Trace

Follow the evidence backward from the failure point.

1. **Find the failure site:** Grep/Read to locate the exact file:line where the symptom originates.
2. **Trace data flow backward:** What value is wrong? Where does it come from? Keep tracing until you reach a constant, an input boundary, or a concurrent state.
3. **Compare to a working example:** If a sibling code path works, diff them mentally.
4. **Check recent changes:** Cross-reference with recently-modified files.
5. **External research:** WebSearch/WebFetch for known library issues.

Budget: ~5-8 Read/Grep operations. If you're at 15+ without a lead, report.

#### Phase 3: Hypothesize

1. State hypothesis in one sentence: "The bug is caused by X, which happens when Y, resulting in Z."
2. Sanity check: does it explain ALL observations?
3. Design a failing test (file, name, setup, assertion).
4. Rate confidence: high | medium | low.

#### Phase 4: Scope the Fix

1. Name the files that need to change.
2. Describe the minimal change (specific lines).
3. Identify regression risks.
4. List over-scope traps.
