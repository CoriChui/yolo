# Research — yolo-debug (a stateless debugging act)

Read-only exploration feeding `yolo-plan`. Goal per brief: a stateless `yolo-debug` skill —
reproduce → hypothesize → isolate → fix → verify — that writes ONE committed debug artifact
with no stored session state (`workspace/features/yolo-debug/brief.md:3-9`).

---

## Key findings — the v2 debug act, keep vs drop

The v2 debug act was **three coupled files**: a read-only investigation agent, a
stateful orchestration workflow, and a slash-command entrypoint.

### What v2 did (investigative substance — worth keeping)

The **agent** (`priorart/v2-agent-debug.md`) is the reusable reasoning core:
- An "Iron Law" up front — `NO ROOT CAUSE CLAIM WITHOUT AN EVIDENCE CHAIN / NO HYPOTHESIS
  WITHOUT A PLAN FOR A FAILING TEST / NO SYMPTOM-FIXING` (`v2-agent-debug.md:9-13`), with the
  evidence-before-claims principle "If you can't cite file:line, it's not evidence"
  (`v2-agent-debug.md:99`). This maps cleanly onto the v4 house rule "cite `file:line`; do not
  invent APIs" (`yolo-research/SKILL.md:26`).
- **Four investigative phases, each with an exit condition** (`v2-agent-debug.md:29`):
  Phase 1 Reproduce & Characterize (categorize the bug: crash / wrong-output / performance /
  flaky / integration / configuration — `v2-agent-debug.md:31-48`); Phase 2 Trace (follow
  evidence backward from the failure site, record file:line at each step, compare to a working
  sibling path, check recent changes, budget ~5-8 Read/Grep ops — `v2-agent-debug.md:50-66`);
  Phase 3 Hypothesize (one-sentence hypothesis that must explain ALL observations, design a
  failing test, rate confidence high/medium/low — `v2-agent-debug.md:68-82`); Phase 4 Scope the
  Fix (name files, describe the minimal change, list regression checks and over-scope traps —
  `v2-agent-debug.md:84-93`).
- A **rationalizations table** (12 rows — "I recognize this error message…", "the fix is
  obvious…", "stack trace points to X so the bug is at X…" — `v2-agent-debug.md:107-120`) and a
  **Red Flags — STOP** list (`v2-agent-debug.md:122-134`). This is the highest-value, most
  distinctive content and has no equivalent in the current v4 skills; it is the reason a debug
  act is worth having as its own skill rather than ad-hoc fixing.

The **workflow** (`priorart/v2-workflow-debug.md`) adds the process spine: an Iron Law "No fix
without a reproducer. No claimed resolution without the reproducer turning green"
(`v2-workflow-debug.md:6`), a **five-phase run** (Reproduce → Investigate → Hypothesize
[failing-test-first] → Fix → Verify & Close — `v2-workflow-debug.md:73-201`), and a strong
**"failing test first"** discipline (no fix permitted without a test that currently fails for
the hypothesized reason — `v2-workflow-debug.md:129-151`) plus a verify gate that re-runs the
reproducer AND the full suite *in the same response* before claiming resolved
(`v2-workflow-debug.md:194-198`).

### What v2 stored (the state machinery — drop it all)

This is exactly the machinery v4 demolished and must NOT return:
- **A persistent session directory** `.planning/debug-sessions/{id}/` with five files —
  `session.yaml`, `reproducer.md`, `investigation.md`, `hypothesis.md`, `fix.md` — surviving
  `/clear` (`v2-workflow-debug.md:34-40`, `:297`).
- **A `session.yaml` status machine**: `status: investigating|hypothesizing|fixing|verifying|
  resolved|abandoned` and `phase: reproduce|investigate|hypothesize|fix|verify`, plus
  `current_hypothesis`, `confidence`, `root_cause`, `fix_commit`, `fix_branch`, and a
  `session.{last_action,resume}` resume pointer (`v2-workflow-debug.md:46-65`).
- **Global `state.yaml` integration** — every phase boundary re-reads `.planning/state.yaml`
  under a TOCTOU guard and writes `session.last_action`/`session.resume` so `/yolo:status`
  can surface active debug work (`v2-workflow-debug.md:9-16`, and repeated at every phase, e.g.
  `:67,:79-80,:121,:149,:188,:198`).
- **Four subcommands** `new|resume|list|end` (`v2-command-debug.md:22-27`,
  `v2-workflow-debug.md:205-266`), session-ID generation with collision suffixes
  (`v2-workflow-debug.md:32`), and per-phase framework commits ("chore: open debug session
  {id}", "debug({id}): investigation complete", "chore: resolve debug session {id}" —
  `v2-workflow-debug.md:69,:123,:199`).

**Why drop it:** conventions.md is explicit that "the v2 `state.yaml`/`release.yaml`/
`feature.yaml` status machine, its locks, TOCTOU guards, and retry counters are deleted"
(`conventions.md:179-182`), and YOLO "stores **no tracked status**… state is **derived**"
(`conventions.md:3-5`). A `session.yaml` status field is precisely the anti-pattern. The brief
forbids it: "NO persistent state machine or status field" (`brief.md:6`).

### The keep/drop line for v4

| v2 element | Verdict | Where it goes in v4 |
|---|---|---|
| Iron Law (reproducer + evidence chain, no symptom-fixing) | **Keep** | Top of the SKILL body |
| Bug categorization (crash/wrong-output/flaky/…) | **Keep** | Reproduce step |
| Backward data-flow trace with file:line evidence chain | **Keep** | Isolate step |
| One-sentence hypothesis explaining ALL observations + confidence | **Keep** | Hypothesize step |
| Failing-test-first before any fix | **Keep** | Fix step |
| Verify: re-run reproducer + suite in the same response | **Keep** | Verify step |
| Rationalizations table + Red Flags | **Keep (condensed)** | A short "Discipline" block; v4 skills are terse (see below) |
| Read-only investigate / apply-fix separation (two agents) | **Drop / collapse** | v4 acts are single skills; one stateless skill does the whole arc |
| `.planning/debug-sessions/{id}/` five-file dir | **Drop** | Replaced by ONE artifact (see Artifact design) |
| `session.yaml` status/phase machine + resume pointer | **Drop** | No status field at all |
| Global `state.yaml` updates / TOCTOU | **Drop** | Status is derived; debug isn't a lifecycle state |
| `new/resume/list/end` subcommands | **Drop** | A skill is invoked from intent, not sub-dispatched |
| Per-phase framework commits | **Drop** | One artifact commit + the fix commit(s) |

Note the tension to resolve for the planner: v2 spread the work over multiple `/clear`-
surviving sessions (`resume`), which is *why* it stored phase state. A stateless v4 act runs
the arc **in one pass**; if interrupted, the committed artifact + git are the only memory.
That is the correct v4 tradeoff (`conventions.md:178-179` "a computed view cannot drift").

---

## The v4 act pattern (mirror this exactly)

Every v4 act is a single `SKILL.md` under `.claude/skills/<name>/`. The shape, from
`yolo-decide`, `yolo-research`, `yolo-verify`:

**Frontmatter** — only two keys, `name` and `description`:
```
---
name: yolo-<act>
description: Use when <trigger>. Produces <artifact>. Triggers on "<phrase>", "<phrase>".
---
```
(`yolo-decide/SKILL.md:1-4`, `yolo-research/SKILL.md:1-4`, `yolo-verify/SKILL.md:1-4`.) The
`description` is the machine auto-trigger — the routing block says so explicitly
(`claude-routing-block.md:6-7`: "the machine auto-triggers live in each skill's
`description`"). It must open with "Use when…" and end with concrete "Triggers on" quotes.

**Body** — a one-line statement of purpose, then a small set of `##` sections. The recurring
section vocabulary across the three exemplars:
- `## Inputs` — what the act reads (`yolo-research/SKILL.md:10-12`, `yolo-verify/SKILL.md:10-11`).
- `## Procedure` — numbered steps (`yolo-decide/SKILL.md:9-16`, `yolo-research/SKILL.md:14-19`,
  `yolo-verify/SKILL.md:13-16`).
- `## Output` / `## Outcome` — the single artifact written + its commit line
  (`yolo-research/SKILL.md:20-21`, `yolo-verify/SKILL.md:18-21`).
- `## Constraints` — the guardrails, each **citing conventions.md rather than restating it**
  (`yolo-decide/SKILL.md:18-21`, `yolo-research/SKILL.md:23-26`, `yolo-verify/SKILL.md:23-25`).

**Tone / house rules the body must obey:**
- Terse and imperative; second person ("You gather the context… you change nothing" —
  `yolo-research/SKILL.md:8`). Total length ~20-25 lines, not the 200-line v2 agent.
- **Cite, don't paraphrase.** Trailer/derivation/gate strings are referenced as
  "`.claude/yolo/conventions.md` *Section*", never restated — required by
  `conventions.md:5-7` and modeled at `yolo-verify/SKILL.md:21`, `yolo-research/SKILL.md:25`.
- **Commit line** uses the framework form `yolo: <act> [<arg>]` (`conventions.md:54-58`), e.g.
  `yolo-research` commits `yolo: research <slug>` (`yolo-research/SKILL.md:21`) and
  `yolo-decide` commits `yolo: decision <slug>` (`yolo-decide/SKILL.md:16`).
- If billed multi-perspective work is involved, run it at a `workspace/config.yaml`
  `agents.<step>` tier and confirm framing first (`yolo-decide/SKILL.md:11,21`). See Open
  Questions re: whether debug needs its own tier.

---

## Integration points (exact files + current text to change)

To register yolo-debug, these surfaces enumerate the acts and currently say a debug act does
not exist. Each must be updated; quoted current text below.

1. **Routing template — the "Bug reports" negative line.**
   `/.claude/yolo/templates/claude-routing-block.md:28-29` currently:
   > `- **Bug reports** — "X is broken", "fix the 500 on login". v4 has no `debug` act yet, so fix`
   > `  directly (a `yolo-debug` skill is a known gap).`
   Must become a **positive route** to `yolo-debug` (per `brief.md:8` success criterion and the
   revisit trigger in `workspace/decisions/auto-vs-explicit-routing.md:80-81`: "A `yolo-debug`
   skill lands → update the taxonomy so bug intent routes there instead of being a pure
   negative"). Decide: does it move out of the "Does NOT route" list entirely into a positive
   route stanza, or stay listed as "routes to yolo-debug, not yolo-feature"? (See Open Qs.)

2. **CLAUDE.md — the synced copy of the same block.**
   `/CLAUDE.md:29-30` carries the identical text:
   > `- **Bug reports** — "X is broken", "fix the 500 on login". v4 has no `debug` act yet, so fix`
   > `  directly (a `yolo-debug` skill is a known gap).`
   The routing block is installed into `CLAUDE.md` by `yolo-init` from the template
   (`yolo-init/SKILL.md:13`, delimited by `<!-- YOLO:routing-block start/end -->`). Both the
   template AND the already-synced CLAUDE.md must be edited so they stay identical (yolo-init
   only re-syncs on the next init/repair run). Also the top-of-file routing prose in
   `CLAUDE.md` (the project-instructions block above the marker) and the "Other YOLO acts"
   line (`CLAUDE.md:31`) may want a debug mention.

3. **CLAUDE.md — the "Other intents" enumeration** and the **"Individual steps"** line
   (`CLAUDE.md:52-57`) and the routing template's equivalents
   (`claude-routing-block.md:51-58`). If debug is presented as an individual act, add it here.

4. **README skills table.** `/README.md:29-40` lists ten acts; there is no debug row. Current
   table ends:
   > `| `yolo-init` | you want to set up (or repair) YOLO in a repo |`
   Add a `yolo-debug` row (e.g. "you have a bug and want a systematic reproduce→fix→verify pass").
   Also the lifecycle sentence `README.md:42-43` enumerates the composed acts — debug is a
   standalone act (like decide/status), so it likely does NOT join that composition line.

5. **getting-started.md.** The glossary/"other things you can say" section
   (`getting-started.md:49-54`) lists standalone acts ("break this epic into features",
   "should we use Postgres or Mongo?", "pull in this Figma"). Add a debug entry (e.g.
   "**\"debug this failure\" / \"why is X breaking?\"** → `yolo-debug`…"). The "Atom / act"
   glossary line (`getting-started.md:77-78`) enumerates "research, plan, execute, verify,
   finish" — debug is a *standalone* act, not part of the feature composition, so treat it
   like decide/status/intake (which are already omitted from that atom list).

6. **The auto-vs-explicit-routing decision record.** `workspace/decisions/auto-vs-explicit-
   routing.md:80-81` names "a `yolo-debug` skill lands" as a revisit trigger. Not a required
   edit, but a planner should note the trigger is now firing; optionally append a note that it
   was actioned (decision records are provenance — `conventions.md:16-18`).

7. **README "The skills" count / config.yaml `agents`.** `workspace/config.yaml:8-15` and the
   template (`.claude/yolo/templates/config.yaml:8-15`) define per-step model tiers
   (research/plan/execute/verify/finish/roadmap/decide). There is **no `agents.debug`**. If
   yolo-debug runs billed sub-analysis at a configured tier (v2 had `agents.debug: opus` —
   `v2-agent-debug.md:2`), add a `debug:` key to both the template and the scaffolded config.
   If it runs inline (like yolo-research/yolo-verify, which don't have their own separate
   tiers beyond the caller's), no config change is needed. (See Open Qs.)

---

## Artifact design

**Path.** conventions.md distinguishes **feature artifacts** (inside
`workspace/features/<slug>/`) from **standalone records** that "live outside the feature
folder" — `workspace/decisions/<slug>.md`, `workspace/intake/<source>/`
(`conventions.md:16-18`). A debug record is a standalone record (a bug is not a feature
lifecycle unit). Recommend a **new sibling dir**, e.g.
`workspace/debug/<YYYY-MM-DD>-<slug>.md` (or `workspace/debug/<slug>/record.md`), consistent
with the decisions layout. This mirrors v2's `{date}-{slug}` id scheme
(`v2-workflow-debug.md:32`) minus the directory-of-state. `yolo-init` scaffolds
`workspace/{features,intake,decisions}/` today (`yolo-init/SKILL.md:11`); a `debug/` dir would
be a new scaffold entry there — OR the skill can `mkdir -p` on first use to avoid touching
init (see Open Qs). Slug derivation can reuse the kebab-case rule used elsewhere
(`yolo-feature/SKILL.md:13`).

**Contents (one file).** Fold the v2 five files into one record: symptom + reproducer;
evidence chain (file:line steps — `v2-agent-debug.md:146-164`); root cause (one sentence);
hypothesis + confidence; the fix (files changed, minimal-change description, over-scope traps
avoided — `v2-agent-debug.md:181-190`); and verification evidence (failing test that now
passes, reproducer no longer reproduces, suite green — modeled on v2 `fix.md`,
`v2-workflow-debug.md:168-186`). It doubles as the human audit surface, exactly as
`verification.md` does for verify (`conventions.md:44-46`).

**Trailers — does debug need a machine signal?** Likely **no new trailer**. The three YOLO
trailers are lifecycle signals — `YOLO-Task` (plan task done), `YOLO-Verified` (criteria
passed), `YOLO-Feature` (feature landed) (`conventions.md:38-42`). Debug is not a feature
lifecycle state, so it needs no derivation trailer. The committed debug record **plus the
normal fix commit(s)** are sufficient evidence — no greppable "done" signal is required
because nothing derives a debug status. The skill should commit the record with the framework
form `yolo: debug <slug>` (consistent with `conventions.md:54-58`) and let the fix land as
ordinary task/commit(s). **Recommendation: no trailer, no status field** — this is the whole
point of "stateless" in the brief (`brief.md:6`).

**Interaction with status derivation.** None. `yolo-status` derives `planned/in-progress/
done/cancelled` for **features** from briefs + branches + trailers
(`conventions.md:70-115`); a debug record has no brief and no `feature/<slug>` branch, so it is
invisible to and independent of status derivation — which is the desired decoupling (v2
deliberately kept debug "independent of releases/features" but then *reintroduced* coupling via
`state.yaml` updates — `v2-workflow-debug.md:9-16,296`; v4 drops that coupling entirely).

---

## Open questions / assumptions (for planner + human)

1. **Branch policy.** Does yolo-debug operate on the current branch, or cut its own
   `debug/<slug>` branch? conventions.md only defines `feature/<slug>` naming
   (`conventions.md:25`); there is no `debug/` branch convention. v2 optionally created a
   `debug/{id}` worktree for large fixes (`v2-workflow-debug.md:133-135`). **Assumption:**
   default to the current branch (a bug fix is often wanted immediately, on whatever branch);
   offer a branch only if the fix is large. Needs confirmation.
2. **Routing placement.** Should "Bug reports" become a full positive route stanza alongside
   `yolo-feature` (`claude-routing-block.md:17-30`), or a line under "Other intents"? And what
   is the **handoff rule** when a fix balloons into new capability → `yolo-feature`
   (`brief.md:38-39`)? The routing block should state that boundary crisply.
3. **Does bug intent need a slug/brief?** Assumption: a slug for the artifact filename, but
   **no brief** (a brief implies a feature with success_criteria — `conventions.md:9-14`). The
   debug record IS the artifact. Confirm the record filename convention
   (`workspace/debug/<date>-<slug>.md` proposed).
4. **`agents.debug` tier?** Add a config key (like v2's `agents.debug: opus`) or run inline
   with the caller's tier? Cheapest is inline (yolo-research/yolo-verify have no dedicated tier
   in the body, though the config lists them). If yolo-debug is only ever invoked directly (not
   composed by yolo-feature), a tier may be unnecessary. Confirm.
5. **Reproducer-absent path.** v2 warned and continued with `reproducer_status: unknown`
   (`v2-workflow-debug.md:43`). Stateless v4 has no status field to set — so the skill should
   just *proceed with a caveat in the record* rather than track a flag. Confirm this is the
   intended degradation.
6. **Does init scaffold `workspace/debug/`?** Editing `yolo-init` (`yolo-init/SKILL.md:11`) to
   add the dir keeps existing repos consistent but touches init; alternatively the skill
   `mkdir -p`s lazily. Recommend lazy-create to keep the change surface small; confirm.
7. **Where does the "failing test first" live?** v2 made it a hard gate
   (`v2-workflow-debug.md:129`). For some bugs (config, perf) a unit test is awkward. Assume:
   strong default ("write the failing test"), with an explicit documented escape for
   non-unit-testable bugs, recorded in the artifact.

---

## Recommended scope boundary

**IN (v1):**
- A single stateless `.claude/skills/yolo-debug/SKILL.md` mirroring the v4 act shape
  (frontmatter + Inputs/Procedure/Output/Constraints), with the reproduce → hypothesize →
  isolate → fix → verify arc and a condensed Iron-Law / Red-Flags discipline block adapted
  from `v2-agent-debug.md:9-13,122-134`.
- Writes exactly ONE committed artifact (proposed `workspace/debug/<date>-<slug>.md`),
  committed `yolo: debug <slug>`, with NO status field and NO new trailer.
- Citations to `conventions.md` for commit-message form and the cite-don't-paraphrase rule;
  no restated trailer strings.
- Integration edits: routing template + synced CLAUDE.md "Bug reports" line → positive route;
  README skills table row; getting-started entry. (Items 1-5 above.)
- A stated handoff rule to `yolo-feature` when a fix becomes new capability.

**OUT (explicitly not v1):**
- Any persistent session state, `session.yaml`, phase/status machine, or resume pointer
  (`brief.md:6`; the whole reason v4 exists — `conventions.md:178-182`).
- `state.yaml`/status-derivation integration — debug is not a feature lifecycle state.
- `new/resume/list/end` subcommands (`v2-command-debug.md:22-27`) and multi-session listing.
- Per-phase framework commits — one artifact commit + the ordinary fix commit(s) only.
- A dedicated read-only "debug agent" separate from an "execute" step — collapsed into one
  skill (revisit only if a separation-of-investigation-and-fix need is demonstrated).
- Auto-creating a `debug/` branch by default and worktree management (defer; current branch
  unless the human asks).
