---
slug: auto-vs-explicit-routing
date: 2026-07-01
confidence: medium-high
---

# Decision: auto- vs explicit routing into YOLO for feature intent

## Decision

In a YOLO-initialized repo, feature-intent prompts route into `yolo-feature` via
**model-judgment auto-detection with a sharpened taxonomy (Option B)**. A deterministic
`UserPromptSubmit` hook (Option C) is **deferred**, kept as a documented upgrade path gated on
observed evidence. The two-gates safety model and repo-scoping are unchanged either way.

Concretely, "B" means reworking `.claude/yolo/templates/claude-routing-block.md` to add, on top
of the existing positive triggers:
- **Negative examples** that must NOT route: questions ("how does X work?"), typo / one-line
  fixes, refactors, pure exploration, and **bug reports** (noting v4 has no `debug` skill yet).
- **Confidence tiers:** high → route (draft brief, stop at the plan gate); ambiguous → a
  one-line ask ("treat this as a feature via YOLO, or just do it directly?"); low → answer
  normally.
- An explicit **escape phrase** ("just do it, no YOLO / skip the ceremony").
- A **size threshold** — trivial one-file/one-line edits skip the lifecycle entirely.

The routing block stays the **single source of truth** for "what counts as feature intent."

## Rationale

- **The gates make mis-routing cheap.** Intent capture + brief drafting are free and reversible,
  and the plan gate stops before anything expensive/irreversible. So the cost of a false-positive
  is ~one throwaway `brief.md` — optimizing hard against false-positives (Option A's whole value)
  is optimizing the wrong axis.
- **Over-triggering, not under-triggering, is the adoption killer.** The taxonomy sharpening in B
  attacks that failure mode directly with zero new machinery.
- **C duplicates the taxonomy in a dumber language.** A hook regex is a second definition of
  "what is a feature," which contradicts YOLO's founding rule ("do not paraphrase these strings
  elsewhere — cite this file") and creates a regex-vs-prose drift seam. Its only unique benefit
  over B is a deterministic recall floor for *silent* false-negatives — a benefit that cannot be
  justified or tuned until such misses are actually observed.
- B uses mechanisms already present (skill descriptions + the routing block) and stays
  repo-scoped, so it never leaks into non-YOLO projects.

## Approach

1. Rewrite `claude-routing-block.md` per the Decision (positives + negatives + tiers + escape
   phrase + size threshold); keep it the sole taxonomy source.
2. Re-run `/yolo-validate` on the reworded block — blind A/B judge (Layer 4) + a behavioral
   scenario (Layer 3) for a borderline prompt (a question vs a build request) to confirm the
   negatives suppress over-triggering.
3. Leave `yolo-init` install flow as-is (it already installs the block idempotently).
4. Document the deferred hook (C) spec inside this record's revisit triggers as the upgrade path.

## Alternatives considered

- **A — Explicit-only.** Rejected: it is precisely the behavior the maintainer wants to move away
  from; high false-negative rate; under-uses the framework in a repo that opted into it.
- **C — Layered (B + deterministic `UserPromptSubmit` hook).** Not rejected outright — deferred.
  Adds a testable recall floor but at the cost of a taxonomy-duplication drift seam, per-prompt
  noise, and cross-platform hook fragility, for a benefit (catching silent false-negatives) that
  is currently unmeasured.

## Dissents (minority views worth recording)

- **Determinism camp:** relying on model judgment for the *entry point* of a workflow is fragile
  and silent when it fails; the hook is cheap insurance and its testability aligns with YOLO's
  own objective-Layer-1 validation ethos. → Honored by the revisit trigger below.
- **Minimalist camp:** even B may be over-engineering; the current block plus a single escape
  phrase might suffice. → Mitigated by keeping B prose-only and validating the change.

## Revisit triggers

- **Recurring silent false-negatives** — real feature intent repeatedly handled ad-hoc/ungated
  past model judgment → adopt **C** (the hook as a nudge-only recall floor; unit-test the regex;
  install via `yolo-init`). This is the primary condition that flips the decision.
- **Over-triggering persists after tuning** → the problem is precision, not recall; the hook would
  worsen it — revisit the taxonomy/tiers instead, not C.
- **Platform shift** — Claude Code ships a native intent-router, or the skill-description
  auto-trigger mechanism changes materially → re-evaluate the whole routing layer.
- A **`yolo-debug` skill** lands → update the taxonomy so bug intent routes there instead of being
  a pure negative. **(ACTIONED 2026-07-02:** `yolo-debug` shipped on `feature/yolo-debug`; the
  routing block's "Bug reports" line now routes bug intent to `yolo-debug`, with hand-off to
  `yolo-feature` when a fix becomes new capability.**)**
