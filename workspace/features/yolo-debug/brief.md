---
slug: "yolo-debug"
goal: "Systematically debug a reported problem (reproduce → root-cause → fix → regression-proof) and capture the investigation as one committed debug artifact, with no stored session state."
success_criteria:
  - "A skill exists at .claude/skills/yolo-debug/SKILL.md with valid name/description frontmatter, discoverable as a yolo-* act."
  - "The skill defines a stateless investigation flow (reproduce → hypothesize → isolate → fix → verify) and writes exactly one committed artifact (a debug record under workspace/), with NO persistent state machine or status field."
  - "The skill cites .claude/yolo/conventions.md for trailers/derivation instead of paraphrasing them, consistent with the other yolo-* skills."
  - "The routing block's 'Bug reports' line routes bug intent to yolo-debug (no longer 'v4 has no debug act'); README skills table and getting-started reflect the new act."
  - "A bug-report prompt (e.g. 'fix the 500 on login') routes to yolo-debug per the updated routing block, while feature intent still routes to yolo-feature."
milestone: null
depends_on: []
intake_refs: []
cancelled: false
created_at: "2026-07-02T00:00:00Z"
---

# yolo-debug — a systematic debugging act

## Motivation
v4 deliberately demolished the v2 command/script framework, and in doing so dropped the
`debug` act. The gap has surfaced three times: the cherrypick repo still carries the old v2
debug act, the auto-detect routing block currently routes bug reports "directly" with an
explicit "v4 has no `debug` act yet (a `yolo-debug` skill is a known gap)" note, and the
`auto-vs-explicit-routing` decision (`workspace/decisions/auto-vs-explicit-routing.md`)
records "a `yolo-debug` skill lands → update the taxonomy" as a revisit trigger.

## Shape (decided at intent capture)
A **stateless reasoning act**, in the mold of `yolo-decide` / `yolo-research`: a disciplined
investigation flow — **reproduce → hypothesize → isolate → fix → verify** — that produces ONE
committed artifact (a debug record) and links the fix. No persistent debug-session state
machine (that would reintroduce the stored status v4 removed). It aligns with git-as-truth:
the investigation and its resolution live in the artifact + the fix commit, nothing tracked
separately.

## Constraints
- Must fit the v4 conventions: cite `conventions.md`, don't paraphrase trailer/derivation
  strings; no stored status field.
- Must integrate with routing: bug intent routes here; when a fix balloons into new
  capability, hand off to `yolo-feature`.
- Prior art to mine (research): the old v2 debug act at `cherrypick 7a01ef9`
  (`.claude/yolo/agents/debug.md`, `workflows/debug.md`, `commands/yolo/debug.md`) — take the
  useful investigative structure, drop the stored-session-state machinery.

## Reference material
- `../cherrypick-yolo` @ `7a01ef9` — old v2 debug act (structure to adapt).
- `.claude/skills/yolo-decide/SKILL.md`, `yolo-research/SKILL.md` — the stateless-act shape to match.
- `.claude/yolo/conventions.md` — trailers, derivation, the two gates.
